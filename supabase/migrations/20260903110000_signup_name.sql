-- Kayıt sırasında girilen adı public.users.name'e taşı.
-- Uygulama signUp(data: {'name': ...}) gönderiyor; bu da raw_user_meta_data'ya
-- düşüyor. Trigger'ı bunu okuyacak şekilde güncelliyoruz.
--
-- Çalıştırma: proje kökünde  npx supabase db push

begin;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.users (id, email, name)
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data->>'name', '')), '')
  )
  on conflict (id) do update
    set name = coalesce(public.users.name, excluded.name);
  return new;
end;
$$;

commit;
