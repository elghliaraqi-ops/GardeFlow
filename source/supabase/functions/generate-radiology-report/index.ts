import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { confirmedObservations, unansweredWarnings, factualDraft } from './report_contract.ts';

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
function observedStatus(q: Question, a: Record<string, unknown>): string {
  const status = text(a.status, 30);
  if (status === 'not_evaluable') return 'non évaluable';
  if (status === 'uncertain') return 'incertain';
  if (status === 'unanswered') return 'non renseigné';
  if (status === 'absent') return 'absent (aucune proposition retenue)';
  if (q.kind === 'qcu') return a.value === 'oui' ? 'présent' : 'absent';
  if (q.kind === 'qcm') {
    const signs = cleanArray(a.selected, 6);
    return 'présents : ' + signs.join(' ; ') +
      ' (autres propositions non renseignées)';
  }
  return 'observation décrite par le lecteur';
}
function groundedReview(questions: Question[], answers: Record<string, unknown>,
    generated: unknown) {
  const learned = Array.isArray(generated) ? generated.map(object) : [];
  return questions.map((q, i) => {
    const a = object(answers[q.id]);
    return {
      sign: q.title,
      status: observedStatus(q, a),
      definition: q.definition,
      criteria: q.criteria.join(' ; '),
      // Generated pedagogical explanations are not allowed to override
      // the physician's explicitly recorded present/absent/uncertain state.
      takeaway: text(learned[i]?.takeaway, 600) ||
        'Revoir les critères objectifs de ce signe.',
    };
  });
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
const reportingPrompt = `Tu es radiologue senior et rédacteur de comptes rendus.
À partir EXCLUSIVEMENT des observations actuelles du radiologue et du contexte,
retourne un objet JSON contenant : {"report":{"indication":"...",
"technique":"...","results":"- ...\\n- ...","conclusion":"- ..."},
"quality_warnings":[]}.
INDICATION, TECHNIQUE, RÉSULTATS et CONCLUSION doivent être en français médical.
Résultats descriptifs, objectifs, concis, organisés en tirets ; conclusion courte en tirets.
Une observation "absent" est négative, "présent" est positive.
Une observation "non_renseigne" n'est PAS normale et ne doit pas être décrite.
Une observation "non_evaluable" ou "incertain" ne peut pas devenir normale ou pathologique.
Pour les QCM, les propositions non sélectionnées sont INCONNUES, jamais négatives.
Les comptes rendus antérieurs sont HISTORIQUES : ne pas transformer les signes anciens
en signes actuels ni affirmer une stabilité sans comparaison actuelle documentée.
Respecte les mentions de siège, dimension, unité, côté, injection et mesures
explicitement fournies ; n'en invente aucune. Si le protocole manque, note qu'il
n'est pas renseigné. N'ajoute aucune donnée non examinée.
Ne rédige PAS le bilan pédagogique : il est assemblé par le logiciel à partir
des réponses originales. Fournis uniquement les quatre champs du rapport
et éventuellement de courtes alertes de qualité. Réponse JSON uniquement.`;

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
    const answers = object(input.answers);
    // Send only concise confirmed observations to Groq, never 8-12 detailed
    // definitions, criteria, external image searches or a long revision request.
    const observations = confirmedObservations(questions, answers);
    const review = groundedReview(questions, answers, []);
    const gaps = unansweredWarnings(observations);
    const degraded = (reason: string) => {
      // Log only technical diagnostic codes, never patient information.
      console.warn('radiology_report_factual_fallback', {
        reason, question_count: questions.length,
      });
      return reply({
        report: factualDraft({
          indication: caseInput.indication, technique: caseInput.technique,
        }, observations),
        review,
        generation_mode: 'fact_only',
        quality_warnings: [
          'Génération Groq indisponible : transcription factuelle des réponses, ' +
          'sans reformulation IA. Relire et compléter la synthèse médicale.',
          ...gaps,
        ].slice(0, 18),
      });
    };
    const result = await groq(reportingPrompt, {
      contexte: caseInput,
      observations,
    }, 3200);
    if (result.error) {
      // Keep explicit quota/provider-configuration errors visible. For other
      // technical failures, return a safe draft rather than an unrecoverable 502.
      if (result.error.status === 429 || result.error.status === 503)
        return result.error;
      return degraded('groq_transport_or_output_error');
    }
    const payload = object(result.data);
    const r = object(payload.report);
    const resultLines = Array.isArray(r.results)
      ? r.results.filter(x => typeof x === 'string')
        .map(x => text(x, 700)).join('\\n')
      : text(r.results, 8500);
    const report = {
      indication: text(r.indication, 2000) || caseInput.indication,
      technique: text(r.technique, 2000) ||
        caseInput.technique || 'Protocole non renseigné.',
      results: resultLines,
      conclusion: text(r.conclusion, 1800),
    };
    if (!report.results || !report.conclusion)
      return degraded('invalid_generated_report');
    return reply({
      report, review, generation_mode: 'groq',
      quality_warnings: [...new Set([
        ...gaps, ...cleanArray(payload.quality_warnings, 15),
      ])].slice(0, 18),
    });
  }
  return reply({ error: 'unknown_action' }, 400);
});
