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

function scrub(value: unknown, max = 5000): string {
  let x = String(value ?? '').trim();
  if (!x) return '';
  x = x.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email masqué]');
  x = x.replace(/\b\d{4}-\d{2}-\d{2}\b/g, '[date masquée]');
  x = x.replace(/\b[0-3]?\d[/-][01]?\d(?:[/-]\d{2,4})?\b/g, '[date masquée]');
  x = x.replace(/\+?\d[\d .()/-]{7,}\d/g, '[numéro masqué]');
  x = x.replace(/\b(nom|prénom|prenom|ipp|cin|dossier)\b\s*[:=-]\s*[^,;\n]{1,100}/gi, '$1 : [masqué]');
  x = x.replace(/\b\d{7,}\b/g, '[identifiant masqué]');
  return x.slice(0, max).trim();
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
    if (!byUrl.has(key)) {
      byUrl.set(key, { title: scrub(title, 500), url: rawUrl });
    }
  };

  for (const item of payload?.output ?? []) {
    if (item?.type === 'web_search_call') {
      for (const source of item?.action?.sources ?? []) {
        add(source?.title, source?.url);
      }
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
  required: [
    'axis',
    'question',
    'options',
    'correct_index',
    'correction',
    'topic',
    'references',
  ],
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
  const lines = references.map((ref) =>
    `${ref.kind}|||${ref.title}|||${ref.organization}|||${ref.year}|||${ref.url}`
  );
  return `${correction}\n\n§SOURCES§\n${lines.join('\n')}`.slice(0, 9000);
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

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
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerData, error: callerError } = await callerClient.auth.getUser();
    const callerId = callerData.user?.id;
    if (callerError || !callerId) return json({ ok: false, error: 'unauthorized' }, 401);

    const { data: profile } = await adminClient
      .from('profiles')
      .select('id,account_status')
      .eq('id', callerId)
      .maybeSingle();
    if (!profile || profile.account_status !== 'active') {
      return json({ ok: false, error: 'inactive_account' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const practiceCaseId = String(body?.practice_case_id ?? '').trim();
    const requestedPostId = String(body?.post_id ?? '').trim();
    if (!practiceCaseId && !requestedPostId) {
      return json({ ok: false, error: 'case_or_post_required' }, 400);
    }

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
        .select('id,practice_case_id,author_id,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan,disposition,specialist_service')
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
        .select('id,practice_case_id,author_id,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan,disposition,specialist_service')
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
      return json({
        ok: true,
        generated: false,
        source: 'openai',
        count: 5,
        post_id: post.id,
        reason: 'already_ready',
      });
    }

    if (!openaiKey) {
      return json({
        ok: true,
        generated: false,
        source: 'fallback',
        count: (existingQcms ?? []).length,
        post_id: post.id,
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

    const prompt = `Tu es responsable pédagogique d'un enseignement d'externat/internat médical.

DATE DE RÉFÉRENCE : 30 septembre 2026.

Tu reçois un cas clinique anonymisé UNIQUEMENT pour identifier le thème médical à enseigner. Tu dois ensuite effectuer une RECHERCHE WEB ACTUELLE et créer EXACTEMENT 5 QCM de cours et de recommandations. Le cas n'est PAS la source des réponses.

OBJECTIF
Transformer le diagnostic/thème suggéré par le cas en une mini-session de cours. Les questions doivent apprendre la pathologie, les critères diagnostiques, les explorations, la prise en charge et les recommandations récentes. Elles ne doivent pas demander de relire ou de restituer ce qui est déjà écrit dans le cas.

RECHERCHE WEB OBLIGATOIRE
- Utilise la recherche web avant de rédiger les QCM.
- Pour les recommandations, identifie la version la plus récente disponible à la date de référence.
- Priorité absolue aux sources de premier niveau : sociétés savantes officielles, autorités sanitaires nationales/internationales, OMS, NICE, HAS, CDC, agences publiques, recommandations/consensus publiés par les collèges et sociétés de spécialité.
- En seconde intention seulement : revue de synthèse évaluée par les pairs, PubMed/NCBI, article de référence ou ressource pédagogique institutionnelle.
- N'utilise pas de blogs, sites commerciaux, forums, Wikipédia ou contenus grand public comme source d'une recommandation.
- Si plusieurs recommandations reconnues divergent, ne les fusionne pas artificiellement : précise l'organisation et l'année dans la question ou la correction.
- Pour chaque QCM, cite 1 à 3 sources réellement consultées. L'URL retournée doit être l'URL exacte d'une source visitée pendant la recherche.

LES 5 AXES SONT OBLIGATOIRES, UN SEUL PAR QCM, DANS CET ORDRE
1. cours_fondamental : physiopathologie, définition, classification ou notion fondamentale utile ;
2. diagnostic : critères diagnostiques, diagnostic différentiel, score ou signe clé ;
3. explorations : indications/interprétation de biologie, imagerie ou autre examen ;
4. prise_en_charge : traitement, surveillance, complication ou stratégie pratique ;
5. recommandations : point important d'une recommandation récente, changement de pratique ou conduite actuellement recommandée.

RÈGLE CENTRALE
Le cas clinique sert seulement d'ANCRAGE THÉMATIQUE. Ne pose pas « quel est le diagnostic de ce patient ? », « quelle est sa conclusion d'imagerie ? », « quelle conduite a été faite ? » ou toute question dont la réponse se trouve telle quelle dans le dossier. Une question peut utiliser une courte vignette générique si cela améliore le raisonnement, mais elle ne doit pas inventer de nouvelles données présentées comme appartenant au patient fourni.

QUALITÉ DES QCM
- Niveau externat/internat, utile en garde et pour la formation continue.
- Exactement 4 propositions, une seule meilleure réponse.
- Trois distracteurs plausibles, de même niveau conceptuel.
- Pas de « toutes les réponses », « aucune des réponses », distracteurs absurdes ou indices de longueur.
- Privilégie les points discriminants et réellement enseignables plutôt que les détails anecdotiques.
- Évite les posologies ultra-spécifiques si elles varient selon protocole local ; si une posologie fait partie d'une recommandation internationale stable et essentielle, nomme la source.
- Ne présente jamais une recommandation ancienne comme « actuelle » lorsqu'une version plus récente existe.

EXPLICATION PÉDAGOGIQUE OBLIGATOIRE
- 3 à 6 phrases concises par QCM.
- Explique le principe du cours et pourquoi la bonne réponse est la meilleure.
- Explique brièvement les principaux distracteurs lorsque c'est utile.
- Lorsque la question dépend d'une recommandation, cite explicitement l'organisation et l'année dans le texte de la correction.
- Ne dis pas « vous avez raison/tort » : l'explication doit être valable quelle que soit la réponse choisie.

CONFIDENTIALITÉ
- Aucun identifiant patient.
- Les faits propres au patient ne peuvent venir que du cas fourni et ne doivent pas être extrapolés.
- Réponds en français.

CAS ANONYMISÉ — ANCRAGE THÉMATIQUE UNIQUEMENT :
${JSON.stringify(safeCase)}`;

    const model =
      Deno.env.get('OPENAI_TEXT_MODEL') ||
      Deno.env.get('OPENAI_VISION_MODEL') ||
      'gpt-5.6';
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
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

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error('OpenAI guideline QCM failed', response.status, payload);
      return json({
        ok: true,
        generated: false,
        source: 'fallback',
        post_id: post.id,
        reason: 'openai_failed',
      });
    }

    const webSources = extractWebSources(payload);
    if (webSources.length === 0) {
      console.error('OpenAI guideline QCM returned no verifiable web source');
      return json({
        ok: true,
        generated: false,
        source: 'fallback',
        post_id: post.id,
        reason: 'missing_web_sources',
      });
    }
    const consultedUrls = new Set(webSources.map((source) => canonicalUrl(source.url)));

    const generated = parseJsonLoose(extractResponseText(payload));
    const rawQcms = Array.isArray(generated?.qcms) ? generated.qcms : [];
    if (rawQcms.length !== 5) {
      return json({
        ok: true,
        generated: false,
        source: 'fallback',
        post_id: post.id,
        reason: 'invalid_qcm_count',
      });
    }

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
      const rawReferences = Array.isArray(raw?.references) ? raw.references : [];
      const references = rawReferences
        .map((ref: any) => ({
          title: scrub(ref?.title, 600),
          organization: scrub(ref?.organization, 300),
          year: scrub(ref?.year, 40),
          url: String(ref?.url ?? '').trim(),
          kind: String(ref?.kind ?? '').trim(),
        }))
        .filter((ref: any) =>
          ref.title &&
          ref.organization &&
          ref.year &&
          ref.url.startsWith('http') &&
          allowedKinds.has(ref.kind) &&
          consultedUrls.has(canonicalUrl(ref.url))
        );

      if (
        !question ||
        !rawCorrection ||
        options.length !== 4 ||
        new Set(options).size !== 4 ||
        !Number.isInteger(correctIndex) ||
        correctIndex < 0 ||
        correctIndex > 3 ||
        !allowedTopics.has(topic) ||
        !allowedAxes.has(axis) ||
        references.length < 1
      ) {
        throw new Error(`invalid_qcm_${index + 1}`);
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

    const actualAxes = normalized.map((q: any) => q.axis);
    if (actualAxes.some((axis: string, index: number) => axis !== axisEnum[index])) {
      return json({
        ok: true,
        generated: false,
        source: 'fallback',
        post_id: post.id,
        reason: 'invalid_axis_order',
      });
    }
    if (new Set(normalized.map((q: any) => q.question.toLowerCase())).size !== 5) {
      return json({
        ok: true,
        generated: false,
        source: 'fallback',
        post_id: post.id,
        reason: 'duplicate_questions',
      });
    }

    const persisted = normalized.map(({ axis: _axis, ...qcm }: any) => qcm);

    // Compatibilité descendante : le QCM n°1 reste disponible dans les champs
    // historiques du post. Le trigger resynchronise les fallbacks avant les cinq
    // upserts finaux et invalide les réponses à l'ancien jeu de questions.
    const first = persisted[0];
    const { error: legacyUpdateError } = await adminClient
      .from('clinical_case_posts')
      .update({
        qcm_question: first.question,
        qcm_options: first.options,
        correct_index: first.correct_index,
        correction: first.correction,
        question_topic: first.topic,
        generation_source: 'openai',
        updated_at: new Date().toISOString(),
      })
      .eq('id', post.id);
    if (legacyUpdateError) throw legacyUpdateError;

    const { error: qcmUpsertError } = await adminClient
      .from('clinical_case_qcms')
      .upsert(persisted, { onConflict: 'post_id,position' });
    if (qcmUpsertError) throw qcmUpsertError;

    return json({
      ok: true,
      generated: true,
      source: 'openai',
      source_mode: 'live_web_guidelines',
      count: 5,
      web_sources: webSources.length,
      post_id: post.id,
      practice_case_id: resolvedPracticeCaseId,
    });
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: 'generation_failed' }, 500);
  }
});
