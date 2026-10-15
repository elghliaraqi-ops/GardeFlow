import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { confirmedObservations, unansweredWarnings, factualDraft } from './report_contract.ts';
import { examTemplate } from './radiology_templates.ts';
import { structuredReport } from './structured_report.ts';
import { clientQuestionCapacity, compatibleQuestionSet } from './question_compatibility.ts';

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
  section?: string; normal_text?: string; abnormal_text?: string;
};
function normalizedQuestions(raw: unknown): Question[] | null {
  if (!Array.isArray(raw) || raw.length < 5 || raw.length > 48) return null;
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
      section: text(q.section, 100) || 'Constatations',
      normal_text: text(q.normal_text, 400),
      abnormal_text: text(q.abnormal_text, 280),
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
const planningPrompt = `Tu es radiologue senior francophone, niveau résidanat.
Prépare un parcours systématique pour la modalité/région/protocole réellement demandé.
IMPORTANT : commence par les structures anatomiques habituelles et les signes
fréquents ou incontournables, dans l'ordre de lecture d'un radiologue.
Les diagnostics rares et traumatiques ne viennent qu'après le bilan de base,
et uniquement si pertinents pour l'indication.
Si possible 12 à 18 questions (minimum 5, maximum 20), une à la fois dans l'interface.
Retours JSON {"questions":[{ "kind":"qcu|qcm|texte","section":"région anatomique",
"title":"question précise sur un signe à chercher",
"definition":"définition utile",
"criteria":["2-3 critères radiologiques concrets"],
"options":["choix descriptifs seulement si QCM, sinon []"],
"reference_query":"signes anatomiques du même examen",
"normal_text":"phrase radiologique complète à employer UNIQUEMENT si signe explicitement absent",
"abnormal_text":"phrase descriptive neutre du signe s'il est présent"}]}.
Conçois des questions QCU prioritaires (présent/absent), quelques QCM descriptifs
quand plusieurs observations sont possibles, puis questions libres pour mesures.
Le texte normal proposé pour chaque signe doit être exact et ne pas présumer
de la normalité d'une autre structure non vérifiée.
Inclure systématiquement les voies de drainage / os / vaisseaux / parenchymes
selon l'examen ; ne pas demander de signe non évaluable sur la technique.
Si comparatif, ajouter question sur évolution des signes historiques, qui ne
sont jamais présumés présents actuellement.
Ne réponds jamais à la place du médecin. Pas d'ostéome mucoïde ou pathologie
rare systématique si un scanner des sinus est demandé.`;
const reportingPrompt = `Tu es radiologue senior rédacteur de comptes rendus
français, utilisant des modèles de comptes rendus par région anatomique.
Rédige sur la base EXCLUSIVE des constats effectués par le médecin.
Réponse JSON {"report":{"indication":"...", "technique":"...",
"results":"...", "conclusion":"..."}, "quality_warnings":[]}.
INDICATION, TECHNIQUE, RÉSULTATS, CONCLUSION.
RÉSULTATS doit respecter les RUBRIQUES ANATOMIQUES fournies, dans l'ordre.
Utilise des phrases radiologiques naturelles : "Sinus maxillaires aérés",
"Voies de drainage libres", "Pas de niveau hydro-aérique" quand ces faits
sont expressément vérifiés. Jamais "maladie X : absente" en inventaire.
Regroupe les constatations normales pertinentes sans perdre les anomalies.
Ne crée pas d'ostéome, de mucocèle ou de fracture si non recherché ou non vu.
Aucune norme chiffrée ou interprétation "dans les normes" sans critère fourni.
Conserve toutes mesures, unités, localisation, côtés et évolution documentées.
Conclusion brève, informative, avec 1-3 tirets et seulement les hypothèses
étayées ; si donnée insuffisante, explicite les limites.
Interdit de transformer anciens résultats en constatations actuelles,
les QCM non cochés en absences, ou non renseigné en normalité.
Le brouillon descriptif "plan_base" fourni est le contrat FACTUEL :
ne supprimer aucun fait vérifié et n'ajouter aucun résultat non documenté.
Ne produis pas le bilan pédagogique.`;


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
    const capacity = clientQuestionCapacity(input.max_questions);
    const template = examTemplate(caseInput.exam, caseInput.region,
      caseInput.indication, caseInput.technique);
    if (template) {
      const questions: Question[] = [...template.questions];
      if (caseInput.comparative) {
        questions.push({
          id: 'q' + (questions.length + 1), kind: 'texte',
          section: 'Comparaison',
          title: 'Évolution ACTUELLE des anomalies décrites sur les examens antérieurs ?',
          definition: 'Comparer uniquement les constatations effectivement vérifiées sur les images actuelles.',
          criteria: ['Indiquer la date comparée, la topographie, les mesures et leur évolution lorsqu’elles sont disponibles.'],
          options: [], reference_query: '', normal_text: '', abnormal_text: '',
        });
      }
      const compatible = compatibleQuestionSet(
        questions, capacity, caseInput.indication, caseInput.comparative);
      return reply({
        questions: compatible.questions,
        template_key: template.key,
        available_questions: compatible.available,
        limited_for_legacy_client: compatible.truncated,
        generation_mode: 'systematic_checklist',
      });
    }
    const result = await groq(planningPrompt, {
      contexte: caseInput,
      instructions: 'Couverture anatomique systématique avant les diagnostics rares.',
    }, 4800);
    if (result.error) return result.error;
    const questions = normalizedQuestions(result.data?.questions);
    if (!questions) return reply({ error: 'invalid_generated_questions' }, 502);
    const compatible = compatibleQuestionSet(
      questions, capacity, caseInput.indication, caseInput.comparative);
    return reply({
      questions: compatible.questions,
      available_questions: compatible.available,
      limited_for_legacy_client: compatible.truncated,
      generation_mode: 'groq_systematic',
    });
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
    const hasAnatomicalModel = questions.some(q => !!q.normal_text && !!q.section);
    const modelDraft = hasAnatomicalModel
      ? structuredReport(caseInput, questions, answers)
      : null;
    const gaps = [...new Set([
      ...unansweredWarnings(observations),
      ...(modelDraft?.missing ?? []),
    ])];
    // A fully checked normal exam has an evidence-gated radiological template.
    // Avoid a costly Groq call that might introduce unrelated absent diseases.
    if (modelDraft && observations.length > 0 &&
        observations.every(o => o.status === 'absent')) {
      return reply({
        report: modelDraft, review, generation_mode: 'systematic_template',
        quality_warnings: gaps.slice(0, 18),
      });
    }
    const degraded = (reason: string) => {
      // Log only technical diagnostic codes, never patient information.
      console.warn('radiology_report_factual_fallback', {
        reason, question_count: questions.length,
      });
      return reply({
        report: modelDraft ?? factualDraft({
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
      plan_base: modelDraft ? { results: modelDraft.results,
        conclusion: modelDraft.conclusion, sections: modelDraft.coveredSections } : null,
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
      indication: caseInput.indication,
      technique: caseInput.technique || 'Protocole non renseigné.',
      // A checked, anatomical template is authoritative: do not accept
      // unverified additional Groq normality claims or a list of "X: absent".
      results: modelDraft ? modelDraft.results : resultLines,
      conclusion: modelDraft
        ? (observations.some(o => o.status === 'présent') &&
            text(r.conclusion, 1800).length > 8
            ? text(r.conclusion, 1800)
            : modelDraft.conclusion)
        : text(r.conclusion, 1800),
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
