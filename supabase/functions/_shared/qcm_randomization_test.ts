import {shuffleSingleAnswer,shuffleMultipleAnswer} from './qcm_randomization.ts';
function assert(ok:unknown,message:string){if(!ok)throw Error(message);}
Deno.test('single-answer shuffle retains truth and four alternatives',()=>{
  const choices=['Bonne reponse','Distracteur 1','Distracteur 2','Distracteur 3'];
  for(const correctIndex of [0,1,2,3])for(const roll of [0,0.2,0.4,0.8,0.999]){
    const result=shuffleSingleAnswer(choices,correctIndex,()=>roll);
    assert(result.options.length===4&&new Set(result.options).size===4,'invalid option set');
    assert(result.options[result.correctIndex]===choices[correctIndex],'correct answer lost');
    assert(choices.every(x=>result.options.includes(x)),'missing distractor');
  }
});
Deno.test('answer indices are not stuck on A',()=>{
  let seed=903733;
  const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
  const counts=[0,0,0,0];
  for(let i=0;i<4000;i++){
    const result=shuffleSingleAnswer(['Bonne reponse','B','C','D'],0,random);
    counts[result.correctIndex]++;
    assert(result.options[result.correctIndex]==='Bonne reponse','index mismatch');
  }
  for(const count of counts)assert(count>750&&count<1250,'biased: '+counts);
});
Deno.test('multiple-answer shuffle preserves correctness and explanations',()=>{
  const input='ABCDE'.split('').map((key,i)=>({
    key,text:'choix-'+i,correct:i===0||i===3,explanation:'explication-'+i,
  }));
  const output=shuffleMultipleAnswer(input,()=>0.25);
  assert(output.map(x=>x.key).join('')==='ABCDE','wrong labels');
  assert(output.filter(x=>x.correct).length===2,'wrong count of correct choices');
  for(const q of input){
    const found=output.find(x=>x.text===q.text);
    assert(found?.correct===q.correct,'correctness detached');
    assert(found?.explanation===q.explanation,'explanation detached');
  }
  assert(input.map(x=>x.key).join('')==='ABCDE','input mutated');
});
