import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const axisEnum = [
  'cours_fondamental',
  'diagnostic',
  'explorations',
  'prise_en_charge',
  'recommandations',
] as const;
const topicEnum = [
  'motif',
  'symptome',
  'examen',
  'imagerie',
  'synthese',
  'prise_en_charge',
  'orientation',
  'avis_specialise',
] as const;
const sourceKindEnum = ['recommandation', 'consensus', 'revue', 'cours'] as const;
const maxCasePayloadChars = 14000;
const requestTimeoutMs = 60000;

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin')?.trim() ?? '';
  const configured = (Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
  if (!origin) return headers;
  if (configured.length === 0) {
    // Compatibility fallback until production origins are explicitly configured.
    // JWT authentication remains mandatory; CORS is never used as authentication.
    headers['Access-Control-Allow-Origin'] = '*';
  } else if (configured.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Vary'] = 'Origin';
  }
  return headers;
}

function json(req: Request, body: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      ...extraHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}

function safeCode(value: unknown, fallback = 'unknown'): string {
  const raw = String(value ?? '').trim();
  return /^[a-zA-Z0-9_.:-]{1,80}$/.test(raw) ? raw : fallback;
}

async function shortHash(value: string): Promise<string> {
  try {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
    return Array.from(new Uint8Array(digest).slice(0, 6))
      .map((x) => x.toString(16).padStart(2, '0'))
      .join('');
  } catch (_) {
    return 'hash_unavailable';
  }
}

function logEvent(event: string, fields: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ event, ...fields }));
}

function scrub(value: unknown, max = 2200): string {
  let x = String(value ?? '').trim();
  if (!x) return '';
  x = x.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email masqué]');
  x = x.replace(/\b\d{4}-\d{2}-\d{2}\b/g, '[date masquée]');
  x = x.replace(/\b[0-3]?\d[/-][01]?\d[/-]\d{2,4}\b/g, '[date masquée]');
  x = x.replace(/\+?\d[\d .()/-]{7,}\d/g, '[téléphone masqué]');
  x = x.replace(
    /\b(nom|prénom|prenom|patient|patiente|ipp|cin|dossier(?: patient)?|date de naissance|né(?:e)? le|adresse|address|domicile|téléphone|telephone|tel)\b\s*[:=-]\s*[^,;\n]{1,140}/gi,
    '$1 : [masqué]',
  );
  x = x.replace(
    /\b(?:M\.|Mr|Mme|Monsieur|Madame)\s+[A-ZÀ-ÖØ-Ý][A-Za-zÀ-ÿ'’-]{1,40}(?:\s+[A-ZÀ-ÖØ-Ý][A-Za-zÀ-ÿ'’-]{1,40})?/g,
    '[identité masquée]',
  );
  x = x.replace(/\b[A-Z]{1,4}\d{5,}\b/gi, '[identifiant masqué]');
  x = x.replace(/\b\d{7,}\b/g, '[identifiant masqué]');
  return x.slice(0, max).trim();
}

function anonymizedCase(post: any): Record<string, string> {
  const build = (limit: number) => ({
    age_band: scrub(post.age_band, 80),
    sex: scrub(post.sex, 40),
    presentation: scrub(post.presentation, limit),
    history: scrub(post.history, limit),
    clinical_exam: scrub(post.clinical_exam, limit),
    complementary_exams: scrub(post.complementary_exams, limit),
    imaging_conclusion: scrub(post.imaging_conclusion, limit),
    assessment: scrub(post.assessment, limit),
    plan: scrub(post.plan, limit),
    disposition: scrub(post.disposition, Math.min(limit, 700)),
    specialist_service: scrub(post.specialist_service, 300),
  });
  let result = build(2200);
  if (JSON.stringify(result).length > maxCasePayloadChars) result = build(900);
  return result;
}

function canonicalUrl(value: unknown): string {
  try {
    const url = new URL(String(value ?? '').trim());
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return '';
    url.hash = '';
    url.search = '';
    const path = url.pathname.replace(/\/+$/, '') || '/';
    return `${url.protocol}//${url.hostname.toLowerCase()}${path}`;
  } catch (_) {
    return '';
  }
}

