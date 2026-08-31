-- Push bildirim için cihaz FCM token'ları.
--
-- Çalıştırma: proje kökünde  npx supabase db push

begin;

create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  platform    text,
  updated_at  timestamptz not null default now()
);

create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists device_tokens_select on public.device_tokens;
create policy device_tokens_select on public.device_tokens
  for select using (user_id = auth.uid());

drop policy if exists device_tokens_insert on public.device_tokens;
create policy device_tokens_insert on public.device_tokens
  for insert with check (user_id = auth.uid());

-- Aynı cihaza başka kullanıcı giriş yaparsa token satırının sahibi değişebilsin
-- (ama yalnızca kendine atayabilir).
drop policy if exists device_tokens_update on public.device_tokens;
create policy device_tokens_update on public.device_tokens
  for update using (true) with check (user_id = auth.uid());

drop policy if exists device_tokens_delete on public.device_tokens;
create policy device_tokens_delete on public.device_tokens
  for delete using (user_id = auth.uid());

commit;
