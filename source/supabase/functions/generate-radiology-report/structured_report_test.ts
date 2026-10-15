import { examTemplate, isTapCt } from './radiology_templates.ts';
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


Deno.test('scanner TAP full anatomy: shorthand and French variants cover 3 regions', () => {
  const variants: Array<[string, string]> = [
    ['TDM', 'TAP'],
    ['Scanner', 'thoraco-abdomino-pelvien'],
    ['TDM TAP', 'Thorax'],
    ['TDM', 'thorax abdomen pelvis'],
    ['TDM', 'T.A.P.'],
    ['Scanner', 'thoraco-abdomino-pelvienne'],
  ];
  for (const [exam, region] of variants) {
    assert(isTapCt(exam, region), 'TAP recognition failed for ' + exam + ' / ' + region);
    const t = examTemplate(exam, region, 'bilan oncologique', 'injecté');
    assert(t?.key === 'tap_ct', 'Unexpected template for ' + region);
    const categories = t!.questions.map(q => q.section);
    assert(categories.some(s => s.startsWith('Thorax · ')), 'Thorax missed');
    assert(categories.some(s => s.startsWith('Abdomen · ')), 'Abdomen missed');
    assert(categories.some(s => s.startsWith('Pelvis · ')), 'Pelvis missed');
    assert(t!.questions.length >= 22 && t!.questions.length <= 48,
      'Complete high-yield TAP checklist expected');
    assert(t!.questions.every((q,i) => q.id === 'q'+(i+1)), 'Sequential ids');
    assert(t!.questions.every(q => q.definition && q.criteria.length &&
      q.reference_query && q.normal_text), 'Definition, criteria, illustration for each sign');
    const sections = categories.join(' | ');
    assert(sections.indexOf('Thorax · ') < sections.indexOf('Abdomen · '),
      'Chest before abdomen');
    assert(sections.indexOf('Abdomen · ') < sections.indexOf('Pelvis · '),
      'Abdomen before pelvis');
  }
  assert(examTemplate('TDM','thorax','bilan',
    'Acquisition thoraco-abdomino-pelvienne injectée')?.key === 'tap_ct',
    'Current protocol explicitly declaring TAP must cover all three regions');
  assert(!isTapCt('TDM','Thorax'), 'Thorax alone must remain chest-only');
  assert(!isTapCt('TDM','abdomen-pelvis'), 'Abdominal CT must not invent chest');
  assert(!isTapCt('Radiographie','thoraco-abdomino-pelvien'),
    'Radiograph is not a CT');
  assert(examTemplate('TDM','thorax')?.key === 'chest_ct', 'Chest CT retained');
  assert(examTemplate('TDM','abdomen-pelvis')?.key === 'abdomen_ct',
    'Abdomino-pelvic CT retained');
});
Deno.test('scanner TAP report: 3 verified regions appear; skipped pelvis is not normal', () => {
  const t = examTemplate('TDM','TAP','bilan oncologique','injecté')!;
  const allChecked = Object.fromEntries(t.questions.map(q => [
    q.id, {status: 'observed',value: 'non',notes: ''},
  ]));
  const ctx = {
    exam:'TDM', region:'TAP', indication:'Bilan oncologique',
    technique:'Acquisition thoraco-abdomino-pelvienne injectée',
    comparative:false, oldReports:'',
  };
  const normal = structuredReport(ctx, t.questions, allChecked);
  assert(normal.results.includes('THORAX · '), 'Thoracic section missing');
  assert(normal.results.includes('ABDOMEN · '), 'Abdominal section missing');
  assert(normal.results.includes('PELVIS · '), 'Pelvic section missing');
  const pelvisSkipped = Object.fromEntries(t.questions.map(q => [
    q.id, q.section.startsWith('Pelvis · ')
      ? {status: 'unanswered',value: '',notes: ''}
      : {status: 'observed',value: 'non',notes: ''},
  ]));
  const incomplete = structuredReport(ctx, t.questions, pelvisSkipped);
  assert(!incomplete.results.includes('PELVIS · '),
    'Never fabricate normal pelvic findings if not assessed');
  assert(!incomplete.fullyNormal, 'Incomplete assessment must not be normal');
  assert(incomplete.missing.some(s => /vésic|pelvien/i.test(s)),
    'Skipped pelvic structures must be explicitly identified');
});