type WebSource = { title: string; url: string };
function extractWebSources(payload: any): WebSource[] {
  const byUrl = new Map<string, WebSource>();
  const add = (title: unknown, url: unknown) => {
    const rawUrl = String(url ?? '').trim();
    const key = canonicalUrl(rawUrl);
    if (!key || byUrl.has(key)) return;
    byUrl.set(key, { title: scrub(title, 500), url: rawUrl });
  };
  for (const item of payload?.output ?? []) {
    if (item?.type === 'web_search_call') {
      for (const source of item?.action?.sources ?? []) add(source?.title, source?.url);
    }
    for (const content of item?.content ?? []) {
      for (const annotation of content?.annotations ?? []) {
        if (annotation?.type === 'url_citation') {
          add(
            annotation?.title ?? annotation?.url_citation?.title,
            annotation?.url ?? annotation?.url_citation?.url,
          );
        }
      }
    }
  }
  return [...byUrl.values()];
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

const referenceSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'organization', 'year', 'url', 'kind'],
  properties: {
    title: { type: 'string', minLength: 1 },
    organization: { type: 'string', minLength: 1 },
    year: { type: 'string', minLength: 4 },
    url: { type: 'string', minLength: 8 },
    kind: { type: 'string', enum: sourceKindEnum },
  },
};
const qcmItemSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['axis', 'question', 'options', 'correct_index', 'correction', 'topic', 'references'],
  properties: {
    axis: { type: 'string', enum: axisEnum },
    question: { type: 'string', minLength: 12 },
    options: {
      type: 'array',
      minItems: 4,
      maxItems: 4,
      items: { type: 'string', minLength: 1 },
    },
    correct_index: { type: 'integer', minimum: 0, maximum: 3 },
    correction: { type: 'string', minLength: 20 },
    topic: { type: 'string', enum: topicEnum },
    references: {
      type: 'array',
      minItems: 1,
      maxItems: 3,
      items: referenceSchema,
    },
  },
};
const fiveQcmSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['qcms'],
  properties: {
    qcms: { type: 'array', minItems: 5, maxItems: 5, items: qcmItemSchema },
  },
};

const genericQuestionPatterns = [
  /dans ce cas(?: clinique)?/i,
  /document(?:é|ée|és|ées)/i,
  /effectivement/i,
  /quelle synthèse clinique a été retenue/i,
  /quelle prise en charge a été/i,
  /quelle orientation a été/i,
  /quel avis spécialisé a été/i,
  /quel élément .* est .* dans ce cas/i,
];

function formatCorrection(correction: string, references: Array<any>): string {
  const lines = references.map(
    (ref) => `${ref.kind}|||${ref.title}|||${ref.organization}|||${ref.year}|||${ref.url}`,
  );
  return `${correction}\n\n§SOURCES§\n${lines.join('\n')}`.slice(0, 9000);
}

function retrySeconds(retryAfter: unknown): number | null {
  const date = Date.parse(String(retryAfter ?? ''));
  if (!Number.isFinite(date)) return null;
  return Math.max(1, Math.ceil((date - Date.now()) / 1000));
}

