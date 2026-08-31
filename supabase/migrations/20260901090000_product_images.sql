-- Ürün (list_items) fotoğrafı desteği:
--  * list_items.image_url metin kolonu
--  * herkese açık 'product-images' storage bucket'ı + politikalar
--
-- Çalıştırma: proje kökünde  npx supabase db push

begin;

-- ---------------------------------------------------------------------------
-- 1) list_items.image_url
-- ---------------------------------------------------------------------------
alter table public.list_items
  add column if not exists image_url text;

-- ---------------------------------------------------------------------------
-- 2) product-images bucket (herkese açık okuma)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

drop policy if exists "product-images public read" on storage.objects;
create policy "product-images public read" on storage.objects
  for select using (bucket_id = 'product-images');

-- Giriş yapmış kullanıcı yalnızca kendi klasörüne (uid) yükleyebilir.
drop policy if exists "product-images auth insert" on storage.objects;
create policy "product-images auth insert" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "product-images owner update" on storage.objects;
create policy "product-images owner update" on storage.objects
  for update to authenticated using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "product-images owner delete" on storage.objects;
create policy "product-images owner delete" on storage.objects
  for delete to authenticated using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

commit;
