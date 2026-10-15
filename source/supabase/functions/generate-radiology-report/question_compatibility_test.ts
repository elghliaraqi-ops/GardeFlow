import { clientQuestionCapacity, compatibleQuestionSet } from './question_compatibility.ts';
import { examTemplate } from './radiology_templates.ts';

const assert = (v: unknown, msg: string) => { if (!v) throw new Error(msg); };
Deno.test('legacy clients receive a valid <= 12 question sinus plan', () => {
  const template = examTemplate('TDM','sinus','anosmie bilan base du crâne ethmoïde','sans injection');
  assert(template, 'Sinus template present');
  assert(template!.questions.length > 12, 'Full medical checklist has > 12 questions');
  const limited = compatibleQuestionSet(
    template!.questions, clientQuestionCapacity(undefined),
    'anosmie bilan base du crâne ethmoïde',
  );
  assert(limited.truncated, 'Legacy response flagged as limited');
  assert(limited.available === template!.questions.length, 'Total known');
  assert(limited.questions.length === 12, 'Legacy Flutter <= 12 requirement');
  assert(limited.questions.some(q => /cribl/i.test(q.title)), 'Olfactory base priority retained');
  assert(limited.questions[0].title.includes('maxillaire'), 'Systematic first question retained');
  assert(limited.questions.every((q,i) => q.id === 'q' + (i+1)), 'Sequential ids for responses');
});
Deno.test('modern clients receive all 17 sinus questions including surgical variants', () => {
  const template = examTemplate('TDM','sinus','anosmie','sans injection');
  assert(template,'Sinus template present');
  const compatible = compatibleQuestionSet(template!.questions,clientQuestionCapacity(48),'anosmie');
  assert(!compatible.truncated,'No truncation in modern app');
  assert(compatible.questions.length === template!.questions.length,'Full list preserved');
  assert(compatible.questions.some(q => /carotidiens/i.test(q.title)), 'Last risk signs retained');
});
Deno.test('comparison always remains in final legacy series', () => {
  const template = examTemplate('TDM','sinus','bilan','sans injection')!;
  const qs = [...template.questions, {
    ...template.questions[0], id: 'q' + (template.questions.length+1),
    section: 'Comparaison',title:'Evolution des lésions anciennes ?',
  }];
  const limited = compatibleQuestionSet(qs,12,'bilan',true);
  assert(limited.questions.length === 12,'Legacy count');
  assert(limited.questions.at(-1)?.section === 'Comparaison','Comparison never silently dropped');
});
Deno.test('capacity cannot be forced above documented safety cap', () => {
  assert(clientQuestionCapacity(48) === 48,'Modern capacity');
  assert(clientQuestionCapacity(500) === 48,'Maximum capacity');
  assert(clientQuestionCapacity('48') === 12,'Non-numeric bypass rejected');
  assert(clientQuestionCapacity(1) === 12,'Invalid minimum fallback');
  assert(clientQuestionCapacity(null) === 12,'Legacy default');
  assert(clientQuestionCapacity(NaN) === 12,'NaN rejected');
});
