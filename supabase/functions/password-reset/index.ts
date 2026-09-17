import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
import { JWT } from 'npm:google-auth-library@11.0.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

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

async function googleAccessToken(sa: Record<string, string>): Promise<string> {
  const auth = new JWT({
    email: sa.client_email,
    key: sa.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const result = await auth.getAccessToken();
  const token = typeof result === 'string' ? result : result?.token;
  if (!token) throw new Error('Google OAuth token unavailable');
  return token;
}

async function sendFcm(
  sa: Record<string, string>,
  accessToken: string,
  token: string,
  platform: string,
  profile: Record<string, string>,
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

  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ message }),
  });
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
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const rawServiceAccount = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!supabaseUrl || !serviceKey || !rawServiceAccount) {
      console.error('password-reset: configuration serveur incomplète');
      return json({ ok: false, error: 'service_unavailable' }, 503);
    }

    const payload = await req.json().catch(() => ({}));
    if (payload?.action !== 'request') return json({ ok: false, error: 'invalid_action' }, 400);
    const phone = normalizePhone(payload?.phone);
    if (!phone) return genericResponse();

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: profile } = await admin
      .from('profiles')
      .select('id,account_status,nom,prenom,phone,hospital')
      .eq('phone', phone)
      .maybeSingle();

    // Keep the same response whether an account exists or not.
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

    const adminIds = [...new Set((adminRows ?? []).map((row: { id: string }) => row.id).filter(Boolean))];
    if (!adminIds.length) return genericResponse();

    const { data: tokenRows, error: tokenError } = await admin
      .from('push_tokens')
      .select('token,platform,owner_id')
      .in('owner_id', adminIds);
    if (tokenError) throw tokenError;
    if (!tokenRows?.length) return genericResponse();

    const serviceAccount = JSON.parse(rawServiceAccount) as Record<string, string>;
    const accessToken = await googleAccessToken(serviceAccount);
    for (const row of tokenRows) {
      const result = await sendFcm(
        serviceAccount,
        accessToken,
        row.token,
        row.platform ?? 'android',
        profile as Record<string, string>,
      );
      if (!result.ok) {
        console.error('password-reset FCM failed', result.status, result.text);
        if (result.text.includes('UNREGISTERED') || result.text.includes('registration-token-not-registered')) {
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
