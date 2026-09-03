-- Arkadaş eklerken e-posta yerine isimle arama.
-- Giriş yapmış kullanıcı, adı/e-postası eşleşen kullanıcıları görür
-- (kendisi ve zaten arkadaş olduğu kişiler hariç).
--
-- Çalıştırma: proje kökünde  npx supabase db push

begin;

create or replace function public.search_users(q text)
returns table (id uuid, name text, email text, avatar_url text)
language sql
security definer
set search_path = public, pg_temp
as $$
  select u.id, u.name, u.email, u.avatar_url
  from public.users u
  where length(trim(coalesce(q, ''))) >= 2
    and u.id <> auth.uid()
    and (
      u.name ilike '%' || trim(q) || '%'
      or u.email ilike '%' || trim(q) || '%'
    )
    and not exists (
      select 1 from public.friends f
      where f.user_id = auth.uid()
        and f.friend_id = u.id
        and f.status = 'accepted'
    )
  order by
    (lower(coalesce(u.name, '')) = lower(trim(q))) desc,
    u.name nulls last
  limit 8;
$$;

commit;
