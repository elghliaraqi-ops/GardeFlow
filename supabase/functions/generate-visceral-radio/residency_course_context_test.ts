import {courseContext} from './residency_course_context.ts';
import {generationContract,ficheSchema} from './generation_contract.ts';
function assert(value:unknown,message:string){if(!value)throw new Error(message);}
Deno.test('Resident instructions reach the actual provider input for all four modes',()=>{
  for(const mode of ['fiche','course_qcms','case','case_qcms'] as const){
    const c=generationContract(mode);
    const sent=c.outputInstructions.split('CONTRAT DES IMAGES')[0];
    assert(mode==='fiche'?sent.includes('650 à 1800'):mode==='case'?sent.includes('quatre phases'):sent.includes('course_section_key'), 'mode prescription was cut off: '+mode);
  }
});
Deno.test('Detailed chapter and taught facts are the same course contract',()=>{
  const section=(ficheSchema.properties as any).sections.items;
  assert(section.properties.content.minLength===650,'superficial chapter accepted');
  assert(section.properties.key_points.minItems===4,'chapter needs concrete teaching points');
  const c=generationContract('course_qcms',{count:10});
  const q=(c.schema.properties as any).questions.items;
  assert(q.required.includes('course_section_key')&&q.required.includes('teaching_point'),'question cannot point to its taught concept');
});
Deno.test('QCM input preserves actual facts, keys and complete clinical qualifications',()=>{
  const fact='Drainage possible seulement si patient stable et collection accessible, sans péritonite diffuse.';
  const fiche={title:'Péritonite',sections:Array.from({length:10},(_,i)=>({key:'s'+i,title:'Chapitre '+i,key_points:[fact, 'Deuxième notion expliquée.']}))};
  const first=JSON.parse(courseContext(fiche,3500,0));
  assert(first.sections[1].key==='s1','section key lost');
  assert(first.sections[1].key_points[0]===fact,'clinical qualification clipped');
  const second=JSON.parse(courseContext(fiche,3500,10));
  assert(second.sections.some((s:any)=>s.key==='s7'),'operative teaching omitted from second batch');
  assert(!first.sections.some((s:any)=>s.key==='s9'),'first/second course contexts were not bounded');
});
