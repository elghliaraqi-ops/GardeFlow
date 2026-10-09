import {assertEquals,assert} from 'jsr:@std/assert@1';
import {validateDailyBatch,validCachedDailyQuestion,dailyQcmFingerprint,
 type DailyRef} from './daily_qcm_validation.ts';

const references:DailyRef[]=[
 {title:'Cardiology review',url:'https://europepmc.org/article/MED/111111',
  year:'2026',organization:'Europe PMC',kind:'revue'},
 {title:'Guideline',url:'https://doi.org/10.1000/example',
  year:'2025',organization:'Europe PMC',kind:'recommandation'}
];
function q(i:number):Record<string,unknown>{
 return {question:'Chez le patient du cas fictif '+i+', quel examen est indiqué ?',
  options:['ECG 12 dérivations','Radiographie','Échographie','Numération formule sanguine'],
  correct_index:0,topic:'examen',
  correction:'La décision tient compte des symptômes et de la situation clinique décrite.',
  source_ids:[1],references:[],image_search_query:''};
}
Deno.test('cinq QCM recevables et références résolues uniquement depuis le serveur',()=>{
 const seen=new Set<string>();
 const {accepted,rejected}=validateDailyBatch({qcms:[q(1),q(2),q(3),q(4),q(5)]},
  references,seen);
 assertEquals(accepted.length,5);
 assertEquals(rejected.length,0);
 assertEquals(accepted[0].references[0].url,references[0].url);
 assertEquals(seen.size,5);
});
Deno.test('une question invalide ne détruit pas les quatre autres',()=>{
 const wrong=q(3);wrong.options=['oui','oui','non','peut-être'];
 const {accepted,rejected}=validateDailyBatch(
  {qcms:[q(1),q(2),wrong,q(4),q(5)]},references,new Set());
 assertEquals(accepted.length,4);
 assertEquals(rejected,[{position:3,reason:'duplicate_options'}]);
});
Deno.test('le rechargement et le remplacement des QCM évitent les doublons',()=>{
 const seen=new Set([dailyQcmFingerprint(q(1).question)]);
 const {accepted,rejected}=validateDailyBatch({qcms:[q(1),q(2)]},references,seen);
 assertEquals(accepted.length,1);
 assertEquals(rejected[0].reason,'duplicate_question');
 assertEquals(seen.size,2);
});
Deno.test('sources imaginaires rejetées, identifiants documentés acceptés',()=>{
 const fake={...q(1),source_ids:[42],
   references:[{url:'https://fake.example/unknown'}]};
 const validated=validateDailyBatch({qcms:[fake]},references,new Set());
 assertEquals(validated.accepted.length,0);
 assertEquals(validated.rejected[0].reason,'unverified_source');
 const checked=validateDailyBatch({qcms:[{...fake,source_ids:[2]}]},
  references,new Set());
 assertEquals(checked.accepted.length,1);
 assertEquals(checked.accepted[0].references[0].url,references[1].url);
});
Deno.test('réponses JSON incomplètes restent récupérables',()=>{
 const result=validateDailyBatch({qcms:[q(1),q(2)]},references,new Set());
 assertEquals(result.accepted.length,2);
 assertEquals(result.rejected.length,0);
 assertEquals(validateDailyBatch({garbage:true},references,new Set()).accepted.length,0);
});
Deno.test('checkpoint exige les 4 options et les sources déjà validées',()=>{
 const data={
  question:'Quelles mesures immédiates réaliser chez ce patient ?',
  options:['A','B','C','D'],correct_index:1,topic:'prise_en_charge',
  correction:'Raisonnement détaillé démontrant la prise en charge adaptée.\n\n§SOURCES§\nEurope PMC',
 };
 assert(validCachedDailyQuestion(data));
 assertEquals(validCachedDailyQuestion({...data,options:['A','A','C','D']}),false);
 assertEquals(validCachedDailyQuestion({...data,correction:'Raisonnement explicatif sans bibliographie.'}),false);
});
