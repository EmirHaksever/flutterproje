-- Faz 4.6 — E-posta ile liste paylaşımı için tek RPC
--
-- Neden: paylaşım istemci tarafında yapılıyordu (users lookup + shared_lists
-- insert + karşı tarafa notification insert). Notifications RLS'i sıkılaştıktan
-- sonra (yalnızca user_id = auth.uid() insert edebilir) karşı tarafa bildirim
-- yazılamıyor. Bu RPC işi sunucuda (SECURITY DEFINER) atomik yapar ve
-- "sahip mi / kullanıcı var mı / zaten paylaşılmış mı" kontrollerini istemci
-- baypas edemeyecek şekilde uygular.
--
-- Çalıştırma: proje kökünde `npx supabase db push`.

begin;

create or replace function public.share_list_by_email(p_list_id uuid, p_email text)
returns text  -- 'ok' | 'self' | 'not_found' | 'already'
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_owner uuid;
  v_target uuid;
  v_my_email text;
  v_list_name text;
begin
  if v_me is null then
    raise exception 'Oturum yok';
  end if;

  select user_id, name into v_owner, v_list_name
  from public.shopping_lists where id = p_list_id;
  if v_owner is null then
    raise exception 'Liste bulunamadı';
  end if;
  if v_owner <> v_me then
    raise exception 'Yalnızca listenin sahibi paylaşabilir';
  end if;

  select email into v_my_email from public.users where id = v_me;
  if lower(trim(p_email)) = lower(v_my_email) then
    return 'self';
  end if;

  select id into v_target from public.users
  where lower(email) = lower(trim(p_email));
  if v_target is null then
    return 'not_found';
  end if;

  if exists (
    select 1 from public.shared_lists
    where list_id = p_list_id and user_id = v_target
  ) then
    return 'already';
  end if;

  insert into public.shared_lists (list_id, user_id, user_email, role, shared_by_user_id)
  values (p_list_id, v_target, lower(trim(p_email)), 'editor', v_me);

  insert into public.notifications (user_id, message)
  values (v_target,
    '"' || coalesce(v_list_name, 'Bir liste') || '" adlı liste seninle paylaşıldı');

  return 'ok';
end;
$$;

commit;

-- Doğrulama:  select proname from pg_proc where proname = 'share_list_by_email';
