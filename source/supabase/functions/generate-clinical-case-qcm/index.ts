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

function scrub(value: unknown, max = 5000): string {
  let x = String(value ?? '').trim();
  if (!x) return '';
  x = x.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email masqué]');
  x = x.replace(/\b\d{4}-\d{2}-\d{2}\b/g, '[date masquée]');
  x = x.replace(/\b[0-3]?\d[/-][01]?\d(?:[/-]\d{2,4})?\b/g, '[date masquée]');
  x = x.replace(/\+?\d[\d .()/-]{7,}\d/g, '[numéro masqué]');
  x = x.replace(
    /\b(nom|prénom|prenom|ipp|cin|dossier)\b\s*[:=-]\s*[^,;\n]{1,100}/gi,
    '$1 : [masqué]',
  );
  x = x.replace(/\b\d{7,}\b/g, '[identifiant masqué]');
  return x.slice(0, max).trim();
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
  } catch (_) {}
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced) return JSON.parse(fenced[1]);
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start >= 0 && end > start) return JSON.parse(text.slice(start, end + 1));
  throw new Error('invalid_model_json');
}

function canonicalUrl(value: unknown): string {
  try {
    const url = new URL(String(value ?? '').trim());
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
    if (!key || !rawUrl.startsWith('http')) return;
    if (!byUrl.has(key)) byUrl.set(key, { title: scrub(title, 500), url: rawUrl });
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

const topicEnum = [
  'motif',
  'symptome',
  'examen',
  'imagerie',
  'synthese',
  'prise_en_charge',
  'orientation',
  'avis_specialise',
];

const axisEnum = [
  'cours_fondamental',
  'diagnostic',
  'explorations',
  'prise_en_charge',
  'recommandations',
];

const sourceKindEnum = ['recommandation', 'consensus', 'revue', 'cours'];

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

const referenceSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'organization', 'year', 'url', 'kind'],
  properties: {
    title: { type: 'string' },
    organization: { type: 'string' },
    year: { type: 'string' },
    url: { type: 'string' },
    kind: { type: 'string', enum: sourceKindEnum },
  },
};

const qcmItemSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['axis', 'question', 'options', 'correct_index', 'correction', 'topic', 'references'],
  properties: {
    axis: { type: 'string', enum: axisEnum },
    question: { type: 'string' },
    options: {
      type: 'array',
      minItems: 4,
      maxItems: 4,
      items: { type: 'string' },
    },
    correct_index: { type: 'integer', minimum: 0, maximum: 3 },
    correction: { type: 'string' },
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
    qcms: {
      type: 'array',
      minItems: 5,
      maxItems: 5,
      items: qcmItemSchema,
    },
  },
};

function formatCorrection(
  correction: string,
  references: Array<{
    title: string;
    organization: string;
    year: string;
    url: string;
    kind: string;
  }>,
): string {
  const lines = references.map(
    (ref) => `${ref.kind}|||${ref.title}|||${ref.organization}|||${ref.year}|||${ref.url}`,
  );
  return `${correction}\n\n§SOURCES§\n${lines.join('\n')}`.slice(0, 9000);
}

