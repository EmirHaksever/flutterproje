-- Faz 1.3 — shared_lists RLS sıkılaştırması
--
-- Sorun: shared_lists tablosunda birbiriyle çelişen 7 politika vardı. RLS
-- politikaları OR mantığıyla değerlendirilir; aşağıdaki 3 gevşek politika
-- "giriş yapmış herkes" seviyesinde erişim verdiği için sıkı politikaları
-- işlevsiz bırakıyordu.
--
-- Bu migration YALNIZCA fazla-geniş politikaları kaldırır (erişimi daraltır).
-- Hiçbir tabloyu/veriyi değiştirmez. Geri almak için politikalar yeniden
-- oluşturulabilir (tanımları bu dosyanın altındaki yorumda).
--
-- Çalıştırma: Supabase Dashboard → SQL Editor → yapıştır → Run.

begin;

-- 1) Herkesin herhangi bir paylaşım satırı EKLEMESİNE izin veren politika
drop policy if exists "Allow all authenticated inserts" on public.shared_lists;

-- 2) user_id = auth.uid() koşuluyla, başkasının listesini kendine paylaşmaya
--    izin veren politika (liste sahipliği kontrol edilmiyordu)
drop policy if exists "Allow authenticated users to insert shared_lists" on public.shared_lists;

-- 3) Giriş yapmış herkesin TÜM paylaşım kayıtlarını OKUMASINA izin veren politika
drop policy if exists "Allow authenticated users to select shared_lists" on public.shared_lists;

commit;

-- Kalan (doğru) politikalar:
--   INSERT: "Allow sharing lists by owner"
--           -> auth.uid() = paylaşılan listenin sahibi
--   SELECT: "Allow authenticated users to read their shared lists"
--           "Allow user to view their shared lists"
--           -> auth.uid() = shared_lists.user_id
--   DELETE: "Allow owner to delete shared list entries"
--           -> liste sahibi VEYA paylaşılan kullanıcı
--
-- Doğrulama (çalıştırdıktan sonra beklenen: yukarıdaki 3 isim listede OLMAMALI):
--   select policyname, cmd from pg_policies
--   where schemaname = 'public' and tablename = 'shared_lists'
--   order by cmd, policyname;
--
-- Geri alma (gerekirse):
--   create policy "Allow all authenticated inserts" on public.shared_lists
--     for insert with check (auth.role() = 'authenticated');
--   create policy "Allow authenticated users to insert shared_lists" on public.shared_lists
--     for insert with check (auth.role() = 'authenticated' and auth.uid() = user_id);
--   create policy "Allow authenticated users to select shared_lists" on public.shared_lists
--     for select using (auth.role() = 'authenticated');
