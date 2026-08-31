// Supabase Edge Function: notifications tablosuna satır düşünce
// o kullanıcının cihazlarına FCM push gönderir.
//
// Kurulum:
//   1) PowerShell:
//      $b64=[Convert]::ToBase64String([IO.File]::ReadAllBytes("servis-hesabi.json"))
//      npx supabase secrets set FIREBASE_SERVICE_ACCOUNT_B64=$b64
//   2) npx supabase functions deploy send-push
//   3) Dashboard > Database > Webhooks: notifications INSERT -> bu fonksiyon
//
// (SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY Edge ortamında hazır gelir.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.9.6/index.ts";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

let cachedToken: { value: string; exp: number } | null = null;

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.value;

  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error("OAuth token alınamadı: " + JSON.stringify(json));
  cachedToken = { value: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return json.access_token;
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record ?? payload;
    const userId: string | undefined = record?.user_id;
    const message: string = record?.message ?? "Yeni bir bildirimin var";
    if (!userId) return new Response("no user_id", { status: 200 });

    const b64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64");
    const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    const saRaw = b64 ? atob(b64) : raw;
    if (!saRaw) {
      return new Response("FIREBASE_SERVICE_ACCOUNT(_B64) yok", { status: 500 });
    }
    const sa: ServiceAccount = JSON.parse(saRaw);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: tokens, error } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", userId);
    if (error) throw error;
    if (!tokens || tokens.length === 0) {
      return new Response("cihaz yok", { status: 200 });
    }

    const accessToken = await getAccessToken(sa);
    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    const dead: string[] = [];

    for (const { token } of tokens) {
      const r = await fetch(fcmUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: "Alışveriş Listem", body: message },
            android: { priority: "HIGH" },
          },
        }),
      });
      if (r.ok) {
        sent++;
      } else {
        const err = await r.text();
        if (err.includes("UNREGISTERED") || err.includes("INVALID_ARGUMENT")) {
          dead.push(token);
        }
        console.error("FCM hata:", r.status, err);
      }
    }

    if (dead.length) {
      await supabase.from("device_tokens").delete().in("token", dead);
    }

    return new Response(JSON.stringify({ sent, dead: dead.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(e);
    return new Response("hata: " + (e as Error).message, { status: 500 });
  }
});
