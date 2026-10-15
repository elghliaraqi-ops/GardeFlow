import { examTemplate } from './radiology_templates.ts';
import { indicationSemiology, needsSymptomExpansion } from './radiology_semiology.ts';
import { compatibleQuestionSet } from './question_compatibility.ts';
import { structuredReport } from './structured_report.ts';
const assert = (v: unknown, msg: string) => { if (!v) throw Error(msg); };
const matches = (titles: string[], token: RegExp) => titles.some(title => token.test(title));
const titles = (indication: string, sex: 'female'|'male'|'other' = 'male') =>
  examTemplate('TDM','abdomino-pelvien',indication,'injecté',sex)!.questions
    .map(q => q.title.toLowerCase());

Deno.test('right iliac fossa automatically checks appendicitis and mimics', () => {
  const q = titles('Douleur de la fosse iliaque droite, fièvre');
  for (const term of [/appendice/, /périappendiculaire/, /diverticule cæcal/,
      /iléite|iléocæcal/, /épiploïque/, /urétéral/]) {
    assert(matches(q,term), 'Missing differentiator ' + term);
  }
  assert(q[0].includes('appendice'), 'Focused signs prioritized');
  assert(matches(q,/foie/), 'Full anatomic survey also retained');
});

Deno.test('female RLQ includes separate ovarian torsion, hemorrhagic cyst and PID', () => {
  const female = titles('Douleur fosse iliaque droite', 'female');
  assert(matches(female,/ovari|annex/), 'Must evaluate adnexa');
  assert(matches(female,/kyste.*rupture|kyste.*hémorragique/), 'Hemorrhagic cyst');
  assert(matches(female,/salpingite|tubo.ovarien/), 'Pelvic infection');
  assert(matches(female,/utérus/), 'Uterus routine check');
  const male = titles('Douleur fosse iliaque droite', 'male');
  assert(!matches(male,/torsion.*annex|kyste annexiel|abcès tubo/),
    'Do not assume female organs in male anatomical case');
  assert(matches(male,/prostat/), 'Prostate male anatomy');
  const unknown = titles('Douleur fosse iliaque droite', 'other');
  assert(!matches(unknown,/utérus ou des annexes/), 'Unspecified anatomy not presumed');
});

Deno.test('semiology generalizes to different indications and modalities', () => {
  const topics: Array<[string, string, RegExp]> = [
    ['TDM abdomino-pelvien','Douleur fosse iliaque gauche',/diverticule sigmoïdien/],
    ['TDM abdomino-pelvien','Douleur hypochondre droit',/vésicule distendue/],
    ['TDM abdomino-pelvien','Colique néphrétique droite',/calcul sur le trajet urétéral/],
    ['TDM abdomino-pelvien','Douleur abdominale et vomissements',/zone de transition/],
    ['TDM abdomino-pelvien','Ictère',/voies biliaires dilatées/],
    ['TDM thorax','Dyspnée et toux',/opacités alvéolaires/],
    ['TDM encéphale','Céphalées brutales',/foyer hémorragique/],
  ];
  for (const [scope, indication, test] of topics) {
    const plan = indicationSemiology({
      exam:'TDM', region:scope, indication, sex:'female',
      clinical:'', technique:'avec injection',
    });
    assert(plan.matched, 'No syndromic plan for ' + indication);
    assert(plan.entries.some(q => test.test(q[1].toLowerCase())),
      'No differentiating sign for ' + indication);
    const template = examTemplate('TDM',scope,indication,'avec injection','female');
    assert(template && template.questions.some(q => test.test(q.title.toLowerCase())),
      'Indication lost from imaging template ' + scope);
  }
  assert(needsSymptomExpansion('Vertiges positionnels'),
    'Unknown symptom should trigger fallback semio request');
  assert(!indicationSemiology({
    exam:'TDM',region:'encéphale',indication:'Vertiges positionnels',
  }).matched,'Unknown symptom must not appear falsely curated');
});

Deno.test('legacy 12 item symptomatic TAP retains clinical and three anatomic regions', () => {
  const t=examTemplate('TDM','TAP','Douleur fosse iliaque droite','injecté','female')!;
  const limited=compatibleQuestionSet(t.questions,12,'Douleur fosse iliaque droite');
  assert(limited.questions.length===12,'Legacy cap');
  assert(limited.questions.filter(q=>q.section.startsWith('Indication · ')).length>=4,
    'Differential focus mandatory');
  for(const region of ['Thorax','Abdomen','Pelvis']){
    assert(limited.questions.some(q=>q.section.startsWith(region+' · ')),
      region+' still examined');
  }
});

Deno.test('no claims about normal appendix or ovaries when physician did not evaluate', () => {
  const t=examTemplate('TDM','abdomen-pelvis','Douleur FID','injecté','female')!;
  const ctx={
    exam:'TDM', region:'abdomen-pelvis',
    indication:'Douleur FID',technique:'injecté',comparative:false,oldReports:'',
  };
  const answers=Object.fromEntries(t.questions
    .filter(q=>q.section==='Foie et voies biliaires')
    .map(q=>[q.id,{status:'observed',value:'non',notes:''}]));
  const report=structuredReport(ctx,t.questions,answers);
  assert(!report.results.toLowerCase().includes('appendice normal'),
    'Unassessed appendix cannot become normal');
  assert(!report.results.toLowerCase().includes('annexes normales'),
    'Unassessed adnexa cannot become normal');
  assert(report.missing.some(s=>/appendice/.test(s.toLowerCase())),
    'Appendix missing must be surfaced');
});
