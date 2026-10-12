import { assertNewStatements, courseBatchPlan } from './qcm_batch_plan.ts';
Deno.test('Two course batches have twenty distinct objectives', () => {
  const first = courseBatchPlan(0,10).split('\n');
  const second = courseBatchPlan(10,10).split('\n');
  if(first.length!==10 || second.length!==10 || new Set([...first,...second]).size!==20)
    throw new Error('invalid course plan');
  if(!second[0].includes('réanimation') || !second[9].includes('suivi'))
    throw new Error('second batch must advance to treatment and follow-up');
});
Deno.test('Duplicates cannot be saved across or within a batch', () => {
  for(const [previous,generated] of [
    [[{statement:'Quel examen choisir ?'}],[{statement:'QUEL examen choisir?'}]],
    [[],[{statement:'Péritonite : quel examen ?'},{statement:'Peritonite, quel examen?'}]],
    [[],[{statement:'   '}]],
  ]) {
    let rejected=false;
    try {assertNewStatements(previous,generated);} catch {rejected=true;}
    if(!rejected)throw new Error('duplicate accepted');
  }
  assertNewStatements([{statement:'Diagnostic initial ?'}],[{statement:'Surveillance postopératoire ?'}]);
});
