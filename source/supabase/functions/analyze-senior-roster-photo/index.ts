import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function toBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function extractResponseText(payload: any): string {
  if (typeof payload?.output_text === 'string') return payload.output_text;
  const parts: string[] = [];
  for (const item of payload?.output ?? []) {
    for (const content of item?.content ?? []) {
      if (typeof content?.text === 'string') parts.push(content.text);
    }
  }
  return parts.join('\n');
}

function parseJsonLoose(raw: string): any {
  const text = raw.trim();
  if (!text) throw new Error('empty_model_output');
  try { return JSON.parse(text); } catch (_) {}
  const fenced = text.match(/\`\`\`(?:json)?\s*([\s\S]*?)\`\`\`/i);
  if (fenced) return JSON.parse(fenced[1]);
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) return JSON.parse(text.slice(start, end + 1));
  throw new Error('invalid_model_json');
}

function normalizeDraft(raw: any, hospital: string) {
  const rows = Array.isArray(raw?.rows) ? raw.rows : [];
  const normalizedRows = rows.map((r: any) => ({
    name: String(r?.name ?? '').trim(),
    service: String(r?.service ?? raw?.service ?? '').trim(),
    phone: String(r?.phone ?? '').trim(),
    dates: Array.isArray(r?.dates)
      ? r.dates.map((d: any) => String(d).trim()).filter((d: string) => /^\d{4}-\d{2}-\d{2}$/.test(d))
      : [],
    confidence: typeof r?.confidence === 'number' ? Math.max(0, Math.min(1, r.confidence)) : 0.5,
  })).filter((r: any) => r.name && r.service && r.dates.length > 0);

  return {
    hospital,
    service: String(raw?.service ?? '').trim(),
    month: Number.isInteger(raw?.month) && raw.month >= 1 && raw.month <= 12 ? raw.month : null,
    year: Number.isInteger(raw?.year) && raw.year >= 2020 && raw.year <= 2100 ? raw.year : null,
    confidence: typeof raw?.confidence === 'number' ? Math.max(0, Math.min(1, raw.confidence)) : 0.5,
    warnings: Array.isArray(raw?.warnings) ? raw.warnings.map((w: any) => String(w)).slice(0, 30) : [],
    rows: normalizedRows,
  };
}

const extractionSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['service', 'month', 'year', 'confidence', 'warnings', 'rows'],
  properties: {
    service: { type: 'string' },
    month: { anyOf: [{ type: 'integer', minimum: 1, maximum: 12 }, { type: 'null' }] },
    year: { anyOf: [{ type: 'integer', minimum: 2020, maximum: 2100 }, { type: 'null' }] },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
    warnings: { type: 'array', items: { type: 'string' }, maxItems: 30 },
    rows: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'service', 'phone', 'dates', 'confidence'],
        properties: {
          name: { type: 'string' },
          service: { type: 'string' },
          phone: { type: 'string' },
          dates: {
            type: 'array',
            items: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
          },
          confidence: { type: 'number', minimum: 0, maximum: 1 },
        },
      },
    },
  },
};

const systemPrompt = `
Tu extrais des tableaux d'astreintes médicales hospitalières à partir d'une PHOTO.
Le résultat est toujours un BROUILLON destiné à une validation humaine avant publication.

Règles impératives:
- Ne jamais inventer un nom, un numéro ou une date.
- Extraire les médecins séniors / médecins d'astreinte principaux. Exclure les résidents lorsqu'une colonne "Médecin Résident" existe.
- Un numéro n'est associé à un médecin que si la correspondance est suffisamment claire. Sinon phone="" et ajouter un warning.
- Développer les plages/blocs: si un médecin couvre 01-06 septembre, retourner chaque date.
- Conserver plusieurs médecins le même jour s'ils sont tous indiqués.
- Utiliser les dates ISO YYYY-MM-DD.
- Le mois/année du titre de la feuille prime sur les erreurs de gabarit évidentes seulement si la séquence rend la correction claire; dans ce cas corriger et ajouter un warning.
- Cas USIP: séparer obligatoirement "USIP — Jour" et "USIP — Nuit".
- Cas Réanimation adultes + pédiatrique: séparer obligatoirement:
  "Réanimation adulte — Jour",
  "Réanimation pédiatrique — Jour",
  "Réanimation adulte — Nuit",
  "Réanimation pédiatrique + bloc — Nuit".
- Pour une feuille de réanimation, ne fusionner JAMAIS les quatre colonnes.
- Si une information est illisible ou ambiguë, ne pas la deviner: l'omettre et l'indiquer dans warnings.
- service au niveau racine = service général de la feuille (ex. "USIP", "Réanimation adultes + pédiatrique", "Urologie").
`;

async function analyzeWithOpenAI(bytes: Uint8Array, mimeType: string) {
  const key = Deno.env.get('OPENAI_API_KEY');
  if (!key) return null;
  const model = Deno.env.get('OPENAI_VISION_MODEL') || 'gpt-5.6';
  const image = `data:${mimeType};base64,${toBase64(bytes)}`;

  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      store: false,
      input: [{
        role: 'user',
        content: [
          { type: 'input_text', text: systemPrompt + '\nAnalyse cette feuille avec attention.' },
          { type: 'input_image', image_url: image, detail: 'original' },
        ],
      }],
      text: {
        format: {
          type: 'json_schema',
          name: 'senior_oncall_photo_extraction',
          strict: true,
          schema: extractionSchema,
        },
      },
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error('OpenAI analysis failed', response.status, payload);
    throw new Error('openai_analysis_failed');
  }
  return parseJsonLoose(extractResponseText(payload));
}

async function analyzeWithTesseract(bytes: Uint8Array) {
  const { createWorker } = await import('npm:tesseract.js@7.0.0');
  const worker = await createWorker('fra+eng');
  try {
    const result = await worker.recognize(bytes, { rotateAuto: true });
    return String(result?.data?.text ?? '');
  } finally {
    await worker.terminate();
  }
}

async function structureOcrWithSupabaseAi(ocrText: string) {
  if (!ocrText.trim()) return null;
  try {
    const session = new Supabase.ai.Session('mistral');
    const prompt = systemPrompt + `
Tu ne vois pas l'image directement. Voici le texte OCR brut de la feuille.
Reconstruis le tableau prudemment. Réponds UNIQUEMENT en JSON avec:
{"service":"","month":null,"year":null,"confidence":0.0,"warnings":[],"rows":[{"name":"","service":"","phone":"","dates":["YYYY-MM-DD"],"confidence":0.0}]}
Si les colonnes ne peuvent pas être distinguées avec certitude, laisse rows vide et explique dans warnings.

OCR:
${ocrText.slice(0, 24000)}
`;
    const output: any = await session.run(prompt);
    const raw = typeof output === 'string'
      ? output
      : typeof output?.response === 'string'
        ? output.response
        : JSON.stringify(output);
    return parseJsonLoose(raw);
  } catch (error) {
    console.error('Supabase AI structuring failed', error);
    return null;
  }
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
      .select('id,role,account_status')
      .eq('id', callerId)
      .maybeSingle();

    if (profileError || !callerProfile || callerProfile.role !== 'admin' || callerProfile.account_status !== 'active') {
      return json({ ok: false, error: 'forbidden' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const resourceId = typeof body?.resourceId === 'string' ? body.resourceId.trim() : '';
    if (!/^[0-9a-f-]{36}$/i.test(resourceId)) {
      return json({ ok: false, error: 'invalid_resource' }, 400);
    }

    const { data: resource, error: resourceError } = await adminClient
      .from('shared_resources')
      .select('id,kind,hospital,storage_path,mime_type,display_name')
      .eq('id', resourceId)
      .maybeSingle();

    if (resourceError || !resource || resource.kind !== 'astreinte_photo' || !resource.hospital) {
      return json({ ok: false, error: 'resource_not_found' }, 404);
    }

    const { data: blob, error: downloadError } = await adminClient.storage
      .from('gardeflow-shared')
      .download(resource.storage_path);
    if (downloadError || !blob) {
      console.error('Image download failed', downloadError);
      return json({ ok: false, error: 'image_download_failed' }, 500);
    }

    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (bytes.length === 0 || bytes.length > 12 * 1024 * 1024) {
      return json({ ok: false, error: 'invalid_image_size' }, 400);
    }

    let engine = 'openai_vision';
    let rawText: string | null = null;
    let extracted: any = null;
    const warnings: string[] = [];

    try {
      extracted = await analyzeWithOpenAI(bytes, resource.mime_type || 'image/jpeg');
    } catch (error) {
      warnings.push('Analyse visuelle OpenAI indisponible; bascule OCR sécurisée.');
      console.error('OpenAI path failed', error);
    }

    if (!extracted) {
      engine = 'tesseract_supabase_ai';
      try {
        rawText = await analyzeWithTesseract(bytes);
        extracted = await structureOcrWithSupabaseAi(rawText);
      } catch (error) {
        console.error('OCR path failed', error);
        warnings.push('OCR automatique indisponible sur ce document.');
      }
    }

    if (!extracted) {
      engine = 'manual_review_required';
      extracted = {
        service: '',
        month: null,
        year: null,
        confidence: 0,
        warnings: ['Analyse automatique incomplète: saisie/correction manuelle requise.'],
        rows: [],
      };
    }

    const draft = normalizeDraft(extracted, resource.hospital);
    draft.warnings.unshift(...warnings);

    const importRow = {
      resource_id: resource.id,
      hospital: resource.hospital,
      status: 'draft',
      detected_service: draft.service || null,
      detected_month: draft.month,
      detected_year: draft.year,
      confidence: draft.confidence,
      analysis_engine: engine,
      draft_rows: draft.rows,
      warnings: draft.warnings,
      raw_text: rawText,
      created_by: callerId,
      updated_at: new Date().toISOString(),
      published_at: null,
    };

    const { data: saved, error: saveError } = await adminClient
      .from('senior_oncall_imports')
      .upsert(importRow, { onConflict: 'resource_id' })
      .select('id,resource_id,hospital,status,detected_service,detected_month,detected_year,confidence,analysis_engine,draft_rows,warnings,updated_at')
      .single();

    if (saveError) {
      console.error('Save analysis failed', saveError);
      return json({ ok: false, error: 'analysis_save_failed' }, 500);
    }

    return json({ ok: true, import: saved });
  } catch (error) {
    console.error('analyze-senior-roster-photo error', error);
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
