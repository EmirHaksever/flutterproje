-- notifications tablosuna satır düşünce send-push Edge Function'ını çağırır.
-- (Dashboard "Database Webhooks" UI'sının yaptığı işin SQL karşılığı.)
--
-- pg_net asenkron çalışır; insert'i yavaşlatmaz.
--
-- Çalıştırma: proje kökünde  npx supabase db push

begin;

create extension if not exists pg_net;

create or replace function public.on_notification_insert()
returns trigger
language plpgsql
security definer
set search_path = public, net, extensions
as $$
begin
  perform net.http_post(
    url := 'https://uwlqoutitixoxflpchwe.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- anon key zaten public (uygulamanın içinde). Edge Function verify_jwt
      -- için geçerli bir JWT yeterli.
      'Authorization',
      'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3bHFvdXRpdGl4b3hmbHBjaHdlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM1MTE2NjUsImV4cCI6MjA1OTA4NzY2NX0.9uLwlSUd_mgjtAuX8kyQg__d1AYhnx_6ZFQLJmhZJ1g'
    ),
    body := jsonb_build_object('record', to_jsonb(new))
  );
  return new;
end;
$$;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
  after insert on public.notifications
  for each row execute function public.on_notification_insert();

commit;