function safeProviderCode(status: number): string {
  if (status === 400) return 'provider_request_invalid';
  if (status === 401 || status === 403) return 'provider_auth_error';
  if (status === 408) return 'provider_timeout';
  if (status === 429) return 'provider_rate_limited';
  if (status >= 500) return 'provider_unavailable';
  return 'provider_error';
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  let adminClient: any = null;
  let claimedPostId = '';

  const finish = async (success: boolean, errorCode?: string) => {
    if (!adminClient || !claimedPostId) return;
    try {
      await adminClient.rpc('clinical_case_finish_qcm_generation', {
        p_post_id: claimedPostId,
        p_success: success,
        p_error_code: errorCode ?? null,
      });
    } catch (_) {
      // Ne jamais exposer ni relancer une erreur de télémétrie/état.
    }
  };

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const openaiKey = Deno.env.get('OPENAI_API_KEY');
    const authorization = req.headers.get('Authorization') ?? '';

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization.startsWith('Bearer ')) {
      return json({ ok: false, error: 'unauthorized' }, 401);
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
    if (callerError || !callerId) return json({ ok: false, error: 'unauthorized' }, 401);

    const { data: profile } = await adminClient
      .from('profiles')
      .select('id,account_status,role')
      .eq('id', callerId)
      .maybeSingle();
    if (!profile || profile.account_status !== 'active') {
      return json({ ok: false, error: 'inactive_account' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const practiceCaseId = String(body?.practice_case_id ?? '').trim();
    const requestedPostId = String(body?.post_id ?? '').trim();
    const requestedForce = body?.force_regenerate === true;

    if (!practiceCaseId && !requestedPostId) {
      return json({ ok: false, error: 'case_or_post_required' }, 400);
    }

    const postSelect =
      'id,practice_case_id,author_id,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan,disposition,specialist_service,specialty_classification_source,specialty_classification_confidence';

    let post: any = null;
    let resolvedPracticeCaseId = practiceCaseId;

    if (practiceCaseId) {
      if (!/^[0-9a-f-]{36}$/i.test(practiceCaseId)) {
        return json({ ok: false, error: 'invalid_case_id' }, 400);
      }
      const { data: practiceCase, error: caseError } = await adminClient
        .from('practice_cases')
        .select('id,user_id,is_draft')
        .eq('id', practiceCaseId)
        .maybeSingle();
      if (caseError || !practiceCase || practiceCase.user_id !== callerId) {
        return json({ ok: false, error: 'case_not_found' }, 404);
      }
      if (practiceCase.is_draft === true) {
        return json({ ok: false, error: 'draft_case' }, 409);
      }
      const { data, error } = await adminClient
        .from('clinical_case_posts')
        .select(postSelect)
        .eq('practice_case_id', practiceCaseId)
        .maybeSingle();
      if (error || !data) return json({ ok: false, error: 'post_not_ready' }, 409);
      post = data;
    } else {
      if (!/^[0-9a-f-]{36}$/i.test(requestedPostId)) {
        return json({ ok: false, error: 'invalid_post_id' }, 400);
      }
      const { data, error } = await adminClient
        .from('clinical_case_posts')
        .select(postSelect)
        .eq('id', requestedPostId)
        .maybeSingle();
      if (error || !data) return json({ ok: false, error: 'post_not_found' }, 404);
      post = data;
      resolvedPracticeCaseId = String(data.practice_case_id ?? '');
    }

    const { data: existingQcms } = await adminClient
      .from('clinical_case_qcms')
      .select('id,generation_source')
      .eq('post_id', post.id);

    if (
      (existingQcms ?? []).length === 5 &&
      (existingQcms ?? []).every((q: any) => q.generation_source === 'openai')
    ) {
      claimedPostId = post.id;
      await finish(true);
      claimedPostId = '';
      return json({
        ok: true,
        generated: false,
        status: 'ready',
        source: 'openai',
        count: 5,
        post_id: post.id,
        specialty: post.specialist_service,
        reason: 'already_ready',
      });
    }

    const isAdmin = String(profile.role ?? '').toLowerCase() === 'admin';
    const canForce = requestedForce && (isAdmin || post.author_id === callerId);

    const { data: claimData, error: claimError } = await adminClient.rpc(
      'clinical_case_claim_qcm_generation',
      { p_post_id: post.id, p_force: canForce },
    );
    if (claimError || !Array.isArray(claimData) || claimData.length === 0) {
      return json({ ok: false, status: 'failed', reason: 'generation_guard_unavailable' }, 503);
    }

    const claim = claimData[0] ?? {};
    if (claim.claimed !== true) {
      const status = String(claim.status ?? 'failed');
      return json({
        ok: status === 'ready' || status === 'running',
        generated: false,
        status,
        source: status === 'ready' ? 'openai' : 'none',
        count: status === 'ready' ? 5 : (existingQcms ?? []).length,
        post_id: post.id,
        retry_after: claim.retry_after ?? null,
        reason: status === 'running' ? 'already_running' : status === 'ready' ? 'already_ready' : 'retry_later',
      }, status === 'missing' ? 404 : 202);
    }
    claimedPostId = post.id;

    if (!openaiKey) {
      await finish(false, 'openai_key_missing');
      claimedPostId = '';
      return json({
        ok: false,
        generated: false,
        status: 'failed',
        source: 'none',
        count: (existingQcms ?? []).length,
        post_id: post.id,
        reason: 'configuration_missing',
      });
    }

    const safeCase = {
      age_band: scrub(post.age_band, 80),
      sex: scrub(post.sex, 40),
      presentation: scrub(post.presentation),
      history: scrub(post.history),
      clinical_exam: scrub(post.clinical_exam),
      complementary_exams: scrub(post.complementary_exams),
      imaging_conclusion: scrub(post.imaging_conclusion),
      assessment: scrub(post.assessment),
      plan: scrub(post.plan),
      disposition: scrub(post.disposition, 500),
      specialist_service: scrub(post.specialist_service, 300),
    };

    const prompt = `Tu es responsable pédagogique d'un programme de QCM pour externes et internes en médecine.
DATE DE RÉFÉRENCE : 1 octobre 2026.

Le cas ci-dessous est anonymisé. Il sert UNIQUEMENT d'ancrage thématique. La spécialité déjà classée côté serveur est un indice ; ne demande jamais de restituer le dossier.

OBJECTIF
Crée EXACTEMENT 5 QCM autonomes, vrais, utiles en garde et en formation continue, fondés sur des cours médicaux institutionnels et des recommandations récentes réellement consultés sur le web.

SOURCE PÉDAGOGIQUE OBLIGATOIRE
- Fais une recherche web AVANT toute question.
- Priorité : cours universitaire/institutionnel, collège de spécialité, NCBI Bookshelf/StatPearls, société savante, HAS, NICE, OMS, CDC ou autre autorité sanitaire reconnue.
- Pour les recommandations, utilise la version officielle la plus récente disponible à la date de référence.
- Aucun blog, forum, Wikipédia, site commercial ou contenu grand public.
- Chaque QCM doit avoir 1 à 3 références réellement consultées avec URL exacte.
- QCM 1 : au moins une source de type 'cours'.
- QCM 2 à 4 : au moins une source pédagogique ('cours' ou 'revue').
- QCM 5 : au moins une 'recommandation' ou un 'consensus' récent.

INTERDIT
- Pas de formulation « dans ce cas », « documenté », « quelle synthèse a été retenue », « quelle conduite a été faite », « quelle orientation a été choisie ».
- Le dossier du patient n'est jamais une preuve scientifique.
- N'invente aucun seuil, score, posologie ou recommandation. Si un point ne peut pas être sourcé, choisis un autre point.

5 AXES, DANS CET ORDRE
1 cours_fondamental : physiopathologie, définition, classification ou notion fondamentale ;
2 diagnostic : critères, signes discriminants, diagnostic différentiel ou score ;
3 explorations : biologie, imagerie, ECG ou examen utile et son interprétation ;
4 prise_en_charge : stratégie thérapeutique, surveillance ou complication ;
5 recommandations : recommandation récente ou changement de pratique.

QUALITÉ
- 4 propositions exactement, une seule meilleure réponse, 3 distracteurs plausibles et homogènes.
- Pas de « toutes/aucune », pas de distracteur absurde, pas d'indice de longueur.
- Questions autonomes : elles doivent rester vraies sans le cas initial.
- Correction en 3 à 6 phrases, factuelle, avec raisonnement et explication des distracteurs si pertinent.
- Mentionne l'organisation et l'année quand la réponse dépend d'une recommandation.
- Réponds en français.

CAS ANONYMISÉ — ANCRAGE THÉMATIQUE :
${JSON.stringify(safeCase)}`;

    const requestedModel = String(Deno.env.get('OPENAI_TEXT_MODEL') ?? '').trim();
    const allowedModels = new Set(['gpt-6-sol', 'gpt-6-luna', 'gpt-6-astra']);
    const model = allowedModels.has(requestedModel) ? requestedModel : 'gpt-6-sol';

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 75000);
    let response: Response;
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
      clearTimeout(timeout);
      const code = error instanceof DOMException && error.name === 'AbortError'
        ? 'provider_timeout'
        : 'provider_network_error';
      await finish(false, code);
      claimedPostId = '';
      return json({ ok: false, generated: false, status: 'failed', source: 'none', post_id: post.id, reason: code });
    } finally {
      clearTimeout(timeout);
    }

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const code = safeProviderCode(response.status);
      console.error('QCM provider request failed', response.status, code);
      await finish(false, code);
      claimedPostId = '';
      return json({
        ok: false,
        generated: false,
        status: 'failed',
        source: 'none',
        post_id: post.id,
        reason: code,
      });
    }

    const webSources = extractWebSources(payload);
    if (webSources.length === 0) {
      await finish(false, 'missing_web_sources');
      claimedPostId = '';
      return json({ ok: false, generated: false, status: 'failed', source: 'none', post_id: post.id, reason: 'missing_web_sources' });
    }
    const consultedUrls = new Set(webSources.map((source) => canonicalUrl(source.url)));

    const generated = parseJsonLoose(extractResponseText(payload));
    const rawQcms = Array.isArray(generated?.qcms) ? generated.qcms : [];
    if (rawQcms.length !== 5) throw new Error('invalid_qcm_count');

    const allowedTopics = new Set(topicEnum);
    const allowedAxes = new Set(axisEnum);
    const allowedKinds = new Set(sourceKindEnum);

    const normalized = rawQcms.map((raw: any, index: number) => {
      const options = Array.isArray(raw?.options)
        ? raw.options.map((x: unknown) => scrub(x, 420)).filter(Boolean)
        : [];
      const correctIndex = Number(raw?.correct_index);
      const question = scrub(raw?.question, 1200);
      const rawCorrection = scrub(raw?.correction, 5500);
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
          ref.title && ref.organization && ref.year && ref.url.startsWith('http') &&
          allowedKinds.has(ref.kind) && consultedUrls.has(canonicalUrl(ref.url))
        );

      if (
        !question || !rawCorrection || options.length !== 4 || new Set(options).size !== 4 ||
        !Number.isInteger(correctIndex) || correctIndex < 0 || correctIndex > 3 ||
        !allowedTopics.has(topic) || !allowedAxes.has(axis) || references.length < 1 ||
        genericQuestionPatterns.some((pattern) => pattern.test(question))
      ) {
        throw new Error(`invalid_qcm_${index + 1}`);
      }

      const kinds = new Set(references.map((ref: any) => ref.kind));
      if (index === 0 && !kinds.has('cours')) throw new Error('qcm_1_missing_course_source');
      if (index >= 1 && index <= 3 && ![...kinds].some((kind: any) => kind === 'cours' || kind === 'revue')) {
        throw new Error(`qcm_${index + 1}_missing_teaching_source`);
      }
      if (index === 4 && ![...kinds].some((kind: any) => kind === 'recommandation' || kind === 'consensus')) {
        throw new Error('qcm_5_missing_guideline_source');
      }

      return {
        axis,
        post_id: post.id,
        position: index + 1,
        question,
        options,
        correct_index: correctIndex,
        correction: formatCorrection(rawCorrection, references.slice(0, 3)),
        topic,
        generation_source: 'openai',
        updated_at: new Date().toISOString(),
      };
    });

    if (normalized.some((qcm: any, index: number) => qcm.axis !== axisEnum[index])) {
      throw new Error('invalid_axis_order');
    }
    if (new Set(normalized.map((qcm: any) => qcm.question.toLowerCase())).size !== 5) {
      throw new Error('duplicate_questions');
    }

    const persisted = normalized.map(({ axis: _axis, ...qcm }: any) => qcm);
    const first = persisted[0];
    const now = new Date().toISOString();

    const { error: qcmUpsertError } = await adminClient
      .from('clinical_case_qcms')
      .upsert(persisted, { onConflict: 'post_id,position' });
    if (qcmUpsertError) throw new Error('qcm_persist_failed');

    const { error: legacyUpdateError } = await adminClient
      .from('clinical_case_posts')
      .update({
        qcm_question: first.question,
        qcm_options: first.options,
        correct_index: first.correct_index,
        correction: first.correction,
        question_topic: first.topic,
        generation_source: 'openai',
        updated_at: now,
      })
      .eq('id', post.id);
    if (legacyUpdateError) throw new Error('legacy_qcm_sync_failed');

    await finish(true);
    claimedPostId = '';

    return json({
      ok: true,
      generated: true,
      status: 'ready',
      source: 'openai',
      source_mode: 'course_grounded_live_web',
      count: 5,
      web_sources: webSources.length,
      post_id: post.id,
      practice_case_id: resolvedPracticeCaseId,
      specialty: post.specialist_service,
      specialty_source: post.specialty_classification_source,
      model,
    });
  } catch (error) {
    const raw = String((error as Error)?.message ?? error);
    const allowedCode = /^[a-zA-Z0-9_:-]{1,80}$/.test(raw) ? raw : 'generation_failed';
    await finish(false, allowedCode);
    claimedPostId = '';
    console.error('QCM generation failed', allowedCode);
    return json({ ok: false, generated: false, status: 'failed', source: 'none', reason: allowedCode });
  }
});
