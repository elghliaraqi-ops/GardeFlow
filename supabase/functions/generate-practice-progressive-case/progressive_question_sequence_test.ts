import {assertEquals,assert} from 'jsr:@std/assert@1';
import {progressiveAxes,progressiveStages,expectedProgressiveAxes,
 validateProgressiveAxisSequence,progressiveJsonContract} from './progressive_question_sequence.ts';

Deno.test('10 distinct chronological axes over 4 stages (2/3/3/2)',()=>{
 assertEquals(progressiveAxes.length,10);
 assertEquals(new Set(progressiveAxes).size,10);
 assertEquals(progressiveStages,[0,0,1,1,1,2,2,2,3,3]);
 assertEquals(progressiveAxes,[
  'symptomes','examen_clinique','hypotheses_diagnostiques',
  'classification_gravite','examens_complementaires',
  'interpretation_diagnostic','decision_therapeutique','conduite_a_tenir',
  'surveillance_revaluation','complications_suivi']);
});
Deno.test('JSON contracts specify the correct five questions per generation call',()=>{
 for(const index of [0,1] as const){
  const contract=progressiveJsonContract(index);
  assert(contract.includes('"qcms"'));
  assert(contract.includes('"correct_index"'));
  assert(contract.includes('"references"'));
  assert(contract.includes('EXACTEMENT cinq objets'));
  const example=contract.split('MODELE_JSON_DEBUT\\n')[1]
    ?.split('\\nMODELE_JSON_FIN')[0];
  assert(example);
  const parsed=JSON.parse(example) as {qcms:{axis:string}[]};
  assertEquals(parsed.qcms.length,5);
  assertEquals(parsed.qcms.map(x=>x.axis),expectedProgressiveAxes(index));
  for(const axis of expectedProgressiveAxes(index))assert(contract.includes(axis));
 }
});
Deno.test('rejects out of sequence even with valid JSON and ten questions',()=>{
 const first=expectedProgressiveAxes(0).map(axis=>({axis}));
 const second=expectedProgressiveAxes(1).map(axis=>({axis}));
 assertEquals(validateProgressiveAxisSequence(first,0),true);
 assertEquals(validateProgressiveAxisSequence(second,1),true);
 assertEquals(validateProgressiveAxisSequence(first,1),false);
 assertEquals(validateProgressiveAxisSequence([...first].reverse(),0),false);
 assertEquals(validateProgressiveAxisSequence(first.slice(0,4),0),false);
});
