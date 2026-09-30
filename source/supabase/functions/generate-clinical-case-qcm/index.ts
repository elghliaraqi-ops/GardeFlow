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

const qcmSchema = {
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
    topic: {
      type: 'string',
      enum: ['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'],
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

    const { data: post, error: postError } = await adminClient
      .from('clinical_case_posts')
      .select('id,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan,disposition,specialist_service')
      .eq('practice_case_id', practiceCaseId)
      .maybeSingle();
    if (postError || !post) return json({ ok: false, error: 'post_not_ready' }, 409);

    if (!openaiKey) {
      return json({ ok: true, generated: false, source: 'fallback' });
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

    const prompt = `Tu crées UN QCM pédagogique à partir d'un cas clinique déjà anonymisé.\n\nRègles impératives :\n- Utilise uniquement les informations présentes dans le cas fourni. N'invente aucun diagnostic, examen, traitement, résultat ni recommandation.\n- La question peut porter sur le motif/symptôme, l'examen, l'imagerie, la synthèse, la prise en charge réellement documentée, l'orientation ou l'avis spécialisé.\n- Choisis le point le plus intéressant et réellement documenté dans CE cas.\n- Formule la question comme un exercice de lecture/raisonnement sur le cas documenté, pas comme une recommandation médicale universelle.\n- Il doit y avoir exactement 4 réponses, une seule correcte et trois distracteurs plausibles mais clairement incompatibles avec le cas fourni.\n- La correction explique pourquoi la réponse est correcte en résumant les éléments utiles du cas. Elle doit correspondre au cas lui-même et ne pas ajouter de conduite à tenir extérieure.\n- Ne réintroduis jamais de nom, téléphone, e-mail, date précise, numéro de dossier, lieu/box, auteur ou autre identifiant.\n- Réponds en français, de façon concise et professionnelle.\n\nCAS ANONYMISÉ :\n${JSON.stringify(safeCase)}`;

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
            name: 'clinical_case_qcm',
            strict: true,
            schema: qcmSchema,
          },
        },
      }),
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      console.error('OpenAI QCM failed', response.status, payload);
      return json({ ok: true, generated: false, source: 'fallback', reason: 'openai_failed' });
    }

    const generated = parseJsonLoose(extractResponseText(payload));
    const options = Array.isArray(generated?.options)
      ? generated.options.map((x: unknown) => scrub(x, 320)).filter(Boolean)
      : [];
    const correctIndex = Number(generated?.correct_index);
    const question = scrub(generated?.question, 800);
    const correction = scrub(generated?.correction, 3500);
    const topic = String(generated?.topic ?? '').trim();
    const allowedTopics = new Set(['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise']);

    if (!question || !correction || options.length !== 4 || new Set(options).size !== 4 || !Number.isInteger(correctIndex) || correctIndex < 0 || correctIndex > 3 || !allowedTopics.has(topic)) {
      return json({ ok: true, generated: false, source: 'fallback', reason: 'invalid_model_output' });
    }

    const { error: updateError } = await adminClient
      .from('clinical_case_posts')
      .update({
        qcm_question: question,
        qcm_options: options,
        correct_index: correctIndex,
        correction,
        question_topic: topic,
        generation_source: 'openai',
        updated_at: new Date().toISOString(),
      })
      .eq('id', post.id)
      .eq('practice_case_id', practiceCaseId);
    if (updateError) throw updateError;

    return json({ ok: true, generated: true, source: 'openai' });
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: 'generation_failed' }, 500);
  }
});
