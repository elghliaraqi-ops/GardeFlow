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

async function sendFcm(
  sa: any,
  access: string,
  token: string,
  platform: string,
  data: Record<string, string>,
) {
  const message: Record<string, unknown> = { token, data };

  if (platform === 'android') {
    message.android = { priority: 'HIGH' };
  } else if (platform === 'ios') {
    message.apns = {
      headers: {
        'apns-priority': '5',
        'apns-push-type': 'background',
      },
      payload: { aps: { 'content-available': 1 } },
    };
  } else {
    message.webpush = {
      headers: { Urgency: 'high' },
      notification: {
        title: data.title,
        body: data.body,
        tag: `${data.kind}:${data.resourceId}`,
      },
    };
  }

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${access}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message }),
    },
  );
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
      .select('id,phone,nom,prenom,hospital,role,account_status,promotion_number')
      .eq('id', authData.user.id).single();
    if (callerError || !caller) throw new Error('Profil appelant introuvable');
    if (kind !== 'account_created' && caller.account_status !== 'active') {
      return new Response('Compte inactif', { status: 403, headers: corsHeaders });
    }

    let recipients: string[] = [];
    let title = 'GardeFlow';
    let body = 'Nouvelle notification';
    let allowSelf = false;
    let practicePush = false;
    let receiptResourceId = resourceId;

    const adminsForHospital = async (hospital: string) => {
      const { data } = await admin.from('profiles')
        .select('id').eq('role', 'admin').eq('account_status', 'active').eq('hospital', hospital);
      const ids = (data ?? []).map((x: any) => x.id as string);
      if (ids.length > 0) return ids;
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
    } else if (kind === 'announcement_created') {
      const { data: announcement, error } = await admin.from('public_announcements')
        .select('*').eq('id', resourceId).single();
      if (error || !announcement) throw new Error('Annonce introuvable');
      if (caller.id !== announcement.author_id || announcement.closed_at) {
        throw new Error('Action non autorisée');
      }

      let cohortQuery = admin.from('profiles')
        .select('id')
        .eq('account_status', 'active')
        .eq('hospital', announcement.hospital);
      const promo = Number(announcement.promotion_number);
      const isServiceAnnouncement = typeof announcement.shift_id === 'string'
        && announcement.shift_id.startsWith('service-');
      if (!isServiceAnnouncement && (promo === 6 || promo === 7)) {
        cohortQuery = cohortQuery.eq('promotion_number', promo);
      }
      const { data: cohort, error: cohortError } = await cohortQuery;
      if (cohortError) throw cohortError;
      recipients = (cohort ?? []).map((x: any) => x.id as string);
      title = 'Nouvelle annonce d’échange';
      body = `${announcement.author_name} cherche un échange pour sa garde du ${announcement.date_str}.`;
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
    } else if (kind === 'disciplinary_assigned') {
      if (caller.role !== 'admin') throw new Error('Action non autorisée');
      const { data: entry, error } = await admin.from('planning_entries')
        .select('*').eq('id', resourceId).single();
      if (error || !entry || !entry.is_disciplinary || entry.deleted_at) {
        throw new Error('Garde disciplinaire introuvable');
      }
      const { data: audit } = await admin.from('audit_log')
        .select('reason,actor_id')
        .eq('action', 'planning.disciplinary_assigned')
        .eq('entity_id', resourceId)
        .eq('actor_id', caller.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!audit) throw new Error('Attribution disciplinaire non vérifiée');
      recipients = [entry.owner_id];
      title = 'Garde disciplinaire attribuée';
      const shiftLabels: Record<string, string> = {
        'urg-jour': 'Urgences · Jour',
        'urg-nuit': 'Urgences · Nuit',
        'urg-24h': 'Urgences · 24H',
        'service-jour': 'Service · Jour',
        'service-nuit': 'Service · Nuit',
        'service-24h': 'Service · 24H',
      };
      const reason = String(audit.reason ?? '').trim();
      body = `Une garde disciplinaire vous a été attribuée le ${entry.date_str} (${shiftLabels[entry.shift_id] ?? entry.shift_id}). Motif : ${reason || 'non renseigné'}.`;
    } else if (kind === 'planning_admin_deleted') {
      if (caller.role !== 'admin') throw new Error('Action non autorisée');
      const { data: entry, error } = await admin.from('planning_entries').select('*').eq('id', resourceId).single();
      if (error || !entry || !entry.deleted_at) throw new Error('Affectation supprimée introuvable');
      const { data: audit } = await admin.from('audit_log')
        .select('reason,actor_id')
        .eq('action', 'planning.deleted')
        .eq('entity_id', resourceId)
        .eq('actor_id', caller.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      const reason = String(audit?.reason ?? '').trim();
      recipients = [entry.owner_id];
      title = entry.shift_id === 'conge'
        ? 'Congé annulé par l’administrateur'
        : 'Garde annulée par l’administrateur';
      if (entry.shift_id === 'conge' && entry.leave_request_id) {
        const { data: leave } = await admin.from('leave_requests').select('start_date,end_date').eq('id', entry.leave_request_id).single();
        const period = leave && leave.start_date !== leave.end_date ? `${leave.start_date} au ${leave.end_date}` : (leave?.start_date ?? entry.date_str);
        body = `L’administrateur a annulé votre congé (${period}).${reason ? ` Motif : ${reason}.` : ''}`;
      } else {
        body = `L’administrateur a annulé votre garde du ${entry.date_str}.${reason ? ` Motif : ${reason}.` : ''}`;
      }
    } else if (kind.startsWith('practice_')) {
      allowSelf = true;
      practicePush = true;
      recipients = [caller.id];

      const requireOwnedCase = async (caseId: string) => {
        const { data: practiceCase, error } = await admin.from('practice_cases')
          .select('id,user_id,guard_id,patient_number,is_draft,consultation_reason')
          .eq('id', caseId)
          .maybeSingle();
        if (error || !practiceCase || practiceCase.user_id !== caller.id || practiceCase.is_draft) {
          throw new Error('Cas Practice introuvable ou non autorisé');
        }
        return practiceCase;
      };

      const requireOwnedPost = async (postId: string) => {
        const { data: post, error } = await admin.from('clinical_case_posts')
          .select('id,practice_case_id,author_id')
          .eq('id', postId)
          .maybeSingle();
        if (error || !post || post.author_id !== caller.id) {
          throw new Error('Cas clinique introuvable ou non autorisé');
        }
        return post;
      };

      if (kind === 'practice_case_created') {
        const practiceCase = await requireOwnedCase(resourceId);
        const number = Number(practiceCase.patient_number || 0);
        title = 'Cas clinique ajouté';
        body = `${number > 0 ? `Patient #${String(number).padStart(3, '0')} ` : 'Nouveau cas '}enregistré dans Practice. Les 5 QCM sont en préparation.`;
      } else if (kind === 'practice_qcm_ready') {
        const { data: post, error } = await admin.from('clinical_case_posts')
          .select('id,practice_case_id,author_id')
          .eq('practice_case_id', resourceId)
          .maybeSingle();
        if (error || !post || post.author_id !== caller.id) {
          throw new Error('Cas clinique introuvable ou non autorisé');
        }
        const { count } = await admin.from('clinical_case_qcms')
          .select('id', { count: 'exact', head: true })
          .eq('post_id', post.id)
          .eq('generation_source', 'openai');
        if ((count ?? 0) < 5) throw new Error('QCM IA pas encore prêts');
        title = '5 QCM Practice prêts';
        body = 'Les 5 QCM de raisonnement avec explication IA après chaque réponse sont disponibles.';
      } else if (kind === 'practice_achievement_unlocked') {
        const { data: achievement, error } = await admin.from('practice_achievements')
          .select('id,key,name,description')
          .eq('key', resourceId)
          .maybeSingle();
        if (error || !achievement) throw new Error('Succès Practice introuvable');
        const { data: userAchievement } = await admin.from('user_practice_achievements')
          .select('unlocked_at')
          .eq('user_id', caller.id)
          .eq('achievement_id', achievement.id)
          .maybeSingle();
        if (!userAchievement?.unlocked_at) throw new Error('Succès non débloqué');
        title = `🏆 Succès débloqué · ${achievement.name}`;
        body = achievement.description || 'Nouveau succès débloqué dans Practice.';
      } else if (kind === 'practice_goal_reached') {
        const { data: pref } = await admin.from('practice_preferences')
          .select('guard_goal')
          .eq('user_id', caller.id)
          .maybeSingle();
        const goal = Number(pref?.guard_goal || 0);
        if (goal <= 0) throw new Error('Aucun objectif de garde configuré');
        const { count } = await admin.from('practice_cases')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', caller.id)
          .eq('guard_id', resourceId)
          .eq('is_draft', false);
        if ((count ?? 0) < goal) throw new Error('Objectif de garde non atteint');
        title = '🎯 Objectif de garde atteint';
        body = `${count ?? goal} cas documentés : votre objectif de ${goal} est atteint.`;
      } else if (kind === 'practice_case_milestone') {
        const practiceCase = await requireOwnedCase(resourceId);
        const { count } = await admin.from('practice_cases')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', caller.id)
          .eq('guard_id', practiceCase.guard_id)
          .eq('is_draft', false);
        const n = count ?? 0;
        if (![5, 10, 15, 20, 30].includes(n)) {
          throw new Error('Pas de palier Practice à notifier');
        }
        receiptResourceId = `${practiceCase.guard_id}:${n}`;
        title = `🔥 ${n} cas documentés`;
        body = 'Belle progression pendant cette garde. Continuez à documenter les cas utiles sans ralentir les soins.';
      } else if (kind === 'practice_qcm_complete' || kind === 'practice_qcm_perfect') {
        const post = await requireOwnedPost(resourceId);
        const { data: qcms } = await admin.from('clinical_case_qcms')
          .select('id')
          .eq('post_id', post.id);
        const ids = (qcms ?? []).map((q: any) => q.id as string);
        if (ids.length < 5) throw new Error('QCM incomplets');
        const { data: answers } = await admin.from('clinical_case_qcm_answers')
          .select('is_correct')
          .eq('user_id', caller.id)
          .in('qcm_id', ids);
        const answered = answers?.length ?? 0;
        const correct = (answers ?? []).filter((a: any) => a.is_correct).length;
        if (answered < 5) throw new Error('Les 5 QCM ne sont pas terminés');
        if (kind === 'practice_qcm_perfect') {
          if (correct < 5) throw new Error('Score parfait non atteint');
          title = '⭐ 5/5 sur ce cas clinique';
          body = 'Les 5 QCM sont justes. Les explications IA restent disponibles pour consolider le raisonnement.';
        } else {
          title = 'Cas révisé · 5 QCM terminés';
          body = `${correct}/5 réponses justes. Relisez les explications IA pour les points à consolider.`;
        }
      } else if (kind === 'practice_level_up' || kind === 'practice_streak') {
        // Ces événements sont détectés par le client après comparaison des
        // statistiques avant/après. On vérifie seulement que la ressource
        // déclenchante appartient bien à l'utilisateur.
        const { data: ownedCase } = await admin.from('practice_cases')
          .select('id')
          .eq('id', resourceId)
          .eq('user_id', caller.id)
          .maybeSingle();
        if (!ownedCase) {
          const { data: ownedPost } = await admin.from('clinical_case_posts')
            .select('id')
            .eq('id', resourceId)
            .eq('author_id', caller.id)
            .maybeSingle();
          if (!ownedPost) throw new Error('Ressource Practice non autorisée');
        }
        if (kind === 'practice_level_up') {
          title = '⬆️ Nouveau niveau Practice';
          body = 'Votre activité documentée et vos QCM vous font passer au niveau suivant.';
        } else {
          title = '🔥 Série Practice prolongée';
          body = 'Votre régularité continue : une nouvelle garde documentée s’ajoute à votre série.';
        }
      } else {
        throw new Error('Type de push Practice inconnu');
      }

      const { data: previousReceipt } = await admin.from('practice_push_receipts')
        .select('id')
        .eq('user_id', caller.id)
        .eq('kind', kind)
        .eq('resource_id', receiptResourceId)
        .maybeSingle();
      if (previousReceipt) {
        return Response.json({ sent: 0, deduplicated: true }, { headers: corsHeaders });
      }
    } else {
      throw new Error('Type de push inconnu');
    }

    recipients = [...new Set(recipients)].filter((id) => id && (allowSelf || id !== caller.id));
    if (recipients.length === 0) return Response.json({ sent: 0 }, { headers: corsHeaders });

    const { data: tokenRows, error: tokenError } = await admin.from('push_tokens')
      .select('token,owner_id,platform').in('owner_id', recipients);
    if (tokenError) throw tokenError;

    if (!tokenRows?.length) {
      return Response.json({ sent: 0, devices: 0 }, { headers: corsHeaders });
    }
    const access = await googleAccessToken(serviceAccount);
    let sent = 0;
    let failed = 0;
    for (const row of tokenRows ?? []) {
      const result = await sendFcm(serviceAccount, access, row.token, row.platform, {
        title, body, kind, resourceId,
        recipientId: row.owner_id,
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

    if (practicePush && sent > 0) {
      await admin.from('practice_push_receipts').upsert({
        user_id: caller.id,
        kind,
        resource_id: receiptResourceId,
        sent_at: new Date().toISOString(),
      }, { onConflict: 'user_id,kind,resource_id' });
    }

    return Response.json({ sent, failed, devices: tokenRows.length, recipients: recipients.length }, { headers: corsHeaders });
  } catch (e) {
    console.error(e);
    return Response.json({ error: String(e) }, { status: 400, headers: corsHeaders });
  }
});