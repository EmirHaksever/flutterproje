-- Arkadaşlık artık kırılgan `friend_email` yerine `friend_id` (users.id) ile
-- bağlanır. E-posta yalnızca gösterim/geriye uyum için tutulur.
--
-- (avatar_url + avatars bucket zaten 20260901120000_user_avatar.sql ile eklendi.)
--
-- Çalıştırma: proje kökünde  npx supabase db push

begin;

-- ---------------------------------------------------------------------------
-- 1) friends.friend_id: ekle, mevcut e-postalardan doldur, FK + tekil index
-- ---------------------------------------------------------------------------
alter table public.friends
  add column if not exists friend_id uuid references public.users(id) on delete cascade;

update public.friends f
set friend_id = u.id
from public.users u
where f.friend_id is null
  and lower(u.email) = lower(f.friend_email);

-- Kullanıcısı çözülemeyen (silinmiş) eski kayıtları temizle.
delete from public.friends where friend_id is null;

create unique index if not exists friends_user_friend_uq
  on public.friends (user_id, friend_id);

-- ---------------------------------------------------------------------------
-- 2) respond_friend_request: kabul edince friend_id ile iki satır ekler
-- ---------------------------------------------------------------------------
create or replace function public.respond_friend_request(request_id uuid, accept boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_sender uuid;
  v_receiver uuid;
  v_status text;
  v_sender_email text;
  v_receiver_email text;
begin
  select sender_id, receiver_id, status
    into v_sender, v_receiver, v_status
  from public.friend_requests where id = request_id;

  if v_sender is null then raise exception 'İstek bulunamadı'; end if;
  if v_receiver <> v_me then raise exception 'Yetki yok'; end if;
  if v_status <> 'pending' then raise exception 'İstek zaten yanıtlanmış'; end if;

  if not accept then
    update public.friend_requests set status = 'rejected' where id = request_id;
    return;
  end if;

  select email into v_sender_email from public.users where id = v_sender;
  select email into v_receiver_email from public.users where id = v_receiver;

  update public.friend_requests set status = 'accepted' where id = request_id;

  insert into public.friends (user_id, friend_id, friend_email, status)
  values (v_sender, v_receiver, v_receiver_email, 'accepted')
  on conflict (user_id, friend_id) do update set status = 'accepted';
  insert into public.friends (user_id, friend_id, friend_email, status)
  values (v_receiver, v_sender, v_sender_email, 'accepted')
  on conflict (user_id, friend_id) do update set status = 'accepted';

  insert into public.notifications (user_id, message)
  values (v_sender,
    (select coalesce(name, email) from public.users where id = v_me)
    || ' arkadaşlık isteğini kabul etti');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) send_friend_request: "zaten arkadaş" kontrolü friend_id ile
-- ---------------------------------------------------------------------------
create or replace function public.send_friend_request(target_email text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_target uuid;
  v_me uuid := auth.uid();
  v_req uuid;
begin
  if v_me is null then raise exception 'Oturum yok'; end if;

  select id into v_target from public.users
  where lower(email) = lower(trim(target_email));
  if v_target is null then raise exception 'Bu e-posta ile kayıtlı kullanıcı yok'; end if;
  if v_target = v_me then raise exception 'Kendine istek gönderemezsin'; end if;

  if exists (select 1 from public.friends
             where user_id = v_me and friend_id = v_target and status = 'accepted') then
    raise exception 'Zaten arkadaşsınız';
  end if;

  if exists (select 1 from public.friend_requests
             where status = 'pending'
               and ((sender_id = v_me and receiver_id = v_target)
                 or (sender_id = v_target and receiver_id = v_me))) then
    raise exception 'Bekleyen bir istek zaten var';
  end if;

  insert into public.friend_requests (sender_id, receiver_id, status)
  values (v_me, v_target, 'pending') returning id into v_req;

  insert into public.notifications (user_id, message)
  values (v_target,
    (select coalesce(name, email) from public.users where id = v_me)
    || ' sana arkadaşlık isteği gönderdi');

  return v_req;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) remove_friend(uuid): id ile iki yönlü sil (eski text sürümünü kaldır)
-- ---------------------------------------------------------------------------
create or replace function public.remove_friend(other_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_me uuid := auth.uid();
begin
  delete from public.friends
  where (user_id = v_me and friend_id = other_user_id)
     or (user_id = other_user_id and friend_id = v_me);
end;
$$;

drop function if exists public.remove_friend(text);

commit;