Deno.test('professional radiology prose: objective sentences, exact findings and no status inventory', () => {
  const t = examTemplate('TDM', 'abdomino-pelvien', 'Douleur fosse iliaque droite',
    'Acquisition injectée en phase portale', 'female', 'ACFA connue')!;
  const question = (token: RegExp) => {
    const found = t.questions.find(q => token.test(q.title));
    assert(found, 'Required targeted sign not found: ' + token);
    return found!;
  };
  const app = question(/^Appendice dilaté/);
  const renal = question(/Plage splénique périphérique/);
  const hep = question(/^Lésion focale hépatique/);
  const bile = question(/^Dilatation des voies biliaires/);
  const answers = {
    [app.id]: {
      status: 'observed', value: 'oui',
      notes: 'Appendice mesurant 11 mm de diamètre, à paroi épaissie, avec infiltration de la graisse périappendiculaire en fosse iliaque droite.',
    },
    [renal.id]: { status: 'not_evaluable', value: '', notes: '' },
    [hep.id]: { status: 'observed', value: 'non', notes: '' },
    [bile.id]: { status: 'observed', value: 'non', notes: '' },
  };
  const r = structuredReport({
    exam:'TDM',region:'abdomino-pelvien',
    indication:'Douleur fosse iliaque droite',technique:'phase portale',
    comparative:false,oldReports:'',
  },t.questions,answers);
  assert(r.results.includes('Appendice mesurant 11 mm de diamètre'),
    'Physician full sentence and exact measurements must be used verbatim');
  assert(r.results.includes('infiltration de la graisse périappendiculaire'),
    'Localisation and actual finding preserved');
  assert(r.results.includes('FOIE ET VOIES BILIAIRES'),
    'Anatomical organ heading used');
  const liverLines = r.results.split('FOIE ET VOIES BILIAIRES :')[1].split('\n\n')[0]
    .split('\n').filter(x => x.startsWith('- '));
  assert(liverLines.length === 1,
    'Two verified normal liver and bile observations must combine into one coherent paragraph');
  assert(!/:\s*(présent|absent|oui|non)\b/i.test(r.results),
    'Never show machine-status inventory in final clinical report');
  assert(!r.results.includes('Plage splénique périphérique'),
    'Non-evaluable infarction must not become normal or positive in the report');
  assert(r.missing.some(x => x.includes('splénique')),
    'Unavailable perfusion still appears in quality warnings');
  assert(!r.results.includes('ANTÉCÉDENTS ·') && !r.results.includes('INDICATION ·'),
    'Teaching categories must not appear as report organ headings');
});

Deno.test('partial report with a positive sign and brief measurement is readable', () => {
  const t=examTemplate('TDM','sinus de la face','Rhinorrhée','sans injection')!;
  const q=t.questions.find(q=>/épaississement muqueux ou comblement frontal/i.test(q.title))!;
  const r=structuredReport({
    exam:'TDM',region:'sinus',indication:'Rhinorrhée',
    technique:'sans injection',comparative:false,oldReports:'',
  },t.questions,{
    [q.id]:{status:'observed',value:'oui',notes:'sinus frontal droit, épaisseur 3 mm'},
  });
  assert(r.results.toLowerCase().includes('sinus frontal droit, épaisseur 3 mm'),
    'Keep short exact measurements and lateralization');
  assert(!/signe\s*:\s*présent/i.test(r.results),
    'No status-led question transcript');
  assert(!r.results.includes('Bonne aération de l’ensemble des sinus'),
    'Positive finding must preclude falsely broad normality');
});
