import { createClient } from 'npm:@supabase/supabase-js@2.116.0';

const maxBytes = 25 * 1024 * 1024;
const allowedExtensions = new Set(['pdf', 'xlsx', 'xls']);

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function clean(value: string | null) {
  return (value ?? '').trim();
}

async function sha256Hex(value: string | Uint8Array) {
  const bytes =
    typeof value === 'string' ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function safeExtension(fileName: string) {
  const dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot === fileName.length - 1) return '';
  return fileName
    .substring(dot + 1)
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function hospitalSlot(hospital: string) {
  if (
    hospital ===
    'Hôpital Universitaire International Mohammed VI de Bouskoura'
  ) {
    return 'hm6_bouskoura';
  }
  if (
    hospital ===
    'Hôpital Universitaire International Mohammed VI de Rabat'
  ) {
    return 'hm6_rabat';
  }
  if (
    hospital ===
    'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
  ) {
    return 'hck_casa';
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'method_not_allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ ok: false, error: 'server_not_configured' }, 500);
  }

  const sourceId = clean(req.headers.get('x-gardeflow-source-id'));
  const sourceToken = clean(req.headers.get('x-gardeflow-source-token'));
  const messageId = clean(req.headers.get('x-gardeflow-message-id'));

  if (!sourceId || !sourceToken || !messageId) {
    return json({ ok: false, error: 'missing_authentication' }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: source, error: sourceError } = await admin
    .from('bloc_mail_sources')
    .select('id, hospital, provider, source_name, token_hash, enabled')
    .eq('id', sourceId)
    .maybeSingle();

  if (sourceError || !source || source.enabled !== true) {
    return json({ ok: false, error: 'source_not_found' }, 401);
  }

  const incomingHash = await sha256Hex(sourceToken);
  if (incomingHash !== source.token_hash) {
    return json({ ok: false, error: 'invalid_source_token' }, 401);
  }

  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return json({ ok: false, error: 'invalid_form_data' }, 400);
  }

  const uploaded = form.get('file');
  if (!(uploaded instanceof File)) {
    return json({ ok: false, error: 'missing_file' }, 400);
  }

  if (uploaded.size <= 0 || uploaded.size > maxBytes) {
    return json({ ok: false, error: 'invalid_file_size' }, 413);
  }

  const ext = safeExtension(uploaded.name);
  if (!allowedExtensions.has(ext)) {
    return json({ ok: false, error: 'unsupported_file_type' }, 415);
  }

  const slotName = hospitalSlot(source.hospital);
  if (!slotName) {
    return json({ ok: false, error: 'invalid_hospital' }, 400);
  }

  const raw = new Uint8Array(await uploaded.arrayBuffer());
  const fileHash = await sha256Hex(raw);
  const dedupeHash = await sha256Hex(
    source.id + ':' + messageId + ':' + fileHash,
  );
  const resourceSlot = 'mail_' + dedupeHash;

  const { data: existing, error: existingError } = await admin
    .from('shared_resources')
    .select('id, storage_path, display_name')
    .eq('kind', 'bloc_program')
    .eq('slot', resourceSlot)
    .maybeSingle();

  if (existingError) {
    console.error('bloc-program-ingest lookup failed', existingError);
    return json({ ok: false, error: 'lookup_failed' }, 500);
  }

  if (existing) {
    return json({
      ok: true,
      duplicate: true,
      resource_id: existing.id,
      display_name: existing.display_name,
    });
  }

  const mimeType =
    clean(uploaded.type) ||
    (ext === 'pdf'
      ? 'application/pdf'
      : ext === 'xlsx'
        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        : 'application/vnd.ms-excel');

  const storagePath =
    'bloc-programs/' +
    slotName +
    '/mail/' +
    dedupeHash +
    '.' +
    ext;

  const { error: uploadError } = await admin.storage
    .from('gardeflow-shared')
    .upload(storagePath, raw, {
      contentType: mimeType,
      cacheControl: '3600',
      upsert: false,
    });

  if (uploadError) {
    console.error('bloc-program-ingest storage upload failed', uploadError);
    return json({ ok: false, error: 'storage_upload_failed' }, 500);
  }

  const now = new Date().toISOString();
  const { data: inserted, error: insertError } = await admin
    .from('shared_resources')
    .insert({
      kind: 'bloc_program',
      slot: resourceSlot,
      hospital: source.hospital,
      storage_path: storagePath,
      display_name: uploaded.name,
      mime_type: mimeType,
      uploaded_by: null,
      created_at: now,
      updated_at: now,
    })
    .select('id, display_name, created_at')
    .single();

  if (insertError) {
    console.error('bloc-program-ingest metadata insert failed', insertError);
    await admin.storage.from('gardeflow-shared').remove([storagePath]);
    return json({ ok: false, error: 'metadata_insert_failed' }, 500);
  }

  return json({
    ok: true,
    duplicate: false,
    resource_id: inserted.id,
    display_name: inserted.display_name,
    created_at: inserted.created_at,
    hospital: source.hospital,
    provider: source.provider,
  });
});
