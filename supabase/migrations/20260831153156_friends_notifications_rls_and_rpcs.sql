-- Faz 4 — Arkadaşlık sistemi + bildirimler: RLS ve RPC'ler
--
-- Sorun tespiti:
--   * public.friends       -> RLS KAPALI (herkes herkesin kaydını görür/değiştirir)
--   * public.friend_requests-> RLS KAPALI
--   * public.notifications  -> RLS AÇIK ama hiç politika yok = tüm erişim reddediliyor
--
-- Bu migration:
--   1) friends / friend_requests üzerinde RLS'i açar ve dar politikalar ekler
--   2) notifications için sahibine dönük politikalar ekler
--   3) İki tarafı da ilgilendiren işlemler için SECURITY DEFINER RPC'ler ekler
--      (arkadaş isteği gönder/yanıtla, arkadaşlıktan çıkar, liste katılımcılarını
--       bilgilendir). Hepsi search_path kilitli.
--
-- Çalıştırma: proje kökünde `npx supabase db push` (kullanıcı çalıştırır).

begin;

-- ---------------------------------------------------------------------------
-- 1) friend_requests
-- ---------------------------------------------------------------------------
alter table public.friend_requests enable row level security;

drop policy if exists fr_select on public.friend_requests;
create policy fr_select on public.friend_requests
  for select using (sender_id = auth.uid() or receiver_id = auth.uid());

drop policy if exists fr_insert on public.friend_requests;
create policy fr_insert on public.friend_requests
  for insert with check (sender_id = auth.uid() and receiver_id <> auth.uid());

-- Alıcı isteği reddedebilir/işleyebilir; gönderen ise geri çekmek için siler.
drop policy if exists fr_update on public.friend_requests;
create policy fr_update on public.friend_requests
  for update using (receiver_id = auth.uid());

drop policy if exists fr_delete on public.friend_requests;
create policy fr_delete on public.friend_requests
  for delete using (sender_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2) friends
-- ---------------------------------------------------------------------------
alter table public.friends enable row level security;

drop policy if exists friends_select on public.friends;
create policy friends_select on public.friends
  for select using (user_id = auth.uid());

drop policy if exists friends_insert on public.friends;
create policy friends_insert on public.friends
  for insert with check (user_id = auth.uid());

drop policy if exists friends_update on public.friends;
create policy friends_update on public.friends
  for update using (user_id = auth.uid());

drop policy if exists friends_delete on public.friends;
create policy friends_delete on public.friends
  for delete using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) notifications  (RLS zaten açık; politikalar ekleniyor)
-- ---------------------------------------------------------------------------
drop policy if exists notif_select on public.notifications;
create policy notif_select on public.notifications
  for select using (user_id = auth.uid());

drop policy if exists notif_insert on public.notifications;
create policy notif_insert on public.notifications
  for insert with check (user_id = auth.uid());

drop policy if exists notif_update on public.notifications;
create policy notif_update on public.notifications
  for update using (user_id = auth.uid());

drop policy if exists notif_delete on public.notifications;
create policy notif_delete on public.notifications
  for delete using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4) RPC'ler
-- ---------------------------------------------------------------------------

-- Arkadaş isteği gönder. E-postadan kullanıcıyı bulur, kendine/var olana engel.
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
  if v_me is null then
    raise exception 'Oturum yok';
  end if;

  select id into v_target
  from public.users
  where lower(email) = lower(trim(target_email));

  if v_target is null then
    raise exception 'Bu e-posta ile kayıtlı kullanıcı yok';
  end if;
  if v_target = v_me then
    raise exception 'Kendine istek gönderemezsin';
  end if;

  -- Zaten arkadaş mı?
  if exists (
    select 1 from public.friends
    where user_id = v_me
      and lower(friend_email) = lower(trim(target_email))
      and status = 'accepted'
  ) then
    raise exception 'Zaten arkadaşsınız';
  end if;

  -- Bekleyen istek var mı (her iki yönde)?
  if exists (
    select 1 from public.friend_requests
    where status = 'pending'
      and ((sender_id = v_me and receiver_id = v_target)
        or (sender_id = v_target and receiver_id = v_me))
  ) then
    raise exception 'Bekleyen bir istek zaten var';
  end if;

  insert into public.friend_requests (sender_id, receiver_id, status)
  values (v_me, v_target, 'pending')
  returning id into v_req;

  -- Alıcıya bildirim
  insert into public.notifications (user_id, message)
  values (v_target,
    (select coalesce(name, email) from public.users where id = v_me)
    || ' sana arkadaşlık isteği gönderdi');

  return v_req;
