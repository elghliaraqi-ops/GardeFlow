import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const PARSER_REVISION = 'v12.0.2-r5';
const SHIFTS = new Set(['urg-jour', 'urg-nuit', 'urg-24h']);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function extractResponseText(payload: any): string {
  if (typeof payload?.output_text === 'string') return payload.output_text;
  const parts: string[] = [];
  for (const item of payload?.output ?? []) {
    for (const part of item?.content ?? []) {
      if (typeof part?.text === 'string') parts.push(part.text);
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
    // Continue with fenced / embedded JSON extraction.
  }
  const fenced = text.match(/\`\`\`(?:json)?\s*([\s\S]*?)\`\`\`/i);
  if (fenced) return JSON.parse(fenced[1]);
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) return JSON.parse(text.slice(start, end + 1));
  throw new Error('invalid_model_json');
}

function normalizeText(value: unknown): string {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('fr')
    .replace(/[’'\-–—]/g, ' ')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeNameList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const result: string[] = [];
  for (const raw of value) {
    const name = String(raw ?? '').replace(/\s+/g, ' ').trim();
    if (!name) continue;
    const key = normalizeText(name);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(name);
  }
  result.sort((a, b) => normalizeText(a).localeCompare(normalizeText(b), 'fr'));
  return result;
}

function validIsoDate(raw: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return false;
  const d = new Date(raw + 'T00:00:00Z');
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === raw;
}

type NormalizedRow = {
  date: string;
  shift: 'urg-jour' | 'urg-nuit' | 'urg-24h';
  names: string[];
  red_names: string[];
};

type NormalizedExtraction = {
  month: number | null;
  year: number | null;
  confidence: number;
  warnings: string[];
  rows: NormalizedRow[];
  validationErrors: string[];
};

function normalizeExtraction(raw: any): NormalizedExtraction {
  const merged = new Map<string, NormalizedRow>();
  const validationErrors: string[] = [];
  const rawRows = Array.isArray(raw?.rows) ? raw.rows : [];

  for (const candidate of rawRows) {
    const date = String(candidate?.date ?? '').trim();
    const shift = String(candidate?.shift ?? '').trim();
    if (!validIsoDate(date)) {
      validationErrors.push('Date invalide: ' + date);
      continue;
    }
    if (!SHIFTS.has(shift)) {
      validationErrors.push('Créneau invalide le ' + date + ': ' + shift);
      continue;
    }

    const names = normalizeNameList(candidate?.names);
    const redNames = normalizeNameList(candidate?.red_names);
    const key = date + '|' + shift;
    const existing = merged.get(key);
    if (!existing) {
      merged.set(key, {
        date,
        shift: shift as NormalizedRow['shift'],
        names,
        red_names: redNames,
      });
    } else {
      existing.names = normalizeNameList([...existing.names, ...names]);
      existing.red_names = normalizeNameList([
        ...existing.red_names,
        ...redNames,
      ]);
    }
  }

  const rows = [...merged.values()].sort(
    (a, b) => a.date.localeCompare(b.date) || a.shift.localeCompare(b.shift),
  );

  const byDate = new Map<string, Set<string>>();
  for (const row of rows) {
    if (!byDate.has(row.date)) byDate.set(row.date, new Set());
    byDate.get(row.date)!.add(row.shift);
  }

  const dates = [...byDate.keys()].sort();
  if (dates.length === 0) {
    validationErrors.push('Aucune date exploitable détectée.');
  } else {
    let cursor = new Date(dates[0] + 'T00:00:00Z');
    const last = new Date(dates[dates.length - 1] + 'T00:00:00Z');
    while (cursor <= last) {
      const key = cursor.toISOString().slice(0, 10);
      if (!byDate.has(key)) validationErrors.push('Date absente: ' + key);
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }

    for (const date of dates) {
      const shifts = byDate.get(date)!;
      const valid24 = shifts.size === 1 && shifts.has('urg-24h');
      const validSplit =
        shifts.size === 2 &&
        shifts.has('urg-jour') &&
        shifts.has('urg-nuit');
      if (!valid24 && !validSplit) {
        validationErrors.push(
          'Couverture incomplète ' + date + ': ' + [...shifts].sort().join(', '),
        );
      }
    }
  }

  const confidence =
    typeof raw?.confidence === 'number'
      ? Math.max(0, Math.min(1, raw.confidence))
      : 0;

  const warnings = Array.isArray(raw?.warnings)
    ? raw.warnings.map((w: any) => String(w)).slice(0, 50)
    : [];

  const month =
    Number.isInteger(raw?.month) && raw.month >= 1 && raw.month <= 12
      ? raw.month
      : null;
  const year =
    Number.isInteger(raw?.year) && raw.year >= 2020 && raw.year <= 2100
      ? raw.year
      : null;

  return {
    month,
    year,
    confidence,
    warnings,
    rows,
    validationErrors,
  };
}

function canonical(extraction: NormalizedExtraction): string {
  return extraction.rows
    .map((row) => {
      const names = row.names.map(normalizeText).sort().join(',');
      const red = row.red_names.map(normalizeText).sort().join(',');
      return row.date + '|' + row.shift + '|' + names + '|red:' + red;
    })
    .join('\n');
}

const extractionSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['month', 'year', 'confidence', 'warnings', 'rows'],
  properties: {
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
    warnings: {
      type: 'array',
      maxItems: 50,
      items: { type: 'string' },
    },
    rows: {
      type: 'array',
      maxItems: 100,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['date', 'shift', 'names', 'red_names'],
        properties: {
          date: {
            type: 'string',
            pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          },
          shift: {
            type: 'string',
            enum: ['urg-jour', 'urg-nuit', 'urg-24h'],
          },
          names: {
            type: 'array',
            maxItems: 16,
            items: { type: 'string' },
          },
          red_names: {
            type: 'array',
            maxItems: 16,
            items: { type: 'string' },
          },
        },
      },
    },
  },
};

const basePrompt = `
Tu es le vérificateur de planning officiel des gardes d'Urgences de GardeFlow.

OBJECTIF
Lire le PDF VISUELLEMENT, y compris s'il est scanné, vectorisé, mal ordonné dans sa couche texte ou si les cellules sont fusionnées. Extraire toutes les gardes de chaque date sans en oublier une.

RÈGLES
- N'invente jamais un nom, une date ou un créneau.
- Lis toutes les pages utiles.
- Repère le tableau des gardes d'Urgences, même si les intitulés diffèrent légèrement.
- "Jour", "08H-20H", "08:00-20:00", "8h à 20h" correspondent à urg-jour.
- "Nuit", "20H-08H", "20:00-08:00", "20h à 8h" correspondent à urg-nuit.
- Une cellule réellement fusionnée sur Jour + Nuit pour la même garde correspond à urg-24h.
- Si Jour et Nuit contiennent des noms différents, crée deux lignes distinctes.
- Une cellule peut contenir plusieurs médecins : conserve TOUS les noms réellement visibles.
- Pour chaque date couverte par le tableau, retourne soit une ligne urg-24h, soit exactement deux lignes urg-jour + urg-nuit, même si une cellule est vide (names=[]).
- Ne transforme jamais un titre, un service, "médecin de garde", "interne", "jour", "nuit" ou un numéro en nom de médecin.
- Si un nom est écrit en rouge, ajoute exactement ce nom dans red_names. N'ajoute personne à red_names par supposition.
- Respecte les changements de mois et d'année.
- Si une coquille de date est visuellement évidente au milieu d'une séquence continue, corrige-la seulement si le contexte est sans ambiguïté et ajoute un warning.
- confidence doit refléter la certitude de la lecture complète de TOUT le tableau, pas seulement de quelques cellules.
- En cas de doute sur une cellule, baisse confidence et ajoute un warning précis.
`;

async function uploadOpenAIFile(
  bytes: Uint8Array,
  fileName: string,
  key: string,
): Promise<string> {
  const form = new FormData();
  form.append('purpose', 'user_data');
  form.append(
    'file',
    new Blob([bytes], { type: 'application/pdf' }),
    fileName || 'planning-officiel.pdf',
  );
  const response = await fetch('https://api.openai.com/v1/files', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + key },
    body: form,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || typeof payload?.id !== 'string') {
    console.error('OpenAI file upload failed', response.status, payload);
    throw new Error('openai_file_upload_failed');
  }
  return payload.id;
}

async function deleteOpenAIFile(fileId: string, key: string) {
  try {
    await fetch('https://api.openai.com/v1/files/' + fileId, {
      method: 'DELETE',
      headers: { Authorization: 'Bearer ' + key },
    });
  } catch (_) {
    // Best-effort cleanup.
  }
}

async function runRead(
  fileId: string,
  key: string,
  extraPrompt: string,
  schemaName: string,
): Promise<NormalizedExtraction> {
  const model = Deno.env.get('OPENAI_VISION_MODEL') || 'gpt-5.6';
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + key,
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
              text: basePrompt + '\n\n' + extraPrompt,
            },
            {
              type: 'input_file',
              file_id: fileId,
            },
          ],
        },
      ],
      text: {
        format: {
          type: 'json_schema',
          name: schemaName,
          strict: true,
          schema: extractionSchema,
        },
      },
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error('OpenAI roster read failed', response.status, payload);
    throw new Error('openai_read_failed');
  }
  return normalizeExtraction(parseJsonLoose(extractResponseText(payload)));
}

function hospitalForSlot(slot: string): string | null {
  if (slot === 'hm6_bouskoura') {
    return 'Hôpital Universitaire International Mohammed VI de Bouskoura';
  }
  if (slot === 'hm6_rabat') {
    return 'Hôpital Universitaire International Mohammed VI de Rabat';
  }
  if (slot === 'hck_casa') {
    return 'Hôpital Universitaire International Cheikh Khalifa de Casablanca';
  }
  return null;
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
    const openAiKey = Deno.env.get('OPENAI_API_KEY');
    const authorization = req.headers.get('Authorization') ?? '';

    if (
      !supabaseUrl ||
      !anonKey ||
      !serviceRoleKey ||
      !authorization.startsWith('Bearer ')
    ) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }
    if (!openAiKey) {
      return json({ ok: false, error: 'verifier_not_configured' }, 503);
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

    const { data: callerProfile } = await adminClient
      .from('profiles')
      .select('id,role,account_status')
      .eq('id', callerId)
      .maybeSingle();
    if (
      !callerProfile ||
      callerProfile.role !== 'admin' ||
      callerProfile.account_status !== 'active'
    ) {
      return json({ ok: false, error: 'forbidden' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const resourceId =
      typeof body?.resourceId === 'string' ? body.resourceId.trim() : '';
    const tempStoragePath =
      typeof body?.tempStoragePath === 'string'
        ? body.tempStoragePath.trim()
        : '';

    let storagePath = '';
    let displayName = 'planning-officiel.pdf';
    let slot = '';
    let hospital = '';
    let resourceUpdatedAt = '';
    let cacheResourceId = '';

    if (/^[0-9a-f-]{36}$/i.test(resourceId)) {
      const { data: resource, error } = await adminClient
        .from('shared_resources')
        .select(
          'id,kind,slot,hospital,storage_path,display_name,mime_type,updated_at',
        )
        .eq('id', resourceId)
        .maybeSingle();
      if (
        error ||
        !resource ||
        resource.kind !== 'official_pdf' ||
        resource.mime_type !== 'application/pdf'
      ) {
        return json({ ok: false, error: 'resource_not_found' }, 404);
      }

      const { data: cached } = await adminClient
        .from('official_roster_verified_reads')
        .select('extraction')
        .eq('resource_id', resource.id)
        .eq('resource_updated_at', resource.updated_at)
        .eq('parser_revision', PARSER_REVISION)
        .maybeSingle();
      if (cached?.extraction?.verified === true) {
        return json({
          ok: true,
          cached: true,
          extraction: cached.extraction,
        });
      }

      storagePath = String(resource.storage_path);
      displayName = String(resource.display_name || displayName);
      slot = String(resource.slot || '');
      hospital = String(resource.hospital || hospitalForSlot(slot) || '');
      resourceUpdatedAt = String(resource.updated_at);
      cacheResourceId = String(resource.id);
    } else {
      slot = typeof body?.slot === 'string' ? body.slot.trim() : '';
      hospital = hospitalForSlot(slot) || '';
      displayName =
        typeof body?.displayName === 'string' && body.displayName.trim()
          ? body.displayName.trim()
          : displayName;
      const expectedPrefix = 'official_preflight/' + callerId + '/';
      if (
        !tempStoragePath ||
        !tempStoragePath.startsWith(expectedPrefix) ||
        !hospital
      ) {
        return json({ ok: false, error: 'invalid_preflight_resource' }, 400);
      }
      storagePath = tempStoragePath;
    }

    const { data: blob, error: downloadError } = await adminClient.storage
      .from('gardeflow-shared')
      .download(storagePath);
    if (downloadError || !blob) {
      console.error('Official PDF download failed', downloadError);
      return json({ ok: false, error: 'pdf_download_failed' }, 500);
    }

    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (bytes.length === 0 || bytes.length > 25 * 1024 * 1024) {
      return json({ ok: false, error: 'invalid_pdf_size' }, 400);
    }

    let openAiFileId = '';
    try {
      openAiFileId = await uploadOpenAIFile(bytes, displayName, openAiKey);

      const readA = await runRead(
        openAiFileId,
        openAiKey,
        'PREMIÈRE LECTURE: lis le PDF depuis zéro et rends le tableau complet.',
        'official_roster_read_a',
      );
      const readB = await runRead(
        openAiFileId,
        openAiKey,
        'DEUXIÈME LECTURE INDÉPENDANTE: relis le PDF depuis zéro. Ne suppose pas que la première lecture existe. Vérifie chaque date et chaque nom.',
        'official_roster_read_b',
      );

      let chosen: NormalizedExtraction | null = null;
      let agreement = '';
      if (
        readA.validationErrors.length === 0 &&
        readB.validationErrors.length === 0 &&
        canonical(readA) === canonical(readB)
      ) {
        chosen = readA;
        chosen.confidence = Math.min(readA.confidence, readB.confidence);
        chosen.warnings = [...new Set([...readA.warnings, ...readB.warnings])];
        agreement = 'A=B';
      } else {
        const adjudicationPrompt =
          'TROISIÈME LECTURE / ARBITRAGE. Les deux lectures précédentes ne sont pas identiques. Relis toi-même le PDF visuellement et rends la version exacte. Ne choisis pas par majorité sans vérifier le document.\n\nLecture A:\n' +
          JSON.stringify(readA) +
          '\n\nLecture B:\n' +
          JSON.stringify(readB);
        const readC = await runRead(
          openAiFileId,
          openAiKey,
          adjudicationPrompt,
          'official_roster_read_c',
        );

        if (
          readC.validationErrors.length === 0 &&
          canonical(readC) === canonical(readA)
        ) {
          chosen = readA;
          chosen.confidence = Math.min(readA.confidence, readC.confidence);
          chosen.warnings = [...new Set([...readA.warnings, ...readC.warnings])];
          agreement = 'A=C';
        } else if (
          readC.validationErrors.length === 0 &&
          canonical(readC) === canonical(readB)
        ) {
          chosen = readB;
          chosen.confidence = Math.min(readB.confidence, readC.confidence);
          chosen.warnings = [...new Set([...readB.warnings, ...readC.warnings])];
          agreement = 'B=C';
        } else {
          return json({
            ok: true,
            cached: false,
            extraction: {
              verified: false,
              parser_revision: PARSER_REVISION,
              engine: 'openai_pdf_triple_read',
              confidence: Math.min(
                readA.confidence,
                readB.confidence,
                readC.confidence,
              ),
              agreement: 'none',
              warnings: [
                'Les lectures indépendantes du PDF ne concordent pas. Import automatique bloqué.',
              ],
              rows: [],
              validation_errors: [
                ...readA.validationErrors,
                ...readB.validationErrors,
                ...readC.validationErrors,
              ],
            },
          });
        }
      }

      if (!chosen || chosen.confidence < 0.9) {
        return json({
          ok: true,
          cached: false,
          extraction: {
            verified: false,
            parser_revision: PARSER_REVISION,
            engine: 'openai_pdf_double_read',
            confidence: chosen?.confidence ?? 0,
            agreement,
            warnings: [
              ...(chosen?.warnings ?? []),
              'Confiance globale inférieure à 90 %. Import automatique bloqué.',
            ],
            rows: chosen?.rows ?? [],
            validation_errors: chosen?.validationErrors ?? [],
          },
        });
      }

      const extraction = {
        verified: true,
        parser_revision: PARSER_REVISION,
        engine: agreement === 'A=B'
          ? 'openai_pdf_double_read'
          : 'openai_pdf_triple_read',
        confidence: chosen.confidence,
        agreement,
        hospital,
        slot,
        month: chosen.month,
        year: chosen.year,
        warnings: chosen.warnings,
        rows: chosen.rows,
        validation_errors: [],
      };

      if (cacheResourceId && resourceUpdatedAt) {
        const { error: cacheError } = await adminClient
          .from('official_roster_verified_reads')
          .upsert(
            {
              resource_id: cacheResourceId,
              resource_updated_at: resourceUpdatedAt,
              parser_revision: PARSER_REVISION,
              engine: extraction.engine,
              extraction,
              confidence: extraction.confidence,
              warnings: extraction.warnings,
              created_at: new Date().toISOString(),
            },
            {
              onConflict:
                'resource_id,resource_updated_at,parser_revision',
            },
          );
        if (cacheError) {
          console.error('Verified roster cache failed', cacheError);
          return json({ ok: false, error: 'cache_failed' }, 500);
        }
      }

      return json({ ok: true, cached: false, extraction });
    } finally {
      if (openAiFileId) await deleteOpenAIFile(openAiFileId, openAiKey);
    }
  } catch (error) {
    console.error('analyze-official-roster-pdf error', error);
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
