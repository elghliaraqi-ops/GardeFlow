import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

// Stateless radiology reporting assistant: no patient data are persisted here.
// Each phase makes a single Groq request. Never run a medical "review" request.
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};
function reply(data: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), { status, headers: { ...headers, ...extra } });
}
function text(value: unknown, limit: number): string {
  return typeof value === 'string' ? value.trim().slice(0, limit) : '';
}
function object(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : {};
}
function cleanArray(value: unknown, max = 12): string[] {
  return Array.isArray(value)
    ? value.filter(x => typeof x === 'string').map(x => text(x, 240)).filter(Boolean).slice(0, max)
    : [];
}
type ClinicalInput = {
  exam: string; region: string; indication: string; technique: string;
  clinical: string; comparative: boolean; oldReports: string;
};
function clinical(value: unknown): ClinicalInput | null {
  const v = object(value);
  const result = {
    exam: text(v.exam, 100),
    region: text(v.region, 180),
    indication: text(v.indication, 1800),
    technique: text(v.technique, 1400),
    clinical: text(v.clinical, 2400),
    comparative: v.comparative === true,
    oldReports: text(v.oldReports, 8500),
  };
  if (!result.exam || !result.region || !result.indication ||
      (result.comparative && !result.oldReports)) return null;
  // Reject oversized input rather than silently dropping clinical observations.
  if (JSON.stringify(v).length > 19000) return null;
  return result;
}
type Question = {
  id: string; kind: 'qcu'|'qcm'|'texte'; title: string;
  definition: string; criteria: string[]; options: string[];
  reference_query: string;
};
function normalizedQuestions(raw: unknown): Question[] | null {
  if (!Array.isArray(raw) || raw.length < 5 || raw.length > 12) return null;
  const qs = raw.map((entry: unknown, i: number) => {
    const q = object(entry), kind = text(q.kind, 10);
    const options = cleanArray(q.options, 6);
    if (!['qcu', 'qcm', 'texte'].includes(kind) ||
        !text(q.title, 280) || !text(q.definition, 500) ||
        !cleanArray(q.criteria, 6).length ||
        (kind === 'qcm' && (options.length < 2 || options.length > 6))) return null;
    return {
      id: 'q' + (i + 1),
      kind: kind as Question['kind'],
      title: text(q.title, 280),
      definition: text(q.definition, 500),
      criteria: cleanArray(q.criteria, 6),
      options: kind === 'qcm' ? options : [],
      // Only anatomy/medical keywords; never patient-specific details.
      reference_query: text(q.reference_query, 200),
    };
  });
  if (qs.some(q => !q)) return null;
  return qs as Question[];
}
function validateAnswers(questions: Question[], value: unknown): boolean {
  const answers = object(value);
  for (const question of questions) {
    const a = object(answers[question.id]);
    if (!['observed', 'absent', 'not_evaluable', 'uncertain', 'unanswered'].includes(text(a.status, 30)))
      return false;
    if (question.kind === 'qcm' && a.status === 'observed') {
      if (!Array.isArray(a.selected) || !a.selected.length ||
          a.selected.some(x => !question.options.includes(x))) return false;
    }
    if (question.kind === 'qcu' && a.status === 'observed' && !['oui', 'non'].includes(a.value as string))
      return false;
    if (question.kind === 'texte' && a.status === 'observed' && !text(a.value, 2000))
      return false;
    if (typeof a.notes !== 'string' || a.notes.length > 2000) return false;
  }
  return true;
}
function rateLimitSeconds(response: Response, payload: any): number | null {
  const n = Number(response.headers.get('retry-after'));
  if (Number.isFinite(n) && n > 0) return Math.min(86400, Math.ceil(n));
  const m = String(payload?.error?.message || '').match(/try again in\s+(\d+(?:\.\d+)?)s/i);
  return m ? Math.min(86400, Math.ceil(Number(m[1]))) : null;
}
async function groq(system: string, user: unknown, budget: number) {
  const key = Deno.env.get('GROQ_API_KEY');
  if (!key) return { error: reply({ error: 'groq_key_missing' }, 503) };
  const configured = Deno.env.get('GROQ_TEXT_MODEL');
  const model = configured === 'openai/gpt-oss-20b' ? configured : 'openai/gpt-oss-120b';
  let response: Response;
  try {
    response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      signal: AbortSignal.timeout(95000),
      headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model, temperature: 0.15, reasoning_effort: 'low',
        max_completion_tokens: budget, stream: false,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system + '\nRéponds exclusivement par un objet JSON valide, sans Markdown.' },
          { role: 'user', content: JSON.stringify(user) },
        ],
      }),
    });
  } catch (_) {
    return { error: reply({ error: 'groq_network_or_timeout' }, 504) };
  }
  const payload: any = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 429) {
      const seconds = rateLimitSeconds(response, payload);
      return { error: reply({
        error: 'groq_rate_limited', retry_after_seconds: seconds,
        detail: 'Quota Groq atteint. Les réponses saisies sont conservées ; ne relancez pas immédiatement.',
      }, 429, seconds ? { 'Retry-After': String(seconds) } : {}) };
    }
    return { error: reply({ error: 'groq_provider_error', status: response.status }, 502) };
  }
  if (payload?.choices?.[0]?.finish_reason === 'length')
    return { error: reply({ error: 'groq_output_truncated' }, 502) };
  const raw = payload?.choices?.[0]?.message?.content;
  if (typeof raw !== 'string') return { error: reply({ error: 'groq_empty_response' }, 502) };
  try { return { data: object(JSON.parse(raw)) }; }
  catch (_) { return { error: reply({ error: 'groq_invalid_json_response' }, 502) }; }
}
const planningPrompt = `Tu es radiologue senior francophone et pédagogue du résidanat. Tu guides un médecin
pendant la lecture d'un examen RÉEL, sans supposer les résultats de l'imagerie.
Retourne {"questions":[5 à 12 objets {"kind":"qcu|qcm|texte",
"title":"question d'observation précise","definition":"définition anatomique ou du signe",
"criteria":["critères radiologiques objectifs et adaptés au protocole"],
"options":["2 à 6 signes descriptifs distincts si qcm, sinon []"],
"reference_query":"mots-clés anatomiques et signe radiologique sans données du patient"}]}.
Fais une progression systématique, ciblée sur la région, modalité, indication et protocole.
QCU = présence/absence du signe demandé. QCM = plusieurs observations pouvant être cochées,
les non-cochées sont INCONNUES, pas automatiquement absentes. texte = mesures, localisation,
extension ou description libre. N'inclus pas d'informations sur les réponses ou le diagnostic
du patient. Ne propose ni signe non évaluable par la modalité/protocole ni image de patient inventée.
En comparatif, interroge sur l'évolution des lésions antérieurement décrites et les limites
de comparabilité. Une question à la fois sera montrée par le client. Fournis une définition,
des critères concrets et une requête d'image médicale de référence pour chaque question.`;
const reportingPrompt = `Tu es radiologue senior rédigeant un compte rendu patient réel à partir
des seules constatations explicitement apportées par le lecteur. Aucune interprétation d'image
réelle n'est effectuée par toi. L'ancien rapport est du contexte HISTORIQUE et ne prouve
jamais une observation actuelle.
Réponds en JSON: {
"report":{"indication":"...", "technique":"...", "results":"tirets objectifs détaillés",
"conclusion":"tirets courts hiérarchisés et prudents"},
"review":[{"sign":"...", "status":"présent|absent|non évalué|incertain",
"definition":"...", "criteria":"...", "takeaway":"..."}],
"quality_warnings":["éléments cliniquement importants non renseignés"]}.
Respecte strictement INDICATION, TECHNIQUE, RÉSULTATS, CONCLUSION. Ne mets pas de conclusion
dans les résultats. Formulations concises, descriptives, terminologie radiologique française.
Ne complète JAMAIS les rubriques normales si elles n'ont pas été vérifiées.
Ne transforme pas une réponse non renseignée en absence, ni une suspicion en certitude.
Une QCM cochée = seulement les observations sélectionnées sont présentes ; les autres
ne sont PAS nécessairement absentes. "Aucune" indique des signes explicitement recherchés absents.
Signale non-évaluable ou incertain si important. Ne conclus à une stabilité/progression que
sur les comparaisons ACTUELLEMENT renseignées par le radiologue. N'invente pas de mesures,
contraste, protocoles, antériorités, dates, diagnostics ou examens. Si la technique n'est pas
précisée, l'indiquer sobrement sans en inventer une.
Le bilan pédagogique doit lister les signes recherchés et leur statut réel
(présent/absent/non évalué/incertain), définitions, critères et points clés.
Le bilan est DISTINCT du compte rendu copiable.
L'utilisateur est le médecin : le texte reste un projet à vérifier et valider.`;

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (req.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  const auth = req.headers.get('authorization') || '';
  if (!auth.startsWith('Bearer ')) return reply({ error: 'authentication_required' }, 401);
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anon) return reply({ error: 'backend_not_configured' }, 503);
  const caller = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: identity, error: authError } = await caller.auth.getUser();
  if (authError || !identity.user) return reply({ error: 'authentication_failed' }, 401);
  const input = object(await req.json().catch(() => ({})));
  const caseInput = clinical(input.clinical);
  if (!caseInput) return reply({ error: 'invalid_clinical_context' }, 400);
  const action = text(input.action, 30);
  if (action === 'plan') {
    const result = await groq(planningPrompt, {
      contexte: caseInput,
      instructions: 'Adapte les questions, ne réponds pas à la place du radiologue.',
    }, 3400);
    if (result.error) return result.error;
    const questions = normalizedQuestions(result.data?.questions);
    if (!questions) return reply({ error: 'invalid_generated_questions' }, 502);
    return reply({ questions });
  }
  if (action === 'report') {
    const questions = normalizedQuestions(input.questions);
    if (!questions || !validateAnswers(questions, input.answers))
      return reply({ error: 'invalid_case_answers' }, 400);
    const result = await groq(reportingPrompt, {
      contexte: caseInput, questions, reponses: input.answers,
      rappel: 'Ne rapporte que ce qui a été réellement observé et saisi. Une donnée non évaluée reste inconnue.',
    }, 4000);
    if (result.error) return result.error;
    const r = object(result.data?.report);
    const report = {
      indication: text(r.indication, 2000),
      technique: text(r.technique, 2000),
      results: text(r.results, 8500),
      conclusion: text(r.conclusion, 1800),
    };
    if (!report.indication || !report.technique || !report.results || !report.conclusion)
      return reply({ error: 'invalid_generated_report' }, 502);
    const review = Array.isArray(result.data?.review)
      ? result.data.review.slice(0, 18).map((v: unknown) => {
        const o = object(v);
        return {
          sign: text(o.sign, 260),
          status: text(o.status, 60),
          definition: text(o.definition, 600),
          criteria: text(o.criteria, 800),
          takeaway: text(o.takeaway, 600),
        };
      }).filter((v: any) => v.sign)
      : [];
    return reply({
      report, review, quality_warnings: cleanArray(result.data?.quality_warnings, 15),
    });
  }
  return reply({ error: 'unknown_action' }, 400);
});
