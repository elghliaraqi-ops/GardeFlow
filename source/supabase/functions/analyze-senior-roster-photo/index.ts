import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import {
  ImageMagick,
  initializeImageMagick,
  MagickFormat,
} from 'npm:@imagemagick/magick-wasm@0.0.30';

const magickWasm = await Deno.readFile(
  new URL(
    'magick.wasm',
    import.meta.resolve('npm:@imagemagick/magick-wasm@0.0.30'),
  ),
);
await initializeImageMagick(magickWasm);

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
  try {
    return JSON.parse(text);
  } catch (_) {
    // Continue with tolerant extraction.
  }
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced) return JSON.parse(fenced[1]);
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) return JSON.parse(text.slice(start, end + 1));
  throw new Error('invalid_model_json');
}

function cleanPhone(value: unknown): string {
  return String(value ?? '')
    .trim()
    .replace(/\s+/g, ' ');
}

function normalizeDraft(raw: any, hospital: string) {
  const sourceRows = Array.isArray(raw?.rows) ? raw.rows : [];
  const merged = new Map<string, any>();

  for (const candidate of sourceRows) {
    const name = String(candidate?.name ?? '').trim();
    const service = String(candidate?.service ?? raw?.service ?? '').trim();
    const phone = cleanPhone(candidate?.phone);
    const dates = Array.isArray(candidate?.dates)
      ? candidate.dates
          .map((d: any) => String(d).trim())
          .filter((d: string) => /^\d{4}-\d{2}-\d{2}$/.test(d))
      : [];
    const confidence = typeof candidate?.confidence === 'number'
      ? Math.max(0, Math.min(1, candidate.confidence))
      : 0.5;

    if (!name || !service || dates.length === 0) continue;

    const key = `${service.toLocaleLowerCase('fr')}|${name.toLocaleLowerCase('fr')}`;
    const existing = merged.get(key);
    if (!existing) {
      merged.set(key, {
        name,
        service,
        phone,
        dates: [...new Set(dates)].sort(),
        confidence,
      });
      continue;
    }

    existing.dates = [...new Set([...existing.dates, ...dates])].sort();
    existing.confidence = Math.max(existing.confidence, confidence);
    if (!existing.phone && phone) existing.phone = phone;
  }

  const rows = [...merged.values()]
    .sort((a, b) =>
      a.service.localeCompare(b.service, 'fr') ||
      a.name.localeCompare(b.name, 'fr'))
    .slice(0, 160);

  return {
    hospital,
    service: String(raw?.service ?? '').trim(),
    month:
      Number.isInteger(raw?.month) && raw.month >= 1 && raw.month <= 12
        ? raw.month
        : null,
    year:
      Number.isInteger(raw?.year) && raw.year >= 2020 && raw.year <= 2100
        ? raw.year
        : null,
    confidence:
      typeof raw?.confidence === 'number'
        ? Math.max(0, Math.min(1, raw.confidence))
        : 0.5,
    warnings: Array.isArray(raw?.warnings)
      ? raw.warnings.map((w: any) => String(w)).slice(0, 40)
      : [],
    rows,
  };
}

const extractionSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['service', 'month', 'year', 'confidence', 'warnings', 'rows'],
  properties: {
    service: { type: 'string' },
    month: {
      anyOf: [
        { type: 'integer', minimum: 1, maximum: 12 },
        { type: 'null' },
      ],
    },
    year: {
      anyOf: [
        { type: 'integer', minimum: 2020, maximum: 2100 },
        { type: 'null' },
      ],
    },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
    warnings: { type: 'array', items: { type: 'string' }, maxItems: 40 },
    rows: {
      type: 'array',
      maxItems: 160,
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
Tu extrais les ASTREINTES DES MÉDECINS SÉNIORS d'une photographie de planning hospitalier.
Le résultat reste toujours un BROUILLON soumis à validation humaine avant publication.

MÉTHODE À SUIVRE:
1. Identifier le service, le mois et l'année dans l'en-tête.
2. Identifier la géométrie du tableau: colonnes de dates, Sénior, Résident, Jour/Nuit, adulte/pédiatrique.
3. Lire toutes les lignes de dates de haut en bas. Une cellule Sénior fusionnée verticalement s'applique à toutes les dates couvertes jusqu'au prochain nom Sénior.
4. Lire ensuite la zone GSM/téléphones en bas de feuille et associer un numéro uniquement au bon médecin.
5. Regrouper un même médecin + même type de service sur une seule ligne avec toutes ses dates.
6. Vérifier une seconde fois les dates et les téléphones avant de répondre.

RÈGLES IMPÉRATIVES:
- Ne jamais inventer un nom, un numéro ou une date.
- Extraire les médecins séniors / médecins d'astreinte principaux. Exclure les résidents lorsque la feuille distingue "Médecin Sénior" et "Médecin Résident".
- Si un téléphone n'est pas clairement attribuable, phone="" et ajouter un warning.
- Développer toutes les plages: 01–06 signifie six dates distinctes.
- Conserver plusieurs séniors le même jour s'ils sont tous réellement indiqués.
- Utiliser uniquement des dates ISO YYYY-MM-DD.
- Si le titre indique par exemple SEPTEMBRE 2026 mais quelques lignes imprimées affichent 16/09/2027 ou 17/09/2027 au milieu d'une séquence 2026, considérer cela comme une erreur de gabarit seulement si le contexte est sans ambiguïté; corriger vers 2026 ET ajouter un warning explicite.
- Ne jamais transformer "MEDECIN DE GARDE" en nom de personne.
- Ne jamais utiliser un nom de résident comme sénior.
- Respecter les annotations manuscrites lorsqu'elles corrigent clairement une cellule imprimée, et ajouter un warning indiquant qu'une correction manuscrite a été suivie.

CAS SPÉCIAUX OBLIGATOIRES:
- USIP: séparer exactement "USIP — Jour" et "USIP — Nuit".
- Réanimation adultes + pédiatrique: séparer exactement:
  "Réanimation adulte — Jour",
  "Réanimation pédiatrique — Jour",
  "Réanimation adulte — Nuit",
  "Réanimation pédiatrique + bloc — Nuit".
- Ne fusionner JAMAIS les quatre colonnes de réanimation.
- Si une feuille comporte JOUR et NUIT pour un autre service, conserver ces catégories séparées dans service.

CONTRÔLES DE QUALITÉ:
- Vérifier qu'un même médecin n'a pas des dates contradictoires par simple répétition OCR.
- Vérifier les chiffres de téléphone caractère par caractère. Ne jamais compléter un chiffre manquant par intuition.
- En cas d'ambiguïté, diminuer confidence et ajouter un warning précis.
- service au niveau racine = nom général de la feuille (ex. "USIP", "Réanimation adultes + pédiatrique", "Urologie").
`;

function enhanceForOcr(bytes: Uint8Array): Uint8Array {
  return ImageMagick.read(bytes, (img): Uint8Array => {
    img.autoOrient();
    if (img.width < 2200) {
      const ratio = 2200 / Math.max(1, img.width);
      img.resize(2200, Math.max(1, Math.round(img.height * ratio)));
    }
    img.autoLevel();
    img.adaptiveSharpen(0, 1.1);
    img.format = MagickFormat.Png;
    return img.write((data) => data);
  });
}

async function runOcr(bytes: Uint8Array) {
  const { createWorker, PSM } = await import('npm:tesseract.js@7.0.0');
  const worker = await createWorker('fra+eng');
  try {
    await worker.setParameters({
      user_defined_dpi: '300',
      preserve_interword_spaces: '1',
      tessedit_pageseg_mode: PSM.SPARSE_TEXT,
    });
    const sparse = await worker.recognize(
      bytes,
      {},
      { text: true, tsv: true },
    );

    let blockText = '';
    let blockConfidence = 0;
    if (
      String(sparse.data.text ?? '').trim().length < 900 ||
      Number(sparse.data.confidence ?? 0) < 70
    ) {
      await worker.setParameters({
        user_defined_dpi: '300',
        preserve_interword_spaces: '1',
        tessedit_pageseg_mode: PSM.SINGLE_BLOCK,
      });
      const block = await worker.recognize(
        bytes,
        {},
        { text: true, tsv: true },
      );
      blockText = String(block.data.text ?? '');
      blockConfidence = Number(block.data.confidence ?? 0);
    }

    const sparseText = String(sparse.data.text ?? '');
    const combined = [
      '=== OCR SPARSE TEXT ===',
      sparseText,
      blockText.trim().isEmpty ? '' : '=== OCR SINGLE BLOCK ===',
      blockText,
    ].filter(Boolean).join('\n');

    return {
      text: combined,
      confidence: Math.max(Number(sparse.data.confidence ?? 0), blockConfidence),
      tsv: String(sparse.data.tsv ?? ''),
    };
  } finally {
    await worker.terminate();
  }
}

async function analyzeWithOpenAI(
  original: Uint8Array,
  enhanced: Uint8Array,
  mimeType: string,
  ocrText: string,
) {
  const key = Deno.env.get('OPENAI_API_KEY');
  if (!key) return null;

  const model = Deno.env.get('OPENAI_VISION_MODEL') || 'gpt-5.6';
  const originalData = `data:${mimeType};base64,${toBase64(original)}`;
  const enhancedData = `data:image/png;base64,${toBase64(enhanced)}`;
  const ocrAssist = ocrText.trim().isEmpty
    ? 'Aucun texte OCR auxiliaire disponible.'
    : `Texte OCR auxiliaire (peut contenir des erreurs; la photo reste la source de vérité):\n${ocrText.slice(0, 26000)}`;

  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      store: false,
      input: [
        {
          role: 'user',
          content: [
            {
              type: 'input_text',
              text: `${systemPrompt}\n\n${ocrAssist}\n\nCompare l'image originale, la version améliorée et l'OCR. En cas de désaccord, privilégie ce qui est visuellement lisible sur la feuille.`,
            },
            {
              type: 'input_image',
              image_url: originalData,
              detail: 'high',
            },
            {
              type: 'input_image',
              image_url: enhancedData,
              detail: 'high',
            },
          ],
        },
      ],
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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'method_not_allowed' }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const authorization = req.headers.get('Authorization') ?? '';

    if (
      !supabaseUrl ||
      !anonKey ||
      !serviceRoleKey ||
      !authorization.startsWith('Bearer ')
    ) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerData, error: callerError } =
      await callerClient.auth.getUser();
    const callerId = callerData.user?.id;
    if (callerError || !callerId) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

    const { data: callerProfile, error: profileError } = await adminClient
      .from('profiles')
      .select('id,role,account_status')
      .eq('id', callerId)
      .maybeSingle();

    if (
      profileError ||
      !callerProfile ||
      callerProfile.role !== 'admin' ||
      callerProfile.account_status !== 'active'
    ) {
      return json({ ok: false, error: 'forbidden' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const resourceId =
      typeof body?.resourceId === 'string' ? body.resourceId.trim() : '';
    if (!/^[0-9a-f-]{36}$/i.test(resourceId)) {
      return json({ ok: false, error: 'invalid_resource' }, 400);
    }

    const { data: resource, error: resourceError } = await adminClient
      .from('shared_resources')
      .select('id,kind,hospital,storage_path,mime_type,display_name')
      .eq('id', resourceId)
      .maybeSingle();

    if (
      resourceError ||
      !resource ||
      resource.kind !== 'astreinte_photo' ||
      !resource.hospital
    ) {
      return json({ ok: false, error: 'resource_not_found' }, 404);
    }

    const { data: blob, error: downloadError } = await adminClient.storage
      .from('gardeflow-shared')
      .download(resource.storage_path);
    if (downloadError || !blob) {
      console.error('Image download failed', downloadError);
      return json({ ok: false, error: 'image_download_failed' }, 500);
    }

    const original = new Uint8Array(await blob.arrayBuffer());
    if (original.length === 0 || original.length > 12 * 1024 * 1024) {
      return json({ ok: false, error: 'invalid_image_size' }, 400);
    }

    const warnings: string[] = [];
    let enhanced = original;
    try {
      enhanced = enhanceForOcr(original);
    } catch (error) {
      console.error('Image enhancement failed', error);
      warnings.push(
        'Prétraitement de l’image indisponible; analyse effectuée sur la photo originale.',
      );
    }

    let ocrText = '';
    let ocrConfidence = 0;
    try {
      const ocr = await runOcr(enhanced);
      ocrText = ocr.text;
      ocrConfidence = ocr.confidence;
      if (ocrConfidence > 0 && ocrConfidence < 65) {
        warnings.push(
          `OCR de confiance limitée (${Math.round(ocrConfidence)} %): vérifier soigneusement noms, dates et numéros.`,
        );
      }
    } catch (error) {
      console.error('OCR failed', error);
      warnings.push('OCR auxiliaire indisponible sur cette photo.');
    }

    let engine = 'openai_vision_ocr_assisted';
    let extracted: any = null;
    try {
      extracted = await analyzeWithOpenAI(
        original,
        enhanced,
        resource.mime_type || 'image/jpeg',
        ocrText,
      );
    } catch (error) {
      console.error('Vision analysis failed', error);
      warnings.push(
        'Analyse visuelle avancée indisponible; le brouillon reste en vérification manuelle.',
      );
    }

    if (!extracted) {
      engine = 'ocr_review_assist';
      extracted = {
        service: '',
        month: null,
        year: null,
        confidence: ocrConfidence > 0 ? Math.min(0.49, ocrConfidence / 100) : 0,
        warnings: [
          ocrText.trim().isEmpty
            ? 'Aucun texte OCR exploitable n’a été reconnu automatiquement.'
            : 'Le texte OCR a été amélioré et conservé comme aide, mais aucune affectation n’est créée automatiquement sans analyse visuelle structurée.',
        ],
        rows: [],
      };
    }

    const draft = normalizeDraft(extracted, resource.hospital);
    draft.warnings.unshift(...warnings);

    if (draft.rows.length === 0 && ocrText.trim()) {
      draft.warnings.push(
        'Utilisez « Ajouter » dans l’écran de vérification pour saisir/corriger les lignes si nécessaire.',
      );
    }

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
      raw_text: ocrText || null,
      created_by: callerId,
      updated_at: new Date().toISOString(),
      published_at: null,
    };

    const { data: saved, error: saveError } = await adminClient
      .from('senior_oncall_imports')
      .upsert(importRow, { onConflict: 'resource_id' })
      .select(
        'id,resource_id,hospital,status,detected_service,detected_month,detected_year,confidence,analysis_engine,draft_rows,warnings,updated_at',
      )
      .single();

    if (saveError) {
      console.error('Save analysis failed', saveError);
      return json({ ok: false, error: 'analysis_save_failed' }, 500);
    }

    return json({
      ok: true,
      import: saved,
      diagnostics: {
        ocrConfidence: Math.round(ocrConfidence),
        enhancedImage: enhanced !== original,
        advancedVisionConfigured: Boolean(Deno.env.get('OPENAI_API_KEY')),
      },
    });
  } catch (error) {
    console.error('analyze-senior-roster-photo error', error);
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
