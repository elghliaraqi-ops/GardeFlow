// Radiology report transport: factual, de-identified observations only.
// This module intentionally has no Groq calls and no patient-data persistence.
export type AnswerStatus = 'observed' | 'absent' | 'not_evaluable' | 'uncertain' | 'unanswered';
export type QuestionFact = {
  id: string;
  kind: 'qcu' | 'qcm' | 'texte';
  title: string;
  options: string[];
};
export type AnswerFact = {
  status?: AnswerStatus;
  value?: unknown;
  selected?: unknown;
  notes?: unknown;
};
export type Observation = {
  question: string;
  status: 'présent' | 'absent' | 'incertain' | 'non_evaluable' | 'non_renseigne';
  details: string;
};
function str(value: unknown, max = 1500): string {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}
function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : {};
}
/** Explicit QCM omissions never become negative findings. */
export function confirmedObservations(
  questions: QuestionFact[],
  answers: Record<string, unknown>,
): Observation[] {
  return questions.map((q) => {
    const a = record(answers[q.id]);
    const status = str(a.status, 30);
    const notes = str(a.notes, 2000);
    const parts: string[] = [];
    let output: Observation['status'] = 'non_renseigne';
    if (status === 'not_evaluable') output = 'non_evaluable';
    else if (status === 'uncertain') output = 'incertain';
    else if (status === 'absent' ||
        (q.kind === 'qcu' && status === 'observed' && a.value === 'non')) {
      output = 'absent';
      if (q.kind === 'qcm') parts.push('Aucun des signes proposés, explicitement vérifiés');
    } else if (status === 'observed') {
      if (q.kind === 'qcu' && a.value === 'oui') output = 'présent';
      else if (q.kind === 'qcm' && Array.isArray(a.selected)) {
        const selected = a.selected
          .filter((v): v is string => typeof v === 'string' && q.options.includes(v));
        if (selected.length) {
          output = 'présent';
          parts.push('Signes observés : ' + selected.join(' ; '));
          parts.push('Propositions non sélectionnées : statut inconnu');
        }
      } else if (q.kind === 'texte' && str(a.value, 2000)) {
        output = 'présent';
        parts.push(str(a.value, 2000));
      }
    }
    if (notes) parts.push('Précisions du lecteur : ' + notes);
    return { question: q.title, status: output, details: parts.join(' ; ') };
  });
}
export function unansweredWarnings(observations: Observation[]): string[] {
  return observations.filter(o => ['non_renseigne', 'non_evaluable', 'incertain'].includes(o.status))
    .map(o => o.question + ' : ' + (
      o.status === 'non_evaluable' ? 'non évaluable'
      : o.status === 'incertain' ? 'incertain' : 'non renseigné') + '.');
}
/**
 * A degraded, factual worksheet when Groq's response is truncated or malformed.
 * The conclusion explicitly stays unconfirmed rather than inventing a diagnosis.
 */
export function factualDraft(
  ctx: { indication: string; technique: string },
  observations: Observation[],
) {
  const findings: string[] = [];
  for (const o of observations) {
    if (o.status === 'non_renseigne') continue;
    if (o.status === 'présent') {
      findings.push('- ' + o.question + ' : ' + (o.details || 'présent.'));
    } else if (o.status === 'absent') {
      findings.push('- ' + o.question + ' : absent, selon les constatations du lecteur.' +
        (o.details ? ' ' + o.details : ''));
    } else if (o.status === 'incertain') {
      findings.push('- ' + o.question + ' : incertain.' +
        (o.details ? ' ' + o.details : ''));
    } else if (o.status === 'non_evaluable') {
      findings.push('- ' + o.question + ' : non évaluable.' +
        (o.details ? ' ' + o.details : ''));
    }
  }
  return {
    indication: str(ctx.indication, 1800),
    technique: str(ctx.technique, 1400) || 'Protocole non renseigné.',
    results: findings.join('\n') || '- Aucune constatation radiologique documentée dans les réponses.',
    conclusion: '- Synthèse radiologique à rédiger après vérification des constatations ci-dessus.',
  };
}