end;
$$;

-- İsteği yanıtla (kabul/ret). Sadece alıcı çağırabilir.
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
  from public.friend_requests
  where id = request_id;

  if v_sender is null then
    raise exception 'İstek bulunamadı';
  end if;
  if v_receiver <> v_me then
    raise exception 'Bu isteği yanıtlama yetkin yok';
  end if;
  if v_status <> 'pending' then
    raise exception 'İstek zaten yanıtlanmış';
  end if;

  if not accept then
    update public.friend_requests set status = 'rejected' where id = request_id;
    return;
  end if;

  select email into v_sender_email from public.users where id = v_sender;
  select email into v_receiver_email from public.users where id = v_receiver;

  update public.friend_requests set status = 'accepted' where id = request_id;

  insert into public.friends (user_id, friend_email, status)
  values (v_sender, v_receiver_email, 'accepted')
  on conflict do nothing;
  insert into public.friends (user_id, friend_email, status)
  values (v_receiver, v_sender_email, 'accepted')
  on conflict do nothing;

  insert into public.notifications (user_id, message)
  values (v_sender,
    (select coalesce(name, email) from public.users where id = v_me)
    || ' arkadaşlık isteğini kabul etti');
end;
$$;

-- Arkadaşlıktan çıkar (iki tarafı da temizler).
create or replace function public.remove_friend(friend_email_param text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_my_email text;
begin
  select email into v_my_email from public.users where id = v_me;

  delete from public.friends
  where user_id = v_me and lower(friend_email) = lower(trim(friend_email_param));

  delete from public.friends
  where lower(friend_email) = lower(v_my_email)
    and user_id = (select id from public.users
                   where lower(email) = lower(trim(friend_email_param)));
end;
$$;

-- Bir listedeki tüm katılımcılara (çağıran hariç) bildirim yaz.
-- list_detail.dart'taki client-tarafı bildirim döngüsünün yerine geçer.
create or replace function public.notify_list_participants(p_list_id uuid, p_message text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_owner uuid;
  r record;
begin
  select user_id into v_owner from public.shopping_lists where id = p_list_id;
  if v_owner is null then
    raise exception 'Liste bulunamadı';
  end if;

  -- Çağıran listeye erişebiliyor mu? (sahip veya paylaşılan)
  if v_me <> v_owner and not exists (
    select 1 from public.shared_lists
    where list_id = p_list_id and user_id = v_me
  ) then
    raise exception 'Bu liste için bildirim gönderme yetkin yok';
  end if;

  if v_owner <> v_me then
    insert into public.notifications (user_id, message) values (v_owner, p_message);
  end if;

  for r in
    select user_id from public.shared_lists
    where list_id = p_list_id and user_id <> v_me
  loop
    insert into public.notifications (user_id, message) values (r.user_id, p_message);
  end loop;
end;
$$;

commit;

-- Doğrulama:
--   select tablename, count(*) from pg_policies
--   where schemaname='public' and tablename in ('friends','friend_requests','notifications')
--   group by tablename;   -- her biri 4 olmalı
--   select proname from pg_proc where proname in
--   ('send_friend_request','respond_friend_request','remove_friend','notify_list_participants');
