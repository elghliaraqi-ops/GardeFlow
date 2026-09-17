import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const enc = new TextEncoder();
const RESET_TTL_MS = 10 * 60 * 1000;
const RESEND_DELAY_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

function json(body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

function normalizePhone(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  let p = raw.replace(/[\s.\-()]/g, '');
  if (p.startsWith('00')) p = `+${p.slice(2)}`;
  if (p.startsWith('+')) return p;
  if (p.startsWith('0') && p.length >= 10) return `+212${p.slice(1)}`;
  if (p.startsWith('212')) return `+${p}`;
  return p;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(value));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function randomCode(): string {
  const value = new Uint32Array(1);
  crypto.getRandomValues(value);
  return (value[0] % 1000000).toString().padStart(6, '0');
}

function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? enc.encode(input) : input;
  let binary = '';
  bytes.forEach((b) => binary += String.fromCharCode(b));
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemPkcs8ToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function googleAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemPkcs8ToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(unsigned));
  const assertion = `${unsigned}.${b64url(new Uint8Array(signature))}`;
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new Error(`OAuth Google ${res.status}: ${await res.text()}`);
  return (await res.json()).access_token;
}

async function sendFcm(
  sa: any,
  accessToken: string,
  token: string,
  platform: string,
  code: string,
  profileId: string,
) {
  const title = 'Code de récupération GardeFlow';
  const body = `Votre code est ${code}. Il expire dans 10 minutes.`;
  const message: Record<string, unknown> = {
    token,
    data: {
      title,
      body,
      kind: 'password_reset_code',
      resourceId: profileId,
      code,
    },
    notification: { title, body },
  };
  if (platform === 'android') {
    message.android = {
      priority: 'HIGH',
      notification: {
        channel_id: 'huim6_push',
        icon: 'ic_stat_huim6',
        sound: 'default',
        tag: `password-reset:${profileId}`,
        visibility: 'PRIVATE',
      },
    };
  } else if (platform === 'ios') {
    message.apns = {
      headers: { 'apns-priority': '10' },
      payload: { aps: { sound: 'default' } },
    };
  } else {
    message.webpush = { headers: { Urgency: 'high' } };
  }

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message }),
    },
  );
  return { ok: res.ok, status: res.status, text: await res.text() };
}

async function genericRequestResponse() {
  // Small fixed delay reduces useful timing differences for account enumeration.
  await new Promise((resolve) => setTimeout(resolve, 220));
  return json({ ok: true });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const rawSa = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!supabaseUrl || !serviceKey || !rawSa) {
      console.error('password-reset: configuration serveur incomplète');
      return json({ ok: false, error: 'service_unavailable' }, 503);
    }

    const serviceAccount = JSON.parse(rawSa);
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const payload = await req.json().catch(() => ({}));
    const action = typeof payload?.action === 'string' ? payload.action : '';
    const phone = normalizePhone(payload?.phone);

    if (action === 'request') {
      if (!phone) return genericRequestResponse();

      const { data: profile } = await admin
        .from('profiles')
        .select('id,account_status')
        .eq('phone', phone)
        .maybeSingle();

      // Never disclose whether the phone exists.
      if (!profile || profile.account_status !== 'active') return genericRequestResponse();

      const { data: authData, error: authError } = await admin.auth.admin.getUserById(profile.id);
      if (authError || !authData.user) return genericRequestResponse();

      const appMetadata = { ...(authData.user.app_metadata ?? {}) } as Record<string, any>;
      const previous = appMetadata.gardeflow_password_reset as Record<string, any> | undefined;
      const now = Date.now();
      const lastRequestedAt = Number(previous?.requested_at ?? 0);
      if (lastRequestedAt > 0 && now - lastRequestedAt < RESEND_DELAY_MS) {
        return genericRequestResponse();
      }

      const code = randomCode();
      appMetadata.gardeflow_password_reset = {
        code_hash: await sha256(code),
        expires_at: now + RESET_TTL_MS,
        requested_at: now,
        attempts: 0,
      };

      const { error: metaError } = await admin.auth.admin.updateUserById(profile.id, {
        app_metadata: appMetadata,
      });
      if (metaError) throw metaError;

      const { data: tokenRows, error: tokenError } = await admin
        .from('push_tokens')
        .select('token,platform')
        .eq('owner_id', profile.id);
      if (tokenError) throw tokenError;

      if (tokenRows?.length) {
        const accessToken = await googleAccessToken(serviceAccount);
        for (const row of tokenRows) {
          const result = await sendFcm(
            serviceAccount,
            accessToken,
            row.token,
            row.platform ?? 'android',
            code,
            profile.id,
          );
          if (!result.ok) {
            console.error('password-reset FCM failed', result.status, result.text);
            if (
              result.text.includes('UNREGISTERED') ||
              result.text.includes('registration-token-not-registered')
            ) {
              await admin.from('push_tokens').delete().eq('token', row.token);
            }
          }
        }
      }

      return genericRequestResponse();
    }

    if (action === 'confirm') {
      const code = typeof payload?.code === 'string' ? payload.code.trim() : '';
      const newPassword = typeof payload?.newPassword === 'string' ? payload.newPassword : '';
      if (!phone || !/^\d{6}$/.test(code) || newPassword.length < 8 || newPassword.length > 72) {
        return json({ ok: false, error: 'invalid_input' });
      }

      const { data: profile } = await admin
        .from('profiles')
        .select('id,account_status')
        .eq('phone', phone)
        .maybeSingle();
      if (!profile || profile.account_status !== 'active') {
        return json({ ok: false, error: 'invalid_code' });
      }

      const { data: authData, error: authError } = await admin.auth.admin.getUserById(profile.id);
      if (authError || !authData.user) return json({ ok: false, error: 'invalid_code' });

      const appMetadata = { ...(authData.user.app_metadata ?? {}) } as Record<string, any>;
      const reset = appMetadata.gardeflow_password_reset as Record<string, any> | undefined;
      const now = Date.now();
      if (!reset || Number(reset.expires_at ?? 0) < now) {
        delete appMetadata.gardeflow_password_reset;
        await admin.auth.admin.updateUserById(profile.id, { app_metadata: appMetadata });
        return json({ ok: false, error: 'expired_code' });
      }

      const attempts = Number(reset.attempts ?? 0);
      if (attempts >= MAX_ATTEMPTS) {
        return json({ ok: false, error: 'too_many_attempts' });
      }

      const submittedHash = await sha256(code);
      if (submittedHash !== String(reset.code_hash ?? '')) {
        reset.attempts = attempts + 1;
        appMetadata.gardeflow_password_reset = reset;
        await admin.auth.admin.updateUserById(profile.id, { app_metadata: appMetadata });
        return json({
          ok: false,
          error: attempts + 1 >= MAX_ATTEMPTS ? 'too_many_attempts' : 'invalid_code',
        });
      }

      delete appMetadata.gardeflow_password_reset;
      const { error: updateError } = await admin.auth.admin.updateUserById(profile.id, {
        password: newPassword,
        app_metadata: appMetadata,
      });
      if (updateError) throw updateError;

      return json({ ok: true });
    }

    return json({ ok: false, error: 'invalid_action' }, 400);
  } catch (e) {
    console.error('password-reset error', e);
    return json({ ok: false, error: 'service_unavailable' }, 500);
  }
});
