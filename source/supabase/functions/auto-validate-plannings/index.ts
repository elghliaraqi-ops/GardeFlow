import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const enc = new TextEncoder();

function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? enc.encode(input) : input;
  let binary = '';
  bytes.forEach((b) => binary += String.fromCharCode(b));
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemToBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function getAccessToken(sa: any): Promise<string> {
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
    pemToBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(unsigned));
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: `${unsigned}.${b64url(new Uint8Array(sig))}`,
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new Error(`OAuth Google ${res.status}: ${await res.text()}`);
  return (await res.json()).access_token;
}

async function sendFcm(sa: any, access: string, token: string, platform: string, data: Record<string,string>) {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${access}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token,
        data,
        ...(platform === 'android'
          ? {
              notification: { title: data.title, body: data.body },
              android: {
                priority: 'HIGH',
                notification: {
                  channel_id: 'huim6_push',
                  icon: 'ic_stat_huim6',
                  sound: 'default',
                  tag: `planning_auto_validated:${data.resourceId}`,
                },
              },
            }
          : {
              webpush: {
                headers: { Urgency: 'high' },
                notification: { title: data.title, body: data.body },
              },
            }),
      },
    }),
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}

const months = ['', 'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

Deno.serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const rawSa = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!rawSa) throw new Error('Secret FCM_SERVICE_ACCOUNT_JSON absent');

    const admin = createClient(supabaseUrl, serviceKey);
    const supplied = req.headers.get('x-planning-auto-validation-key') ?? '';

    const { data: cfg, error: cfgErr } = await admin
      .from('planning_auto_validation_config')
      .select('sync_key')
      .eq('id', true)
      .single();

    if (cfgErr || !cfg?.sync_key || supplied !== String(cfg.sync_key)) {
      return new Response('Unauthorized', { status: 401 });
    }

    const { data: events, error: rpcErr } = await admin.rpc('process_due_planning_auto_validations');
    if (rpcErr) throw rpcErr;

    const pending = (events ?? []) as Array<{
      event_id: string;
      owner_id: string;
      year: number;
      month: number;
      approved_at: string;
    }>;

    if (!pending.length) {
      return Response.json({ pending: 0, sent_events: 0, sent_devices: 0 });
    }

    const sa = JSON.parse(rawSa);
    const access = await getAccessToken(sa);
    let sentEvents = 0;
    let sentDevices = 0;
    let failedEvents = 0;

    for (const event of pending) {
      const { data: tokenRows, error: tokenErr } = await admin
        .from('push_tokens')
        .select('token,platform')
        .eq('owner_id', event.owner_id);

      const { data: current } = await admin
        .from('planning_auto_validation_events')
        .select('push_attempts')
        .eq('id', event.event_id)
        .single();

      let eventSent = false;
      const errors: string[] = [];

      if (tokenErr) {
        errors.push(String(tokenErr.message ?? tokenErr));
      } else {
        const month = months[event.month] ?? String(event.month);
        const title = 'Planning validé automatiquement';
        const body = `Votre planning de ${month} ${event.year} a été validé automatiquement, 7 jours après la publication du planning officiel.`;

        for (const row of tokenRows ?? []) {
          const result = await sendFcm(sa, access, row.token, row.platform, {
            title,
            body,
            kind: 'planning_auto_validated',
            resourceId: event.event_id,
            year: String(event.year),
            month: String(event.month),
          });
          if (result.ok) {
            eventSent = true;
            sentDevices++;
          } else {
            errors.push(`FCM ${result.status}: ${result.text}`);
            if (
              result.text.includes('UNREGISTERED') ||
              result.text.includes('registration-token-not-registered')
            ) {
              await admin.from('push_tokens').delete().eq('token', row.token);
            }
          }
        }
      }

      const update: Record<string, unknown> = {
        push_attempted_at: new Date().toISOString(),
        push_attempts: Number(current?.push_attempts ?? 0) + 1,
        last_push_error: eventSent
          ? null
          : (errors.join('\n').slice(0, 4000) ||
              'Aucun appareil avec notifications push enregistré'),
      };

      if (eventSent) {
        update.push_sent_at = new Date().toISOString();
        sentEvents++;
      } else {
        failedEvents++;
      }

      await admin
        .from('planning_auto_validation_events')
        .update(update)
        .eq('id', event.event_id);
    }

    return Response.json({
      pending: pending.length,
      sent_events: sentEvents,
      failed_events: failedEvents,
      sent_devices: sentDevices,
    });
  } catch (e) {
    console.error(e);
    return Response.json({ error: String(e) }, { status: 400 });
  }
});
