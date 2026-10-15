import { examTemplate } from './radiology_templates.ts';
import { structuredReport } from './structured_report.ts';
function assert(v: unknown, msg: string) { if (!v) throw Error(msg); }
function sinus() {
  const t = examTemplate('TDM', 'sinus de la face', 'Obstruction nasale',
    'Acquisition sans injection, reconstructions multiplanaires');
  assert(t && t.key === 'sinus', 'Scanner des sinus must use curated checklist');
  return t!;
}
Deno.test('sinus CT: routine anatomy before rare lesions, complete surgical checklist', () => {
  const t = sinus(), qs = t.questions;
  assert(qs.length >= 14 && qs.length <= 24, 'Systematic coverage expected');
  assert(qs[0].section === 'Sinus', 'Start with sinus parenchyma');
  assert(qs[0].title.toLowerCase().includes('maxillaire'), 'Maxillary first');
  const names = qs.map(x => x.title.toLowerCase()).join(' | ');
  for (const x of ['ostio', 'muqueu', 'cloison', 'concha', 'dentaire', 'criblée',
    'papyracée', 'carotidiens', 'optiques']) {
    assert(names.includes(x), 'Missing standard feature: ' + x);
  }
  assert(!names.includes('ostéome mucoïde'), 'Do not make up rare entities');
  assert(qs.every(q => q.normal_text && q.criteria.length &&
    q.section && q.reference_query), 'Every sign must have criteria and radiological normal phrasing');
});
Deno.test('normal sinus checklist: idiomatic structured report, not X: absent inventory', () => {
  const t = sinus();
  const answers = Object.fromEntries(t.questions.map(q => [
    q.id, { status: 'observed', value: 'non', notes: '' },
  ]));
  const report = structuredReport({
    exam: 'TDM', region: 'sinus de la face', indication: 'Obstruction nasale',
    technique: 'Sans injection de produit de contraste iodé.',
    comparative: false, oldReports: '',
  }, t.questions, answers);
  const result = report.results;
  for (const x of ['SINUS :','VOIES DE DRAINAGE :','FOSSES NASALES :',
    'PAROIS OSSEUSES :','VARIANTES À RISQUE CHIRURGICAL :',
    'Bonne aération de l’ensemble des sinus', 'Complexes ostioméataux libres',
    'Pas de matériel dentaire']) {
    assert(result.includes(x), 'Missing normal report phrase or heading: ' + x);
  }
  assert(result.indexOf('SINUS :') < result.indexOf('VOIES DE DRAINAGE :'),
    'Anatomical order must be stable');
  assert(result.indexOf('FOSSES NASALES :') < result.indexOf('VARIANTES À RISQUE CHIRURGICAL :'),
    'Risk variants follow routine sinuses and nasal cavity');
  assert(!/: absent\b/i.test(result), 'Reject dry absent inventory');
  assert(!/ostéome mucoïde|mucocèle|fracture du plancher/i.test(result),
    'Routine findings should not be diluted with irrelevant rare lesions');
  assert(report.conclusion.includes('Pas d’anomalie inflammatoire'),
    'Comprehensive negative sinus assessment supports normal conclusion');
});
Deno.test('partial examination: do not write normality for unassessed anatomy', () => {
  const t = sinus();
  const answers = {
    [t.questions[0].id]: {status:'observed',value:'non',notes:''},
    [t.questions[1].id]: {status:'observed',value:'oui',notes:'sinus frontal droit, 3 mm'},
  };
  const report = structuredReport({
    exam:'TDM',region:'sinus',indication:'Céphalées',technique:'sans injection',
    comparative:false,oldReports:'',
  },t.questions,answers);
  assert(!report.results.includes('Bonne aération de l’ensemble des sinus'),
    'Cannot generalize normality from one negative answer');
  assert(report.results.includes('sinus frontal droit, 3 mm'),
    'Positive finding and measurement must be preserved');
  assert(!report.results.includes('Complexes ostioméataux libres'),
    'Unassessed ostia cannot be declared patent');
  assert(!report.conclusion.includes('Pas d’anomalie inflammatoire'),
    'Unassessed inflammatory structures forbid broad normal conclusion');
  assert(report.missing.length > 10, 'Missing anatomical items must stay visible');
});
Deno.test('indication modifies checklist only after mandatory routine reading', () => {
  const t = examTemplate('Scanner', 'sinus', 'Traumatisme facial', 'sans injection');
  assert(t && t.questions.length > sinus().questions.length,
    'Trauma adds specifically relevant fracture question');
  assert(t!.questions[0].section === 'Sinus', 'Routine systematic reading remains first');
  assert(t!.questions.at(-1)?.title.includes('Fracture traumatique'),
    'Trauma gets targeted question after systematic anatomy');
});
Deno.test('modality and acquisition guide selection of true evaluable questions', () => {
  assert(examTemplate('IRM','encéphale','céphalées','sans injection')?.questions
    .every(q => q.section !== 'Rehaussement'),
    'No contrast question if MRI explicitly unenhanced');
  assert(examTemplate('IRM','encéphale','bilan','avec injection de gadolinium')?.questions
    .some(q => q.section === 'Rehaussement'),
    'Contrast question when gadolinium acquired');
  assert(examTemplate('TDM','thorax','toux','sans injection')?.questions
    .some(q => q.section === 'Parenchyme pulmonaire'),
    'CT chest must have lung parenchyma');
  assert(examTemplate('TDM','abdomen-pelvis','douleurs','injecté')?.questions
    .some(q => q.section === 'Tube digestif'),
    'Abdominal CT must assess digestive tract');
  assert(examTemplate('radiographie','thorax','dyspnée','')?.questions
    .some(q => q.section === 'Plèvres'),
    'CXR must assess pleura');
  assert(examTemplate('échographie','abdomen','douleur','')?.questions
    .some(q => q.section === 'Voies biliaires'),
    'Abdominal ultrasound must assess bile ducts');
});

Deno.test('sinus air-fluid level prevents global normal aeration shortcut', () => {
  const t = sinus();
  const answers = Object.fromEntries(t.questions.map(q => [q.id, {
    status: 'observed', value: 'non', notes: '',
  }]));
  const liquid = t.questions.find(q => /niveau hydro.aérique/i.test(q.title));
  assert(liquid, 'Sinus standard checklist includes air-fluid level');
  answers[liquid!.id] = {status: 'observed', value: 'oui', notes: 'sinus maxillaire gauche'};
  const report = structuredReport({
    exam:'TDM', region:'sinus', indication:'Rhinorrhée', technique:'sans injection',
    comparative:false, oldReports:'',
  }, t.questions, answers);
  assert(!report.results.includes('Bonne aération de l’ensemble des sinus'),
    'Positive sinus fluid contraindicates global aeration normality');
  assert(report.results.includes('sinus maxillaire gauche'),
    'Positive fluid and laterality must remain');
  assert(!report.conclusion.includes('Pas d’anomalie inflammatoire'),
    'Do not conclude normality when abnormal fluid observed');
});
