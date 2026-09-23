import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const authorization = req.headers.get('Authorization') ?? '';

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization.startsWith('Bearer ')) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerData, error: callerError } = await callerClient.auth.getUser();
    const callerId = callerData.user?.id;
    if (callerError || !callerId) return json({ ok: false, error: 'unauthorized' }, 401);

    const { data: callerProfile, error: profileError } = await adminClient
      .from('profiles')
      .select('id, role, account_status')
      .eq('id', callerId)
      .maybeSingle();

    if (profileError || !callerProfile || callerProfile.role !== 'admin' || callerProfile.account_status !== 'active') {
      return json({ ok: false, error: 'forbidden' }, 403);
    }

    const payload = await req.json().catch(() => ({}));
    const targetUserId = typeof payload?.userId === 'string' ? payload.userId.trim() : '';
    const newPassword = typeof payload?.newPassword === 'string' ? payload.newPassword : '';

    if (!/^[0-9a-f-]{36}$/i.test(targetUserId)) return json({ ok: false, error: 'invalid_user' }, 400);
    if (newPassword.length < 8 || newPassword.length > 72) {
      return json({ ok: false, error: 'invalid_password' }, 400);
    }

    const { data: targetProfile, error: targetError } = await adminClient
      .from('profiles')
      .select('id, account_status')
      .eq('id', targetUserId)
      .maybeSingle();

    if (targetError || !targetProfile || targetProfile.account_status !== 'active') {
      return json({ ok: false, error: 'user_not_found' }, 404);
    }

    const { error: updateError } = await adminClient.auth.admin.updateUserById(targetUserId, {
      password: newPassword,
    });
    if (updateError) {
      console.error('admin-reset-user-password update failed', updateError);
      return json({ ok: false, error: 'update_failed' }, 500);
    }

    const { error: requestResolveError } = await adminClient
      .from('password_reset_requests')
      .update({
        status: 'resolved',
        handled_at: new Date().toISOString(),
        handled_by: callerId,
      })
      .eq('profile_id', targetUserId)
      .eq('status', 'pending');
    if (requestResolveError) {
      // Password reset succeeded; do not roll it back only because the notification
      // cleanup failed. Realtime/refresh can reconcile later.
      console.error('admin-reset-user-password request resolution failed', requestResolveError);
    }

    return json({ ok: true });
  } catch (error) {
    console.error('admin-reset-user-password error', error);
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
