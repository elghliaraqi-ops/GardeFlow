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

const specialtyEnum = [
  'Cardiologie',
  'Pneumologie',
  'Gastro-entérologie',
  'Chirurgie Viscérale',
  'Urologie',
  'Néphrologie',
  'Neurologie',
  'Neurochirurgie',
  'Traumatologie / Orthopédie',
  'Rhumatologie',
  'Gynécologie',
  'Pédiatrie',
  'ORL',
  'Ophtalmologie',
  'Dermatologie',
  'Endocrinologie - Diabétologie',
  'Hématologie',
  'Oncologie',
  'Infectiologie',
  'Réanimation',
  'Anesthésie',
  'Psychiatrie',
  'Imagerie Médicale',
  'Urgences',
  'Médecine interne',
  'Autres cas cliniques',
];

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
  required: ['specialty', 'specialty_confidence', 'qcms'],
  properties: {
    specialty: { type: 'string', enum: specialtyEnum },
    specialty_confidence: { type: 'number', minimum: 0, maximum: 1 },
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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'method_not_allowed' }, 405);
  }

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
    if (callerError || !callerId) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

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
    const forceRegenerate = body?.force_regenerate === true;

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
      if (error || !data) {
        return json({ ok: false, error: 'post_not_ready' }, 409);
      }
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
      if (error || !data) {
        return json({ ok: false, error: 'post_not_found' }, 404);
      }
      post = data;
      resolvedPracticeCaseId = String(data.practice_case_id ?? '');
    }

    const { data: existingQcms } = await adminClient
      .from('clinical_case_qcms')
      .select('id,generation_source')
      .eq('post_id', post.id);

    if (
      !forceRegenerate &&
      (existingQcms ?? []).length === 5 &&
      (existingQcms ?? []).every((q: any) => q.generation_source === 'openai')
    ) {
      return json({
        ok: true,
        generated: false,
        source: 'openai',
        count: 5,
        post_id: post.id,
        specialty: post.specialist_service,
        specialty_source: post.specialty_classification_source,
        reason: 'already_ready',
      });
    }

    if (!openaiKey) {
      return json({
        ok: false,
        generated: false,
        source: 'none',
        count: (existingQcms ?? []).length,
        post_id: post.id,
        reason: 'openai_key_missing',
      }, 503);
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

    const specialtiesForPrompt = specialtyEnum.map((value) => `- ${value}`).join('\n');

    const prompt = `Tu es responsable pédagogique d'un programme de QCM pour externes et internes en médecine.
DATE DE RÉFÉRENCE : 1 octobre 2026.

Tu reçois un cas clinique anonymisé. Tu as DEUX tâches obligatoires :
1) classer ce cas dans UNE spécialité médicale/chirurgicale ;
2) utiliser le cas uniquement comme ancrage thématique pour créer EXACTEMENT 5 QCM de cours et de recommandations.

CLASSEMENT DE LA SPÉCIALITÉ — OBLIGATOIRE
Analyse l'ENSEMBLE du cas : motif, symptômes, antécédents, examen clinique, biologie, imagerie, synthèse diagnostique, traitement/conduite à tenir et orientation. Ne te limite jamais au titre ni à un mot-clé isolé.

Choisis EXACTEMENT une catégorie parmi :
${specialtiesForPrompt}

Règles de classement :
- Cherche activement la spécialité principale la plus pertinente. « Autres cas cliniques » est STRICTEMENT un dernier recours.
- Ne choisis jamais « Autres cas cliniques » simplement parce que specialist_service est vide ou imprécis.
- En cas d'ambiguïté, compare les 2 ou 3 spécialités plausibles à partir de tout le contexte clinique et retiens la plus cohérente.
- « Urgences » n'est PAS un fourre-tout ni le lieu de prise en charge. Une colique néphrétique vue aux urgences = Urologie ; un AVC = Neurologie ; une appendicite = Chirurgie Viscérale. Réserve « Urgences » aux situations réellement transversales de médecine d'urgence/polytraumatisme quand aucune spécialité d'organe ne domine.
- Distingue Urologie et Néphrologie : lithiase/colique néphrétique/obstruction urétérale/rétention/prostate = Urologie ; atteinte glomérulaire, insuffisance rénale médicale, syndrome néphrotique/néphritique, dialyse ou trouble hydro-électrolytique primitif = Néphrologie.
- Si specialist_service contient déjà une spécialité, considère-la comme un indice seulement ; le contenu clinique reste la référence sémantique.
- Retourne specialty_confidence entre 0 et 1. Une confiance basse ne justifie pas à elle seule « Autres » si une spécialité reste raisonnablement identifiable.

SOURCE PÉDAGOGIQUE OBLIGATOIRE POUR LES QCM
- Fais une recherche web AVANT toute question.
- Cherche prioritairement un cours médical institutionnel ou universitaire, NCBI Bookshelf/StatPearls, collège de spécialité, référentiel d'enseignement, société savante ou autorité sanitaire.
- Pour les recommandations, utilise la version officielle la plus récente disponible à la date de référence.
- Aucun blog, forum, Wikipédia, site commercial ou contenu grand public.
- Chaque QCM doit avoir 1 à 3 références réellement consultées avec URL exacte.
- Le QCM 1 doit obligatoirement citer au moins une source de type 'cours'.
- Les QCM 2 à 4 doivent être fondés sur une source pédagogique ('cours' ou 'revue') et peuvent être complétés par une recommandation/consensus.
- Le QCM 5 doit citer au moins une 'recommandation' ou un 'consensus' récent.

INTERDIT
- Ne pose jamais une question de restitution du dossier : formulations du type « dans ce cas », « documenté », « quelle synthèse a été retenue », « quelle conduite a été faite », « quelle orientation a été choisie ».
- Le texte du cas n'est jamais une preuve scientifique et ne doit jamais être la source de la bonne réponse.
- N'invente aucun fait clinique, seuil, score, posologie ou recommandation. Si un point ne peut pas être sourcé, choisis un autre point de cours.

5 AXES, DANS CET ORDRE
1 cours_fondamental : physiopathologie, définition, classification ou notion fondamentale ;
2 diagnostic : critères, signes discriminants, diagnostic différentiel ou score ;
3 explorations : biologie, imagerie, ECG ou examen utile et son interprétation ;
4 prise_en_charge : stratégie thérapeutique, surveillance ou complication ;
5 recommandations : recommandation récente ou changement de pratique.

QUALITÉ
- Niveau externat/internat, intéressant en garde et en formation continue.
- 4 propositions exactement, une seule meilleure réponse, 3 distracteurs plausibles et homogènes.
- Pas de « toutes/aucune », pas de distracteur absurde, pas d'indice de longueur.
- Questions autonomes : elles doivent rester vraies même si on retire le cas clinique initial.
- Correction en 3 à 6 phrases, factuelle, expliquant le raisonnement et, si pertinent, pourquoi les distracteurs sont faux.
- Mentionne l'organisation et l'année quand la réponse dépend d'une recommandation.
- Réponds en français.

CAS ANONYMISÉ — CLASSIFICATION + ANCRAGE THÉMATIQUE :
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
            name: 'clinical_case_specialty_and_course_grounded_qcms',
            strict: true,
            schema: fiveQcmSchema,
          },
        },
      }),
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error('OpenAI course QCM failed', response.status, payload);
      return json({
        ok: false,
        generated: false,
        source: 'none',
        post_id: post.id,
        reason: 'openai_failed',
      }, 503);
    }

    const webSources = extractWebSources(payload);
    if (webSources.length === 0) {
      return json({
        ok: false,
        generated: false,
        source: 'none',
        post_id: post.id,
        reason: 'missing_web_sources',
      }, 422);
    }
    const consultedUrls = new Set(webSources.map((source) => canonicalUrl(source.url)));

    const generated = parseJsonLoose(extractResponseText(payload));
    const specialty = String(generated?.specialty ?? '').trim();
    const specialtyConfidence = Number(generated?.specialty_confidence);
    if (
      !specialtyEnum.includes(specialty) ||
      !Number.isFinite(specialtyConfidence) ||
      specialtyConfidence < 0 ||
      specialtyConfidence > 1
    ) {
      return json({
        ok: false,
        generated: false,
        source: 'none',
        post_id: post.id,
        reason: 'invalid_specialty_classification',
      }, 422);
    }

    const rawQcms = Array.isArray(generated?.qcms) ? generated.qcms : [];
    if (rawQcms.length !== 5) {
      return json({
        ok: false,
        generated: false,
        source: 'none',
        post_id: post.id,
        reason: 'invalid_qcm_count',
      }, 422);
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
      const references = (Array.isArray(raw?.references) ? raw.references : [])
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
        references.length < 1 ||
        genericQuestionPatterns.some((pattern) => pattern.test(question))
      ) {
        throw new Error(`invalid_qcm_${index + 1}`);
      }

      const kinds = new Set(references.map((ref: any) => ref.kind));
      if (index === 0 && !kinds.has('cours')) {
        throw new Error('qcm_1_missing_course_source');
      }
      if (
        index >= 1 &&
        index <= 3 &&
        ![...kinds].some((kind: any) => kind === 'cours' || kind === 'revue')
      ) {
        throw new Error(`qcm_${index + 1}_missing_teaching_source`);
      }
      if (
        index === 4 &&
        ![...kinds].some(
          (kind: any) => kind === 'recommandation' || kind === 'consensus',
        )
      ) {
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
      return json({
        ok: false,
        generated: false,
        source: 'none',
        post_id: post.id,
        reason: 'invalid_axis_order',
      }, 422);
    }

    if (new Set(normalized.map((qcm: any) => qcm.question.toLowerCase())).size !== 5) {
      return json({
        ok: false,
        generated: false,
        source: 'none',
        post_id: post.id,
        reason: 'duplicate_questions',
      }, 422);
    }

    const persisted = normalized.map(({ axis: _axis, ...qcm }: any) => qcm);
    const first = persisted[0];
    const now = new Date().toISOString();

    const preserveDeclaredSpecialty =
      String(post.specialty_classification_source ?? '').trim() === 'declared' &&
      String(post.specialist_service ?? '').trim() !== '' &&
      !['Urgences', 'Autres cas cliniques'].includes(
        String(post.specialist_service ?? '').trim(),
      );

    const postUpdate: Record<string, unknown> = {
      qcm_question: first.question,
      qcm_options: first.options,
      correct_index: first.correct_index,
      correction: first.correction,
      question_topic: first.topic,
      generation_source: 'openai',
      updated_at: now,
    };

    if (!preserveDeclaredSpecialty) {
      postUpdate.specialist_service = specialty;
      postUpdate.specialty_classification_confidence = specialtyConfidence;
      postUpdate.specialty_classification_source = 'ai';
      postUpdate.specialty_classified_at = now;
    }

    const { error: legacyUpdateError } = await adminClient
      .from('clinical_case_posts')
      .update(postUpdate)
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
      source_mode: 'course_grounded_live_web',
      count: 5,
      web_sources: webSources.length,
      post_id: post.id,
      practice_case_id: resolvedPracticeCaseId,
      specialty: preserveDeclaredSpecialty ? post.specialist_service : specialty,
      specialty_confidence: preserveDeclaredSpecialty
        ? post.specialty_classification_confidence
        : specialtyConfidence,
      specialty_source: preserveDeclaredSpecialty ? 'declared' : 'ai',
    });
  } catch (error) {
    console.error(error);
    return json(
      {
        ok: false,
        error: 'generation_failed',
        detail: String((error as Error)?.message ?? error),
      },
      500,
    );
  }
});
