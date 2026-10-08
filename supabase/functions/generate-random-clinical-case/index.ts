import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

// No patient data is sent to the model. Every generated case is fictional.
const specialties = [
  'Chirurgie viscérale', 'Orthopédie', 'Cardiologie', 'Neurologie',
  'Urologie', 'ORL', 'Gynécologie', 'Réanimation', 'Pneumologie',
  'Gastro-entérologie', 'Néphrologie', 'Endocrinologie', 'Dermatologie',
  'Psychiatrie', 'Pédiatrie', 'Ophtalmologie', 'Neurochirurgie',
  'Chirurgie thoracique', 'Chirurgie vasculaire', 'Maladies infectieuses',
  'Médecine interne',
] as const;
const levels = ['classique', 'intermédiaire', 'complexe'] as const;
const textFields = [
  'location', 'chief_complaint', 'interrogatoire',
  'personal_surgical_history', 'personal_medical_history',
  'family_surgical_history', 'family_medical_history',
  'consultation_reason', 'illness_history', 'clinical_exam',
  'complementary_exams', 'imaging_conclusion', 'assessment',
  'plan', 'specialist_service', 'hospitalization_service',
] as const;
const boolFields = [
  'specialist_opinion_requested', 'specialist_opinion_done',
  'waiting', 'prescription_done', 'discharged', 'hospitalized',
] as const;
const caseProperties: Record<string, unknown> = {
  age: { type: 'integer', minimum: 1, maximum: 105 },
  sex: { type: 'string', enum: ['F', 'M', 'Autre', 'Non précisé'] },
};
for (const field of textFields) caseProperties[field] = { type: 'string' };
for (const field of boolFields) caseProperties[field] = { type: 'boolean' };
const caseSchema = {
  type: 'object', additionalProperties: false,
  required: ['age', 'sex', ...textFields, ...boolFields],
  properties: caseProperties,
};
const outputSchema = {
  type: 'object', additionalProperties: false,
  required: ['case'], properties: { case: caseSchema },
};

