import { historyRiskSemiology } from './radiology_history.ts';
import { indicationSemiology } from './radiology_semiology.ts';
import { examTemplate } from './radiology_templates.ts';
import { compatibleQuestionSet } from './question_compatibility.ts';
import { structuredReport } from './structured_report.ts';

const assert=(yes:unknown,msg:string)=>{if(!yes)throw new Error(msg);};
const ctx=(clinical: string, indication='Douleur fosse iliaque droite', technique='TDM injectée temps portal')=>({
  exam:'TDM',region:'abdomen-pelvis',indication,clinical,technique,sex:'female' as const,
});
Deno.test('known ACFA independently checks mesenteric embolism and renal/splenic infarctions',()=>{
  const risk=historyRiskSemiology(ctx('ACFA connue depuis 2019, sous anticoagulants'));
  assert(risk.matched,'Recognize cardiac fibrillation');
  const titles=risk.entries.map(x=>x[1].toLowerCase()).join(' | ');
  for(const term of ['artère mésentérique supérieure','rehaussement des parois intestinales',
    'pneumatose','splénique','rénale','artères rénales']) {
    assert(titles.includes(term),'Missing history-driven sign: '+term);
  }
  const all=indicationSemiology(ctx('ACFA connue depuis 2019, sous anticoagulants'));
  assert(all.symptomMatched&&all.historyMatched,'Combine history + symptom, do not replace either');
  assert(all.entries.some(x=>/appendice/i.test(x[1])),'Appendicitis differential retained');
  assert(all.entries.some(x=>/splénique/.test(x[1])),'Splenic infarction retained');
  assert(all.entries.some(x=>/rénale/.test(x[1])),'Renal infarction retained');
  assert(all.entries.some(x=>/tubo-ovarien/.test(x[1])),'Gynaecologic mimic retained');
});
Deno.test('history adds embolic checks even without any named abdominal symptom',()=>{
  const result=indicationSemiology(ctx('ACFA connue','Bilan général'));
  assert(result.historyMatched,'Risk matched independently');
  assert(!result.symptomMatched,'Do not fabricate a symptom in indication');
  const t=examTemplate('TDM','abdomen-pelvis','Bilan général',
    'acquisition injectée', 'male','ACFA connue');
  assert(t?.questions.some(q=>/artère mésentérique supérieure/i.test(q.title)),
    'Embolic SMA signs included in routine CT');
});
Deno.test('risk clues are limited to anatomical examination field',()=>{
  const t=examTemplate('TDM','encéphale','Céphalées','sans injection','male','ACFA connue');
  assert(t && !t.questions.some(q=>q.section.startsWith('Antécédents · Reins')),
    'Do not request renal CT findings on a head CT');
  const other=historyRiskSemiology({
    exam:'IRM',region:'abdomen-pelvis',indication:'douleur',clinical:'ACFA',
  });
  assert(!other.matched,'Do not present CT-specific criteria as MRI findings');
});
Deno.test('generic histories can trigger single Groq risk expansion',()=>{
  const unknown=indicationSemiology(ctx('Antécédent de diabète compliqué', 'Douleur fosse iliaque droite'));
  assert(unknown.symptomMatched,'Known FID symptom');
  assert(unknown.historyFlagged && !unknown.historyMatched,
    'The unknown history needs a context-risk expansion even when the symptom is known');
});
Deno.test('old 12-question TAP includes ACFA, appendix and all scanned regions',()=>{
  const t=examTemplate('TDM','TAP','Douleur FID','injection temps portal','female',
    'ACFA connue')!;
  const old=compatibleQuestionSet(t.questions,12,'Douleur FID');
  assert(old.questions.length===12,'Legacy question limit');
  assert(old.questions.some(q=>q.section.startsWith('Antécédents · ')),
    'Do not lose ACFA risks');
  assert(old.questions.some(q=>q.section.startsWith('Indication · ')),
    'Do not lose appendice');
  for(const r of ['Thorax','Abdomen','Pelvis'])
    assert(old.questions.some(q=>q.section.startsWith(r+' · ')),
      'Do not lose '+r+' territory');
});
Deno.test('omitting the infarction questions cannot produce normal perfusion statement',()=>{
  const t=examTemplate('TDM','abdomen-pelvis','Douleur FID','temps portal','female',
    'ACFA connue')!;
  const ans=Object.fromEntries(t.questions
    .filter(q=>q.section==='Foie et voies biliaires')
    .map(q=>[q.id,{status:'observed',value:'non',notes:''}]));
  const report=structuredReport({
    exam:'TDM',region:'abdomen-pelvis',indication:'Douleur FID',
    technique:'temps portal',comparative:false,oldReports:'',
  },t.questions,ans);
  assert(!/pas de défaut de perfusion splénique|pas de défaut de perfusion rénale/i.test(report.results),
    'Do not assert unassessed organ perfusion');
  assert(report.missing.some(q=>/artère mésentérique supérieure|splénique/.test(q)),
    'Missing cardiovascular territory must be surfaced');
});
