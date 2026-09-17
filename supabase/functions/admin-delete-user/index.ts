import { createClient } from 'npm:@supabase/supabase-js@2.116.0';

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

function cleanError(error: unknown) {
  if (error instanceof Error) return error.message;
  return String(error ?? 'unknown_error');
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

    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from('profiles')
      .select('id, role, account_status')
      .eq('id', callerId)
      .maybeSingle();

    if (
      callerProfileError ||
      !callerProfile ||
      callerProfile.role !== 'admin' ||
      callerProfile.account_status !== 'active'
    ) {
      return json({ ok: false, error: 'forbidden' }, 403);
    }

    const payload = await req.json().catch(() => ({}));
    const targetUserId = typeof payload?.userId === 'string' ? payload.userId.trim() : '';
    if (!/^[0-9a-f-]{36}$/i.test(targetUserId)) {
      return json({ ok: false, error: 'invalid_user' }, 400);
    }
    if (targetUserId === callerId) {
      return json({ ok: false, error: 'cannot_delete_admin' }, 403);
    }

    const { data: targetProfile, error: targetError } = await adminClient
      .from('profiles')
      .select('id, phone, role, account_status')
      .eq('id', targetUserId)
      .maybeSingle();

    if (targetError || !targetProfile) {
      return json({ ok: false, error: 'user_not_found' }, 404);
    }
    if (targetProfile.role === 'admin') {
      return json({ ok: false, error: 'cannot_delete_admin' }, 403);
    }

    // Delete any astreinte files owned by this account before removing DB rows.
    // Supabase Auth refuses to delete a user who still owns Storage objects.
    const { data: photoRows, error: photoLookupError } = await adminClient
      .from('astreinte_photos')
      .select('storage_path')
      .or(`owner_id.eq.${targetUserId},owner_phone.eq.${targetProfile.phone}`);

    if (photoLookupError) {
      console.error('admin-delete-user photo lookup failed', photoLookupError);
      return json({ ok: false, error: 'storage_cleanup_failed' }, 500);
    }

    const storagePaths = Array.from(
      new Set(
        (photoRows ?? [])
          .map((row: { storage_path?: string | null }) => row.storage_path?.trim())
          .filter((value: string | undefined): value is string => Boolean(value)),
      ),
    );

    for (let index = 0; index < storagePaths.length; index += 1000) {
      const chunk = storagePaths.slice(index, index + 1000);
      const { error: storageError } = await adminClient.storage.from('gardeflow-shared').remove(chunk);
      if (storageError) {
        console.error('admin-delete-user storage cleanup failed', storageError);
        return json({ ok: false, error: 'storage_cleanup_failed' }, 500);
      }
    }

    const phone = targetProfile.phone;
    const cleanupOperations = [
      adminClient.from('audit_log').delete().or(`actor_id.eq.${targetUserId},subject_id.eq.${targetUserId}`),
      adminClient
        .from('exchange_requests')
        .delete()
        .or(`from_id.eq.${targetUserId},to_id.eq.${targetUserId},from_phone.eq.${phone},to_phone.eq.${phone}`),
      adminClient.from('leave_requests').delete().or(`owner_id.eq.${targetUserId},owner_phone.eq.${phone}`),
      adminClient.from('planning_entries').delete().or(`owner_id.eq.${targetUserId},owner_phone.eq.${phone}`),
      adminClient.from('astreinte_photos').delete().or(`owner_id.eq.${targetUserId},owner_phone.eq.${phone}`),
      adminClient.from('planning_months').update({ reviewed_by: null }).eq('reviewed_by', targetUserId),
    ];

    const cleanupResults = await Promise.all(cleanupOperations);
    const cleanupFailure = cleanupResults.find((result) => result.error != null)?.error;
    if (cleanupFailure) {
      console.error('admin-delete-user data cleanup failed', cleanupFailure);
      return json({ ok: false, error: 'data_cleanup_failed' }, 500);
    }

    // Hard-delete the Auth user. profiles.id references auth.users(id) ON DELETE CASCADE,
    // which also removes profile-owned rows configured with cascading foreign keys.
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(targetUserId, false);
    if (deleteError) {
      console.error('admin-delete-user auth deletion failed', deleteError);
      return json({ ok: false, error: 'delete_failed', detail: cleanError(deleteError) }, 500);
    }

    return json({ ok: true });
  } catch (error) {
    console.error('admin-delete-user error', error);
    return json({ ok: false, error: 'server_error', detail: cleanError(error) }, 500);
  }
});