function cors(req: Request): Record<string, string> {
  const origin = (req.headers.get('Origin') ?? '').trim();
  const allowed = (Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS') ?? '')
    .split(',').map(x => x.trim()).filter(Boolean);
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
  if (!origin) return headers;
  if (allowed.length === 0) headers['Access-Control-Allow-Origin'] = '*';
  else if (allowed.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Vary'] = 'Origin';
  }
  return headers;
}
function reply(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors(req),
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store' },
  });
}
function takeText(value: unknown, max = 2400): string {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}
function extractGroqText(payload: any): string {
  if (typeof payload?.output_text === 'string') return payload.output_text.trim();
  const parts: string[] = [];
  for (const item of payload?.output ?? []) {
    if (item?.type !== 'message') continue;
    for (const part of item?.content ?? []) {
      if ((part?.type === 'output_text' || part?.type === 'text') &&
          typeof part.text === 'string') parts.push(part.text);
    }
  }
  return parts.join('').trim();
}
function pick<T>(items: readonly T[]): T {
  const n = crypto.getRandomValues(new Uint32Array(1))[0];
  return items[n % items.length];
}
function cleanCase(raw: any, specialty: string) {
  if (!raw || typeof raw !== 'object') return null;
  const age = Number(raw.age);
  const sex = takeText(raw.sex, 20);
  if (!Number.isInteger(age) || age < 1 || age > 105 ||
      !['F', 'M', 'Autre', 'Non précisé'].includes(sex)) return null;
  const c: Record<string, unknown> = { age, sex };
  for (const field of textFields) c[field] = takeText(raw[field]);
  for (const field of boolFields) c[field] = raw[field] === true;
  c.location = 'Simulation pédagogique · ' + specialty;
  const specialist = c.specialist_opinion_requested === true;
  const specialistService = String(c.specialist_service ?? '');
  c.specialist_service = specialist
    ? (specialties as readonly string[]).includes(specialistService) ? specialistService : 'Autre'
    : '';
  c.specialist_opinion_done = specialist && c.specialist_opinion_done === true;
  if (c.hospitalized === true) c.discharged = false;
  if (c.discharged === true) c.hospitalized = false;
  if (c.hospitalized !== true) c.hospitalization_service = '';
  const required: Record<string, number> = {
    consultation_reason: 15, illness_history: 30,
    clinical_exam: 30, assessment: 20, plan: 30,
  };
  if (Object.entries(required).some(([key, len]) => String(c[key]).length < len))
    return null;
  // Persistent, visible educational marker: do not represent this as a real patient.
  c.chief_complaint = '[CAS FICTIF – IA] ' +
    (String(c.chief_complaint) || String(c.consultation_reason)).slice(0, 400);
  c.consultation_reason = '[SIMULATION IA] ' + c.consultation_reason;
  return c;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, {
    status: 204, headers: cors(req),
  });
  if (req.method !== 'POST')
    return reply(req, { ok: false, error: 'method_not_allowed' }, 405);
  const origin = (req.headers.get('Origin') ?? '').trim();
  const allowed = (Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS') ?? '')
    .split(',').map(x => x.trim()).filter(Boolean);
  if (origin && allowed.length > 0 && !allowed.includes(origin))
    return reply(req, { ok: false, error: 'origin_not_allowed' }, 403);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer '))
    return reply(req, { ok: false, error: 'authentication_required' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const groqKey = Deno.env.get('GROQ_API_KEY');
  if (!supabaseUrl || !anonKey || !serviceKey || !groqKey)
    return reply(req, { ok: false, error: 'provider_not_configured' }, 503);

  try {
    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await caller.auth.getUser();
    if (error || !data.user?.id)
      return reply(req, { ok: false, error: 'authentication_failed' }, 401);
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const profile = await admin.from('profiles')
      .select('account_status').eq('id', data.user.id).maybeSingle();
    if (profile.error || profile.data?.account_status !== 'active')
      return reply(req, { ok: false, error: 'account_inactive' }, 403);

    const specialty = pick(specialties);
    const level = pick(levels);
    const model = Deno.env.get('GROQ_CASE_MODEL')?.trim() ||
      'openai/gpt-oss-20b';
    const prompt = `Crée UN cas clinique ENTIÈREMENT FICTIF, pédagogique et vraisemblable pour des internes en médecine.
Spécialité imposée : ${specialty}. Niveau : ${level}.
Aucune donnée réelle : pas de nom, initiales, date de naissance, adresse, téléphone ni identifiant.
Rédige en français médical précis, avec signes positifs ET négatifs utiles.
Remplis toutes les rubriques du formulaire et décris un scénario clinique cohérent avec l'âge et le sexe.
Détaille les constantes chiffrées pertinentes, la biologie avec unités et valeurs plausibles,
et l'imagerie uniquement lorsqu'elle est pertinente (sinon chaîne vide).
L'interrogatoire, les antécédents, l'histoire, l'examen et les résultats doivent concorder
avec la synthèse diagnostique et la conduite à tenir.
Le bilan et le plan doivent couvrir les diagnostics différentiels, la gravité,
les examens utiles, la décision thérapeutique, la surveillance et l'orientation.
Les booléens des décisions doivent correspondre à la prise en charge décrite.
N'invente ni références bibliographiques ni recommandations datées.
Tu écris un exercice d'apprentissage, pas une ordonnance ni la description d'un vrai patient.
Réponds exclusivement avec l'objet JSON structuré demandé.`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 45000);
    let provider: Response;
    try {
      provider = await fetch('https://api.groq.com/openai/v1/responses', {
        method: 'POST', signal: controller.signal,
        headers: {
          Authorization: `Bearer ${groqKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model, instructions: 'Réponds seulement selon le schéma JSON fourni.',
          input: prompt, reasoning: { effort: 'low' },
          text: { format: {
            type: 'json_schema', name: 'random_clinical_case', schema: outputSchema,
          } }, store: false, max_output_tokens: 5500,
        }),
      });
    } finally { clearTimeout(timer); }
    if (!provider.ok) {
      const status = provider.status;
      console.log(JSON.stringify({ event: 'random_case_provider_error', status }));
      return reply(req, { ok: false, error:
        status === 429 ? 'rate_limited' : 'generation_unavailable' },
        status === 429 ? 429 : 503);
    }
    const payload = await provider.json().catch(() => null);
    let generated: unknown;
    try {
      const text = extractGroqText(payload);
      generated = JSON.parse(text.replace(/^\x60\x60\x60(?:json)?\s*/i, '')
        .replace(/\s*\x60\x60\x60$/i, ''));
    } catch {
      return reply(req, { ok: false, error: 'invalid_model_json' }, 502);
    }
    const simulated = cleanCase((generated as any)?.case, specialty);
    if (!simulated)
      return reply(req, { ok: false, error: 'invalid_generated_case' }, 502);
    return reply(req, {
      ok: true, fictional: true, requires_review: true,
      case: simulated,
    });
  } catch (error) {
    console.log(JSON.stringify({
      event: 'random_case_generation_error',
      type: error instanceof DOMException && error.name === 'AbortError'
        ? 'timeout' : 'unavailable',
    }));
    return reply(req, { ok: false, error: 'generation_unavailable' }, 503);
  }
});
