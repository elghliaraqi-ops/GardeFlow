import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const enc = new TextEncoder();

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
  profile: { id: string; prenom?: string; nom?: string; phone?: string; hospital?: string },
) {
  const displayName = `${profile.prenom ?? ''} ${profile.nom ?? ''}`.trim() || 'Un médecin';
  const title = 'Mot de passe oublié';
  const body = `${displayName} (${profile.phone ?? ''}) demande un nouveau mot de passe. Ouvrez Réglages > Administration des comptes.`;
  const message: Record<string, unknown> = {
    token,
    data: {
      title,
      body,
      kind: 'password_reset_request',
      resourceId: profile.id,
      requesterName: displayName,
      requesterPhone: profile.phone ?? '',
      requesterHospital: profile.hospital ?? '',
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
        tag: `password-reset:${profile.id}`,
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

async function genericResponse() {
  await new Promise((resolve) => setTimeout(resolve, 180));
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

    const payload = await req.json().catch(() => ({}));
    const action = typeof payload?.action === 'string' ? payload.action : '';
    const phone = normalizePhone(payload?.phone);
    if (action !== 'request') return json({ ok: false, error: 'invalid_action' }, 400);
    if (!phone) return genericResponse();

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: profile } = await admin
      .from('profiles')
      .select('id,account_status,nom,prenom,phone,hospital')
      .eq('phone', phone)
      .maybeSingle();

    // Same response whether the account exists or not: do not expose the directory.
    if (!profile || profile.account_status !== 'active') return genericResponse();

    let { data: adminRows, error: adminsError } = await admin
      .from('profiles')
      .select('id')
      .eq('role', 'admin')
      .eq('account_status', 'active')
      .eq('hospital', profile.hospital);
    if (adminsError) throw adminsError;

    if (!adminRows?.length) {
      const fallback = await admin
        .from('profiles')
        .select('id')
        .eq('role', 'admin')
        .eq('account_status', 'active');
      if (fallback.error) throw fallback.error;
      adminRows = fallback.data;
    }

    const adminIds = [...new Set((adminRows ?? []).map((row: any) => row.id as string).filter(Boolean))];
    if (!adminIds.length) return genericResponse();

    const { data: tokenRows, error: tokenError } = await admin
      .from('push_tokens')
      .select('token,platform,owner_id')
      .in('owner_id', adminIds);
    if (tokenError) throw tokenError;
    if (!tokenRows?.length) return genericResponse();

    const serviceAccount = JSON.parse(rawSa);
    const accessToken = await googleAccessToken(serviceAccount);
    for (const row of tokenRows) {
      const result = await sendFcm(
        serviceAccount,
        accessToken,
        row.token,
        row.platform ?? 'android',
        profile,
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

    return genericResponse();
  } catch (e) {
    console.error('password-reset error', e);
    return json({ ok: false, error: 'service_unavailable' }, 500);
  }
});