Deno.serve(async (req: Request) => {
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();
  const executionId = safeCode(Deno.env.get('SB_EXECUTION_ID'), 'edge');
  let adminClient: any = null;
  let claimedPostId = '';
  let userHash = '';
  let postIdForLog = '';

  const baseLog = () => ({
    request_id: requestId,
    execution_id: executionId,
    post_id: postIdForLog || undefined,
    user_hash: userHash || undefined,
    duration_ms: Date.now() - startedAt,
  });
  const finish = async (success: boolean, errorCode?: string) => {
    if (!adminClient || !claimedPostId) return;
    try {
      await adminClient.rpc('clinical_case_finish_qcm_generation', {
        p_post_id: claimedPostId,
        p_success: success,
        p_error_code: errorCode ? safeCode(errorCode, 'generation_failed') : null,
      });
    } catch (_) {
      logEvent('generation_finish_state_failed', baseLog());
    }
  };
  const fail = (
    status: number,
    error: string,
    retryable: boolean,
    extra: Record<string, unknown> = {},
  ) => json(req, { ok: false, error, retryable, ...extra }, status);

  if (req.method === 'OPTIONS') return new Response('ok', { status: 204, headers: corsHeaders(req) });
  if (req.method !== 'POST') return fail(405, 'method_not_allowed', false);

  const origin = req.headers.get('Origin')?.trim() ?? '';
  const configuredOrigins = (Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS') ?? '')
    .split(',').map((x) => x.trim()).filter(Boolean);
  if (origin && configuredOrigins.length > 0 && !configuredOrigins.includes(origin)) {
    logEvent('cors_origin_denied', baseLog());
    return fail(403, 'origin_not_allowed', false);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const openaiKey = Deno.env.get('OPENAI_API_KEY');
    const authorization = req.headers.get('Authorization') ?? '';

    if (!authorization.startsWith('Bearer ')) {
      logEvent('authentication_failed', baseLog());
      return fail(401, 'authentication_required', false);
    }
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      logEvent('server_configuration_missing', {
        ...baseLog(),
        missing_supabase_url: !supabaseUrl,
        missing_anon_key: !anonKey,
        missing_service_role_key: !serviceRoleKey,
      });
      return fail(503, 'server_configuration_unavailable', true);
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerData, error: callerError } = await callerClient.auth.getUser();
    const callerId = callerData.user?.id;
    if (callerError || !callerId) {
      logEvent('authentication_failed', baseLog());
      return fail(401, 'authentication_failed', false);
    }
    userHash = await shortHash(callerId);

    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('id,account_status,role')
      .eq('id', callerId)
      .maybeSingle();
    if (profileError || !profile || profile.account_status !== 'active') {
      logEvent('account_inactive', baseLog());
      return fail(403, 'account_inactive', false);
    }

    const body = await req.json().catch(() => null);
    if (!body || typeof body !== 'object') return fail(400, 'invalid_request', false);
    const practiceCaseId = String((body as any).practice_case_id ?? '').trim();
    const requestedPostId = String((body as any).post_id ?? '').trim();
    const requestedForce = (body as any).force_regenerate === true;
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

    if ((!practiceCaseId && !requestedPostId) || (practiceCaseId && requestedPostId)) {
      return fail(400, 'exactly_one_case_identifier_required', false);
    }
    if (practiceCaseId && !uuidPattern.test(practiceCaseId)) return fail(400, 'invalid_case_id', false);
    if (requestedPostId && !uuidPattern.test(requestedPostId)) return fail(400, 'invalid_post_id', false);

    const postSelect =
      'id,practice_case_id,author_id,published_at,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan,disposition,specialist_service,specialty_classification_source,specialty_classification_confidence';
    let post: any = null;
    let resolvedPracticeCaseId = practiceCaseId;

    if (practiceCaseId) {
      const { data: practiceCase, error: caseError } = await adminClient
        .from('practice_cases')
        .select('id,user_id,is_draft')
        .eq('id', practiceCaseId)
        .maybeSingle();
      if (caseError || !practiceCase || practiceCase.user_id !== callerId) {
        logEvent('case_not_found', baseLog());
        return fail(404, 'case_not_found', false);
      }
      if (practiceCase.is_draft === true) return fail(409, 'case_not_ready', false);
      const { data, error } = await adminClient
        .from('clinical_case_posts')
        .select(postSelect)
        .eq('practice_case_id', practiceCaseId)
        .maybeSingle();
      if (error || !data) return fail(409, 'case_not_ready', false);
      post = data;
    } else {
      const { data, error } = await adminClient
        .from('clinical_case_posts')
        .select(postSelect)
        .eq('id', requestedPostId)
        .maybeSingle();
      if (error || !data || !data.published_at) {
        logEvent('case_not_found', baseLog());
        return fail(404, 'case_not_found', false);
      }
      // clinical_case_feed is available to every active authenticated physician;
      // only published posts are therefore eligible through post_id.
      post = data;
      resolvedPracticeCaseId = String(data.practice_case_id ?? '');
    }

    postIdForLog = String(post.id);
    logEvent('qcm_generation_started', baseLog());

    const { data: existingQcms, error: existingError } = await adminClient
      .from('clinical_case_qcms')
      .select('id,generation_source')
      .eq('post_id', post.id);
    if (existingError) {
      logEvent('database_read_failed', baseLog());
      return fail(503, 'database_unavailable', true);
    }
    if (
      (existingQcms ?? []).length === 5 &&
      (existingQcms ?? []).every((q: any) => q.generation_source === 'openai')
    ) {
      return json(req, {
        ok: true,
        generated: false,
        status: 'ready',
        count: 5,
        post_id: post.id,
        reason: 'already_ready',
      });
    }

    const isAdmin = String(profile.role ?? '').toLowerCase() === 'admin';
    const canForce = requestedForce && (isAdmin || post.author_id === callerId);
    const { data: claimData, error: claimError } = await adminClient.rpc(
      'clinical_case_claim_qcm_generation',
      { p_post_id: post.id, p_user_id: callerId, p_force: canForce },
    );
    if (claimError || !Array.isArray(claimData) || claimData.length === 0) {
      logEvent('generation_guard_unavailable', baseLog());
      return fail(503, 'generation_guard_unavailable', true);
    }
    const claim = claimData[0] ?? {};
    if (claim.claimed !== true) {
      const claimStatus = String(claim.status ?? 'failed');
      const claimErrorCode = safeCode(claim.error_code, 'retry_later');
      const retryAfter = claim.retry_after ?? null;
      const seconds = retrySeconds(retryAfter);
      if (claimStatus === 'ready') {
        return json(req, { ok: true, generated: false, status: 'ready', count: 5, post_id: post.id });
      }
      if (claimStatus === 'running') {
        logEvent('generation_already_running', baseLog());
        return fail(202, 'generation_in_progress', true, {
          post_id: post.id,
          retry_after: retryAfter,
          retry_after_seconds: seconds,
        });
      }
      if (claimErrorCode === 'rate_limit_exceeded') {
        logEvent('rate_limit_exceeded', baseLog());
        return fail(429, 'rate_limit_exceeded', true, {
          retry_after: retryAfter,
          retry_after_seconds: seconds,
        });
      }
      const permanent = ['openai_request_invalid', 'authentication_failed', 'authorization_failed', 'invalid_request']
        .includes(claimErrorCode);
      return fail(permanent ? 502 : 503, claimErrorCode, !permanent, {
        retry_after: retryAfter,
        retry_after_seconds: seconds,
      });
    }
    claimedPostId = post.id;

    if (!openaiKey) {
      logEvent('openai_key_missing', baseLog());
      await finish(false, 'openai_key_missing');
      claimedPostId = '';
      return fail(503, 'openai_unavailable', true, { retry_after_seconds: 60 });
    }

    const safeCase = anonymizedCase(post);
    const safeCaseJson = JSON.stringify(safeCase);
    if (safeCaseJson.length > maxCasePayloadChars) {
      await finish(false, 'payload_too_large');
      claimedPostId = '';
      return fail(400, 'clinical_payload_too_large', false);
    }

    const prompt = `Tu es responsable pédagogique d'un programme de QCM pour externes et internes en médecine.\nDATE DE RÉFÉRENCE : 1 octobre 2026.\n\nLe cas ci-dessous est anonymisé et sert uniquement d'ancrage thématique. N'essaie jamais d'identifier le patient et ne restitue jamais le dossier.\n\nCrée EXACTEMENT 5 QCM autonomes, vrais et utiles, fondés sur des sources médicales institutionnelles/universitaires et des recommandations récentes réellement consultées sur le web. La recherche web est nécessaire ici car chaque QCM doit être sourcé et le cinquième doit refléter une recommandation récente.\n\nAXES DANS CET ORDRE :\n1 cours_fondamental ; 2 diagnostic ; 3 explorations ; 4 prise_en_charge ; 5 recommandations.\n\nRÈGLES :\n- exactement 4 propositions et une seule meilleure réponse ; distracteurs plausibles ;\n- jamais de formulation « dans ce cas », de restitution du dossier, de « toutes/aucune » ;\n- n'invente aucun seuil, score, posologie ou recommandation ;\n- correction factuelle de 3 à 6 phrases ;\n- QCM 1 : au moins une source 'cours' ; QCM 2-4 : au moins une source 'cours' ou 'revue' ; QCM 5 : au moins une 'recommandation' ou un 'consensus' ;\n- 1 à 3 références réellement consultées par QCM, avec URL exacte ; pas de blog, forum, Wikipédia, site commercial ou grand public ;\n- réponds en français.\n\nCAS ANONYMISÉ :\n${safeCaseJson}`;

    const model = String(Deno.env.get('OPENAI_TEXT_MODEL') ?? '').trim() || 'gpt-5.6-sol';
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), requestTimeoutMs);
    let response: Response;

    logEvent('openai_request_started', { ...baseLog(), model });
    try {
      response = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        signal: controller.signal,
        headers: {
          Authorization: `Bearer ${openaiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          store: false,
          tools: [{ type: 'web_search' }],
          tool_choice: 'required',
          include: ['web_search_call.action.sources'],
          input: [{ role: 'user', content: [{ type: 'input_text', text: prompt }] }],
          text: {
            format: {
              type: 'json_schema',
              name: 'clinical_case_course_guideline_qcms',
              strict: true,
              schema: fiveQcmSchema,
            },
          },
        }),
      });
    } catch (error) {
      const timeout = error instanceof DOMException && error.name === 'AbortError';
      const code = timeout ? 'openai_timeout' : 'openai_network_error';
      logEvent('openai_http_error', { ...baseLog(), provider_error: code });
      await finish(false, code);
      claimedPostId = '';
      return fail(503, 'openai_unavailable', true);
    } finally {
      clearTimeout(timer);
    }

    const providerRequestId = safeCode(response.headers.get('x-request-id'), 'unavailable');
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      const providerCode = safeCode(payload?.error?.code, `http_${response.status}`);
      const providerType = safeCode(payload?.error?.type, 'provider_error');
      const providerParam = safeCode(payload?.error?.param, '');
      const schemaProblem = response.status === 400 &&
        `${providerCode}:${providerType}:${providerParam}`.toLowerCase().includes('schema');
      logEvent(schemaProblem ? 'openai_invalid_schema' : 'openai_http_error', {
        ...baseLog(),
        provider_status: response.status,
        provider_code: providerCode,
        provider_type: providerType,
        provider_request_id: providerRequestId,
      });
      const permanent = response.status === 400 || response.status === 401 || response.status === 403;
      const errorCode = schemaProblem ? 'openai_invalid_schema' :
        response.status === 400 ? 'openai_request_invalid' :
        response.status === 429 ? 'openai_rate_limited' :
        response.status >= 500 ? 'openai_provider_unavailable' :
        response.status === 401 || response.status === 403 ? 'openai_provider_auth_error' :
        'openai_provider_error';
      await finish(false, errorCode);
      claimedPostId = '';
      return fail(permanent ? 502 : 503, permanent ? 'openai_request_invalid' : 'openai_unavailable', !permanent);
    }
    if (!payload || typeof payload !== 'object') {
      logEvent('openai_invalid_json', { ...baseLog(), provider_request_id: providerRequestId });
      await finish(false, 'openai_invalid_json');
      claimedPostId = '';
      return fail(502, 'openai_invalid_response', true);
    }

    const webSources = extractWebSources(payload);
    if (webSources.length === 0) {
      logEvent('qcm_validation_failed', { ...baseLog(), reason: 'missing_web_sources' });
      await finish(false, 'missing_web_sources');
      claimedPostId = '';
      return fail(502, 'openai_invalid_response', true);
    }
    const consultedUrls = new Set(webSources.map((source) => canonicalUrl(source.url)));

    let generated: any;
    try {
      const raw = extractResponseText(payload).trim();
      if (!raw) throw new Error('empty_model_output');
      generated = JSON.parse(raw);
    } catch (_) {
      logEvent('openai_invalid_json', { ...baseLog(), provider_request_id: providerRequestId });
      await finish(false, 'openai_invalid_json');
      claimedPostId = '';
      return fail(502, 'openai_invalid_response', true);
    }

    try {
      const rawQcms = Array.isArray(generated?.qcms) ? generated.qcms : [];
      if (rawQcms.length !== 5) throw new Error('invalid_qcm_count');
      const allowedTopics = new Set<string>(topicEnum);
      const allowedAxes = new Set<string>(axisEnum);
      const allowedKinds = new Set<string>(sourceKindEnum);

      const normalized = rawQcms.map((raw: any, index: number) => {
        const options = Array.isArray(raw?.options)
          ? raw.options.map((x: unknown) => scrub(x, 420)).filter(Boolean)
          : [];
        const question = scrub(raw?.question, 1200);
        const correction = scrub(raw?.correction, 5500);
        const correctIndex = Number(raw?.correct_index);
        const topic = String(raw?.topic ?? '').trim();
        const axis = String(raw?.axis ?? '').trim();
        const references = (Array.isArray(raw?.references) ? raw.references : [])
          .map((ref: any) => ({
            title: scrub(ref?.title, 600),
            organization: scrub(ref?.organization, 300),
            year: scrub(ref?.year, 40),
            url: String(ref?.url ?? '').trim(),
            kind: String(ref?.kind ?? '').trim(),
          }))
          .filter((ref: any) =>
            ref.title && ref.organization && ref.year && canonicalUrl(ref.url) &&
            allowedKinds.has(ref.kind) && consultedUrls.has(canonicalUrl(ref.url))
          );

        if (!question || !correction || options.length !== 4 || new Set(options).size !== 4 ||
            !Number.isInteger(correctIndex) || correctIndex < 0 || correctIndex > 3 ||
            !allowedTopics.has(topic) || !allowedAxes.has(axis) || references.length < 1 ||
            genericQuestionPatterns.some((pattern) => pattern.test(question))) {
          throw new Error(`invalid_qcm_${index + 1}`);
        }
        const kinds = new Set(references.map((ref: any) => ref.kind));
        if (index === 0 && !kinds.has('cours')) throw new Error('qcm_1_missing_course_source');
        if (index >= 1 && index <= 3 && ![...kinds].some((kind) => kind === 'cours' || kind === 'revue')) {
          throw new Error(`qcm_${index + 1}_missing_teaching_source`);
        }
        if (index === 4 && ![...kinds].some((kind) => kind === 'recommandation' || kind === 'consensus')) {
          throw new Error('qcm_5_missing_guideline_source');
        }
        return {
          axis,
          position: index + 1,
          question,
          options,
          correct_index: correctIndex,
          correction: formatCorrection(correction, references.slice(0, 3)),
          topic,
        };
      });

      if (normalized.some((qcm: any, index: number) => qcm.axis !== axisEnum[index])) {
        throw new Error('invalid_axis_order');
      }
      const normalizedQuestions = normalized.map((qcm: any) =>
        qcm.question.toLowerCase().replace(/\s+/g, ' ').trim()
      );
      if (new Set(normalizedQuestions).size !== 5) throw new Error('duplicate_questions');

      const persisted = normalized.map(({ axis: _axis, ...qcm }: any) => qcm);
      const { error: commitError } = await adminClient.rpc('clinical_case_commit_generated_qcms', {
        p_post_id: post.id,
        p_qcms: persisted,
      });
      if (commitError) {
        logEvent('database_write_failed', { ...baseLog(), db_code: safeCode(commitError.code, 'rpc_error') });
        await finish(false, 'database_write_failed');
        claimedPostId = '';
        return fail(503, 'database_unavailable', true);
      }
    } catch (error) {
      const reason = safeCode((error as Error)?.message, 'qcm_validation_failed');
      logEvent('qcm_validation_failed', { ...baseLog(), reason });
      await finish(false, reason);
      claimedPostId = '';
      return fail(502, 'openai_invalid_response', true);
    }

    await finish(true);
    claimedPostId = '';
    logEvent('qcm_generation_success', {
      ...baseLog(),
      qcm_count: 5,
      web_source_count: webSources.length,
      provider_request_id: providerRequestId,
    });
    return json(req, {
      ok: true,
      generated: true,
      status: 'ready',
      count: 5,
      post_id: post.id,
      practice_case_id: resolvedPracticeCaseId,
    });
  } catch (error) {
    const code = safeCode((error as Error)?.message, 'generation_failed');
    await finish(false, code);
    claimedPostId = '';
    logEvent('qcm_generation_failed', { ...baseLog(), error_code: code });
    return fail(503, 'generation_unavailable', true);
  }
});
