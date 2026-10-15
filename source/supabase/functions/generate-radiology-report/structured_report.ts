import { confirmedObservations, type QuestionFact } from './report_contract.ts';
import { sentence, positiveDescription, reportingSection } from './radiology_prose.ts';

// In a systematic exam each NORMAL phrase is emitted only after the physician
// explicitly answered "absent" to its corresponding abnormality question.
// This is a writing template, not automated image interpretation.
export type ReportingQuestion = QuestionFact & {
  section?: string;
  normal_text?: string;
  abnormal_text?: string;
};
type ReportContext = {
  exam: string; region: string; indication: string; technique: string;
  comparative: boolean; oldReports: string;
};
type Answer = { status?: unknown; value?: unknown; selected?: unknown; notes?: unknown };
const string = (v: unknown) => typeof v === 'string' ? v.trim() : '';
const record = (v: unknown): Answer => v && typeof v === 'object' && !Array.isArray(v)
  ? v as Answer : {};
const okNegative = (q: ReportingQuestion, answers: Record<string, unknown>) => {
  const a = record(answers[q.id]);
  return a.status === 'absent' ||
    (q.kind === 'qcu' && a.status === 'observed' && a.value === 'non');
};
function minus(s: string): string {
  return '- ' + sentence(s);
}
function phrase(q: ReportingQuestion, a: Answer, status: string): string {
  if (status === 'absent') return sentence(string(q.normal_text));
  if (status !== 'présent') return '';
  const notes = string(a.notes);
  if (q.kind === 'texte') {
    const free = string(a.value);
    return sentence(free + (notes ? ' (' + notes + ')' : ''));
  }
  if (q.kind === 'qcm') {
    const selected = Array.isArray(a.selected)
      ? a.selected.filter((v): v is string => typeof v === 'string' && q.options.includes(v))
      : [];
    if (!selected.length) return '';
    // A multiple-choice selection documents ONLY checked options.
    // Unchecked options remain unknown, never read as negative.
    if (notes && notes.length > 34 &&
        /[.;]/.test(notes)) return sentence(notes);
    return sentence('Les signes suivants sont mis en évidence : ' +
      selected.join(', ') + (notes ? ' (' + notes + ')' : ''));
  }
  return positiveDescription(q.title, string(q.abnormal_text), notes);
}
/** 1-3 coherent sentences per bullet instead of a check-list of negatives. */
function compactResults(lines: {text:string; positive:boolean}[]): string[] {
  const written: string[] = [], negatives: string[] = [];
  const flush = () => {
    if (!negatives.length) return;
    written.push(minus(negatives.join(' ')));
    negatives.length = 0;
  };
  let size = 0;
  for (const entry of lines) {
    if (entry.positive) {
      flush();
      size = 0;
      written.push(minus(entry.text));
      continue;
    }
    if (size + entry.text.length > 240 || negatives.length === 3) {
      flush(); size = 0;
    }
    negatives.push(sentence(entry.text));
    size += entry.text.length;
  }
  flush();
  return written;
}
export function structuredReport(
  clinical: ReportContext,
  questions: ReportingQuestion[],
  answers: Record<string, unknown>,
) {
  const observations = confirmedObservations(questions, answers);
  const sections = new Map<string, {text:string; positive:boolean}[]>();
  const skips: string[] = [];
  const add = (section: string, content: string, positive = false) => {
    if (!sections.has(section)) sections.set(section, []);
    sections.get(section)!.push({text:content, positive});
  };
  const sinus = questions.length > 0 &&
    questions.some(q => q.section === 'Variantes à risque chirurgical') &&
    /sinus/i.test(clinical.region + ' ' + clinical.exam);
  // Four separate verified negative parenchymal checks allow a SINGLE
  // idiomatic global statement instead of repetitive "X : absent" lines.
  const mucosa = questions.filter(q => q.section === 'Sinus' &&
    /(maxillaire|frontal|ethmoïdal|sphénoïdal)/i.test(q.title));
  const liquid = questions.find(q => q.section === 'Sinus' &&
    /niveau hydro.aérique/i.test(q.title));
  // A fluid level invalidates a broad "all sinuses correctly aerated" claim,
  // even when the four isolated mucosal-thickening checks are negative.
  const groupedMucosa = sinus && mucosa.length === 4 &&
    mucosa.every(q => okNegative(q, answers)) &&
    (!liquid || okNegative(liquid, answers));
  const risk = questions.filter(q => q.section === 'Variantes à risque chirurgical');
  const groupedRisk = sinus && risk.length >= 4 && risk.every(q => okNegative(q, answers));
  let mucosaWritten = false;
  let riskWritten = false;
  for (let i = 0; i < questions.length; i++) {
    const q = questions[i];
    if (groupedMucosa && mucosa.some(v => v.id === q.id)) {
      if (!mucosaWritten) {
        add('Sinus', 'Bonne aération de l’ensemble des sinus de la face, sans épaississement muqueux ni comblement');
        mucosaWritten = true;
      }
      continue;
    }
    if (groupedRisk && risk.some(v => v.id === q.id)) {
      if (!riskWritten) {
        add('Variantes à risque chirurgical',
          'Pas de déhiscence identifiée des lames criblées, lames papyracées et des canaux optiques ou carotidiens, ni de variante à risque parmi les structures chirurgicales évaluées');
        riskWritten = true;
      }
      continue;
    }
    const a = record(answers[q.id]), obs = observations[i];
    if (obs.status === 'non_renseigne') {
      skips.push(q.title + ' : non renseigné'); continue;
    }
    if (obs.status === 'non_evaluable') {
      skips.push(q.title + ' : non évaluable'); continue;
    }
    if (obs.status === 'incertain') {
      skips.push(q.title + ' : incertain'); continue;
    }
    const p = phrase(q, a, obs.status);
    if (p) add(reportingSection(string(q.section), q.title), p,
      obs.status === 'présent');
  }
  const results = Array.from(sections.entries())
    .map(([section, lines]) => section.toUpperCase() + ' :\n' + compactResults(lines).join('\n'))
    .join('\n\n') || '- Aucune observation actuelle confirmée.';
  const allSinusMucosaNegative = groupedMucosa &&
    questions.filter(q => q.section === 'Sinus').every(q => okNegative(q, answers));
  const drainage = questions.filter(q => q.section === 'Voies de drainage');
  const allDrainageNegative = drainage.length >= 2 &&
    drainage.every(q => okNegative(q, answers));
  const anyPositive = observations.some(o => o.status === 'présent');
  const conclusions: string[] = [];
  if (sinus && allSinusMucosaNegative && allDrainageNegative && !anyPositive)
    conclusions.push('Pas d’anomalie inflammatoire des sinus objectivée sur les structures évaluées');
  if (groupedRisk && !anyPositive)
    conclusions.push('Pas de variante significative à risque chirurgical identifiée parmi les éléments évalués');
  if (!conclusions.length)
    conclusions.push('Synthèse radiologique à finaliser après confrontation avec les constatations décrites');
  return {
    indication: clinical.indication,
    technique: clinical.technique || 'Protocole non renseigné.',
    results, conclusion: conclusions.map(minus).join('\n'),
    missing: skips,
    coveredSections: Array.from(sections.keys()),
    fullyNormal: observations.length > 0 &&
      observations.every(o => o.status === 'absent'),
  };
}
