import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const enc = new TextEncoder();

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
  const json = await res.json();
  return json.access_token;
}

async function sendFcm(sa: any, access: string, token: string, platform: string, data: Record<string, string>) {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${access}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token,
        data,
        ...(platform === 'android' ? {
          notification: { title: data.title, body: data.body },
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: 'huim6_push',
              icon: 'ic_stat_huim6',
              sound: 'default',
              tag: `${data.kind}:${data.resourceId}`,
            },
          },
        } : { webpush: { headers: { Urgency: 'high' } } }),
      },
    }),
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const rawSa = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!rawSa) throw new Error('Secret FCM_SERVICE_ACCOUNT_JSON absent');
    const serviceAccount = JSON.parse(rawSa);

    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return new Response('Unauthorized', { status: 401, headers: corsHeaders });

    const { kind, resourceId } = await req.json();
    if (typeof kind !== 'string' || typeof resourceId !== 'string') {
      return new Response('Payload invalide', { status: 400, headers: corsHeaders });
    }

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: caller, error: callerError } = await admin.from('profiles')
      .select('id,phone,nom,prenom,hospital,role,account_status').eq('id', authData.user.id).single();
    if (callerError || !caller) throw new Error('Profil appelant introuvable');
    if (kind !== 'account_created' && caller.account_status !== 'active') {
      return new Response('Compte inactif', { status: 403, headers: corsHeaders });
    }

    let recipients: string[] = [];
    let title = 'GardeFlow';
    let body = 'Nouvelle notification';

    const adminsForHospital = async (hospital: string) => {
      const { data } = await admin.from('profiles')
        .select('id').eq('role', 'admin').eq('account_status', 'active').eq('hospital', hospital);
      const ids = (data ?? []).map((x: any) => x.id as string);
      if (ids.length > 0) return ids;
      // Secours pour un administrateur réseau dont le profil est rattaché à un autre établissement.
      const { data: allAdmins } = await admin.from('profiles')
        .select('id').eq('role', 'admin').eq('account_status', 'active');
      return (allAdmins ?? []).map((x: any) => x.id as string);
    };

    if (kind === 'account_created') {
      const { data: profile, error } = await admin.from('profiles').select('*').eq('id', resourceId).single();
      if (error || !profile) throw new Error('Compte en attente introuvable');
      if (caller.id !== profile.id || profile.account_status !== 'pending') throw new Error('Action non autorisée');
      recipients = await adminsForHospital(profile.hospital);
      title = 'Nouveau compte à vérifier';
      body = `${profile.prenom} ${profile.nom} demande l’accès à ${profile.hospital}.`;
    } else if (kind.startsWith('exchange_')) {
      const { data: ex, error } = await admin.from('exchange_requests').select('*').eq('id', resourceId).single();
      if (error || !ex) throw new Error('Demande transfert/échange introuvable');
      const { data: sourceProfile } = await admin.from('profiles').select('hospital').eq('id', ex.from_id).single();
      const label = ex.type === 'exchange' ? 'échange' : 'transfert';

      if (kind === 'exchange_created') {
        if (caller.id !== ex.from_id || ex.status !== 'pendingB') throw new Error('Action non autorisée');
        recipients = [ex.to_id];
        title = `Nouvelle demande d’${label}`;
        body = `${ex.from_name} vous propose un ${label} de garde.`;
      } else if (kind === 'exchange_accepted') {
        if (caller.id !== ex.to_id) throw new Error('Action non autorisée');
        const autoServiceExchange = ex.type === 'exchange'
          && typeof ex.shift_id === 'string' && ex.shift_id.startsWith('service-')
          && typeof ex.target_shift_id === 'string' && ex.target_shift_id.startsWith('service-');
        if (autoServiceExchange) {
          if (ex.status !== 'approved') throw new Error('Action non autorisée');
          recipients = [ex.from_id];
          title = 'Échange de service accepté';
          body = `${ex.to_name} a accepté votre échange. Il a été appliqué immédiatement, sans validation administrateur.`;
        } else {
          if (ex.status !== 'pendingAdmin') throw new Error('Action non autorisée');
          recipients = [ex.from_id, ...(await adminsForHospital(sourceProfile?.hospital ?? caller.hospital))];
          title = `${label[0].toUpperCase()}${label.slice(1)} accepté`;
          body = `${ex.to_name} a accepté. Validation administrateur requise.`;
        }
      } else if (kind === 'exchange_declined') {
        if (caller.id !== ex.to_id || ex.status !== 'declinedB') throw new Error('Action non autorisée');
        recipients = [ex.from_id];
        title = `${label[0].toUpperCase()}${label.slice(1)} refusé`;
        body = `${ex.to_name} a refusé votre demande.`;
      } else if (kind === 'exchange_reviewed') {
        if (caller.role !== 'admin' || caller.id === ex.from_id || caller.id === ex.to_id || !['approved', 'rejectedAdmin'].includes(ex.status)) throw new Error('Action non autorisée');
        recipients = [ex.from_id, ex.to_id];
        const ok = ex.status === 'approved';
        title = `${label[0].toUpperCase()}${label.slice(1)} ${ok ? 'approuvé' : 'refusé'}`;
        body = `L’administrateur a ${ok ? 'approuvé' : 'refusé'} la demande entre ${ex.from_name} et ${ex.to_name}.`;
      } else if (kind === 'exchange_cancelled') {
        if (caller.id !== ex.from_id || ex.status !== 'cancelled') throw new Error('Action non autorisée');
        recipients = [ex.to_id];
        title = `Demande d’${label} annulée`;
        body = `${ex.from_name} a annulé sa demande.`;
      } else throw new Error('Type de push inconnu');
    } else if (kind.startsWith('leave_')) {
      const { data: leave, error } = await admin.from('leave_requests').select('*').eq('id', resourceId).single();
      if (error || !leave) throw new Error('Demande de congé introuvable');
      const { data: owner } = await admin.from('profiles').select('hospital').eq('id', leave.owner_id).single();
      if (kind === 'leave_created') {
        if (caller.id !== leave.owner_id || leave.status !== 'pendingAdmin') throw new Error('Action non autorisée');
        recipients = await adminsForHospital(owner?.hospital ?? caller.hospital);
        title = 'Nouvelle demande de congé';
        body = leave.start_date === leave.end_date
          ? `${leave.owner_name} demande un congé le ${leave.start_date}.`
          : `${leave.owner_name} demande un congé du ${leave.start_date} au ${leave.end_date}.`;
      } else if (kind === 'leave_reviewed') {
        if (caller.role !== 'admin' || caller.id === leave.owner_id || !['approved', 'rejectedAdmin'].includes(leave.status)) throw new Error('Action non autorisée');
        recipients = [leave.owner_id];
        const ok = leave.status === 'approved';
        title = `Congé ${ok ? 'approuvé' : 'refusé'}`;
        const period = leave.start_date === leave.end_date ? leave.start_date : `${leave.start_date} au ${leave.end_date}`;
        body = `Votre demande de congé (${period}) a été ${ok ? 'approuvée' : 'refusée'}.`;
      } else if (kind === 'leave_cancelled') {
        if (caller.id !== leave.owner_id || leave.status !== 'cancelled') throw new Error('Action non autorisée');
        recipients = await adminsForHospital(owner?.hospital ?? caller.hospital);
        title = 'Demande de congé annulée';
        const period = leave.start_date === leave.end_date ? leave.start_date : `${leave.start_date} au ${leave.end_date}`;
        body = `${leave.owner_name} a annulé sa demande (${period}).`;
      } else throw new Error('Type de push inconnu');
    } else if (kind === 'planning_admin_deleted') {
      if (caller.role !== 'admin') throw new Error('Action non autorisée');
      const { data: entry, error } = await admin.from('planning_entries').select('*').eq('id', resourceId).single();
      if (error || !entry || !entry.deleted_at) throw new Error('Affectation supprimée introuvable');
      recipients = [entry.owner_id];
      title = entry.shift_id === 'conge' ? 'Congé supprimé' : 'Garde supprimée';
      if (entry.shift_id === 'conge' && entry.leave_request_id) {
        const { data: leave } = await admin.from('leave_requests').select('start_date,end_date').eq('id', entry.leave_request_id).single();
        const period = leave && leave.start_date !== leave.end_date ? `${leave.start_date} au ${leave.end_date}` : (leave?.start_date ?? entry.date_str);
        body = `L’administrateur a supprimé votre congé (${period}).`;
      } else {
        body = `L’administrateur a supprimé votre garde du ${entry.date_str}.`;
      }
    } else {
      throw new Error('Type de push inconnu');
    }

    recipients = [...new Set(recipients)].filter((id) => id && id !== caller.id);
    if (recipients.length === 0) return Response.json({ sent: 0 }, { headers: corsHeaders });

    const { data: tokenRows, error: tokenError } = await admin.from('push_tokens')
      .select('token,owner_id,platform').in('owner_id', recipients);
    if (tokenError) throw tokenError;

    if (!tokenRows?.length) return Response.json({ sent: 0, devices: 0 }, { headers: corsHeaders });
    const access = await googleAccessToken(serviceAccount);
    let sent = 0;
    let failed = 0;
    for (const row of tokenRows ?? []) {
      const result = await sendFcm(serviceAccount, access, row.token, row.platform, {
        title, body, kind, resourceId,
      });
      if (result.ok) {
        sent++;
      } else {
        failed++;
        console.error('FCM delivery failed', result.status, result.text);
        if (result.text.includes('UNREGISTERED') || result.text.includes('registration-token-not-registered')) {
          await admin.from('push_tokens').delete().eq('token', row.token);
        }
      }
    }

    return Response.json({ sent, failed, devices: tokenRows.length, recipients: recipients.length }, { headers: corsHeaders });
  } catch (e) {
    console.error(e);
    return Response.json({ error: String(e) }, { status: 400, headers: corsHeaders });
  }
});
