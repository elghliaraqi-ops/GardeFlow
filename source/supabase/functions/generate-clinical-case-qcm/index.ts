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
  try { return JSON.parse(text); } catch (_) {}
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

const qcmItemSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['question', 'options', 'correct_index', 'correction', 'topic'],
  properties: {
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
    if ((existingQcms ?? []).length === 5 && (existingQcms ?? []).every((q: any) => q.generation_source === 'openai')) {
      return json({ ok: true, generated: false, source: 'openai', count: 5, post_id: post.id, reason: 'already_ready' });
    }

    if (!openaiKey) {
      return json({ ok: true, generated: false, source: 'fallback', count: (existingQcms ?? []).length, post_id: post.id });
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

    const prompt = `Tu crées EXACTEMENT 5 QCM pédagogiques DISTINCTS de raisonnement clinique à partir d'un cas déjà anonymisé, pour un niveau externat/internat médical.

OBJECTIF GÉNÉRAL
Les cinq questions doivent transformer ce cas en mini-session d'apprentissage. Elles ne doivent jamais être cinq reformulations de la même question ni demander de recopier une phrase affichée dans le dossier.

DIVERSITÉ OBLIGATOIRE
- Produis 5 angles différents et complémentaires.
- Quand les données le permettent, couvre en priorité :
  1) raisonnement diagnostique ou diagnostic différentiel ;
  2) signe/critère clinique ou paraclinique décisif ;
  3) interprétation d'un examen, d'une biologie ou d'une imagerie ;
  4) prochaine étape / prise en charge initiale / surveillance ;
  5) gravité, complication, orientation ou avis spécialisé.
- Ne répète pas le même concept dans deux questions.

RÈGLES CLINIQUES IMPÉRATIVES
- Les faits concernant CE patient doivent provenir uniquement du cas fourni. N'invente jamais un symptôme, une constante, une biologie, une image, un antécédent ou un traitement propre au patient qui n'est pas documenté.
- Tu peux utiliser les connaissances médicales générales, standards et établies nécessaires au raisonnement.
- Chaque bonne réponse doit demander au moins UNE étape de raisonnement clinique.
- INTERDIT : « Quelle conclusion d'imagerie correspond à ce cas ? », « Quel diagnostic a été retenu ? », « Quelle prise en charge a été documentée ? » ou toute question dont la réponse est une simple copie d'un champ du dossier.
- INTERDIT : une bonne réponse qui est seulement une reformulation triviale du texte du dossier.
- Si le dossier est incomplet, pose une question d'interprétation ou de principe clinique applicable aux données présentes plutôt que d'inventer des données manquantes.
- Chaque QCM comporte exactement 4 propositions, une seule meilleure réponse, et 3 distracteurs plausibles du même niveau conceptuel.
- Pas de « toutes les réponses », « aucune des réponses », distracteurs absurdes ou indice de longueur révélant la bonne réponse.
- Évite les posologies/protocoles dépendants du contexte local sauf s'ils sont explicitement documentés.

EXPLICATION IA OBLIGATOIRE POUR CHAQUE QCM
- Le champ correction doit être une vraie explication pédagogique, pas seulement « bonne réponse : B ».
- Elle sera affichée APRÈS CHAQUE réponse, Y COMPRIS lorsque l'utilisateur a répondu juste.
- Explique pourquoi la meilleure réponse est correcte en reliant le principe médical aux éléments utiles du cas.
- Explique brièvement pourquoi les principaux distracteurs sont moins appropriés lorsque cela apporte de la valeur.
- 3 à 6 phrases concises, claires et pédagogiques.
- N'invente aucune nouvelle donnée propre au patient.
- Ne dis pas « vous avez raison/tort » : l'explication doit rester valable quel que soit le choix de l'utilisateur.

CONFIDENTIALITÉ
- Ne réintroduis jamais de nom, téléphone, e-mail, date précise, numéro de dossier, lieu/box, auteur ou autre identifiant.
- Réponds en français.

CAS ANONYMISÉ :
${JSON.stringify(safeCase)}`;

    const model = Deno.env.get('OPENAI_TEXT_MODEL') || Deno.env.get('OPENAI_VISION_MODEL') || 'gpt-5.6';
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        store: false,
        input: [{ role: 'user', content: [{ type: 'input_text', text: prompt }] }],
        text: {
          format: {
            type: 'json_schema',
            name: 'clinical_case_five_qcms',
            strict: true,
            schema: fiveQcmSchema,
          },
        },
      }),
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error('OpenAI 5 QCM failed', response.status, payload);
      return json({ ok: true, generated: false, source: 'fallback', post_id: post.id, reason: 'openai_failed' });
    }

    const generated = parseJsonLoose(extractResponseText(payload));
    const rawQcms = Array.isArray(generated?.qcms) ? generated.qcms : [];
    if (rawQcms.length !== 5) {
      return json({ ok: true, generated: false, source: 'fallback', post_id: post.id, reason: 'invalid_qcm_count' });
    }

    const allowedTopics = new Set(topicEnum);
    const normalized = rawQcms.map((raw: any, index: number) => {
      const options = Array.isArray(raw?.options)
        ? raw.options.map((x: unknown) => scrub(x, 420)).filter(Boolean)
        : [];
      const correctIndex = Number(raw?.correct_index);
      const question = scrub(raw?.question, 1000);
      const correction = scrub(raw?.correction, 4500);
      const topic = String(raw?.topic ?? '').trim();
      if (!question || !correction || options.length !== 4 || new Set(options).size !== 4 ||
          !Number.isInteger(correctIndex) || correctIndex < 0 || correctIndex > 3 || !allowedTopics.has(topic)) {
        throw new Error(`invalid_qcm_${index + 1}`);
      }
      return {
        post_id: post.id,
        position: index + 1,
        question,
        options,
        correct_index: correctIndex,
        correction,
        topic,
        generation_source: 'openai',
        updated_at: new Date().toISOString(),
      };
    });

    if (new Set(normalized.map((q: any) => q.question.toLowerCase())).size !== 5) {
      return json({ ok: true, generated: false, source: 'fallback', post_id: post.id, reason: 'duplicate_questions' });
    }

    // Mettre d'abord à jour les champs historiques du post. Le trigger SQL
    // resynchronise alors les fallbacks et invalide les anciennes réponses ;
    // les cinq upserts IA suivants deviennent la version pédagogique finale.
    const first = normalized[0];
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
      .upsert(normalized, { onConflict: 'post_id,position' });
    if (qcmUpsertError) throw qcmUpsertError;

    return json({
      ok: true,
      generated: true,
      source: 'openai',
      count: 5,
      post_id: post.id,
      practice_case_id: resolvedPracticeCaseId,
    });
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: 'generation_failed' }, 500);
  }
});