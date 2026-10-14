import {
  generationContract, qcmSchema, ficheSchema, caseSchema, expandQcmImages,
} from './generation_contract.ts';

function assert(ok: unknown, message: string) {
  if (!ok) throw new Error(message);
}
function field(schema: any, key: string): any { return schema.properties[key]; }
function checkRequiredObjects(value: any, at = 'root') {
  if (Array.isArray(value)) { value.forEach((v,i)=>checkRequiredObjects(v, at+'['+i+']')); return; }
  if (!value || typeof value !== 'object') return;
  if (value.type === 'object') {
    const keys=Object.keys(value.properties ?? {});
    assert(value.additionalProperties===false, at+' must forbid extra keys');
    assert(JSON.stringify(value.required)===JSON.stringify(keys), at+' must require all keys');
  }
  for (const [k,v] of Object.entries(value)) checkRequiredObjects(v, at+'.'+k);
}
for (const [mode, count, phases] of [
  ['fiche', 0, []], ['course_qcms',10,[1]], ['case',0,[]],
  ['case_qcms',10,[1,2,3,4]], ['case_qcms',5,[3,4]],
] as const) {
  Deno.test(mode+' '+count+' shared prompt/JSON contract',()=>{
    const c=generationContract(mode,{count:count || undefined,phases:[...phases]});
    checkRequiredObjects(c.schema);
    assert(c.name.startsWith('visceral_radio_'),'expected Groq format name');
    const keys=Object.keys((c.schema as any).properties);
    keys.forEach(k=>assert(c.outputInstructions.includes(k),'prompt missed JSON root key '+k));
    if(count) {
      const qs=field(c.schema,'questions');
      assert(qs.minItems===count&&qs.maxItems===count,'count must be exact in schema');
      assert(c.outputInstructions.includes('EXACTEMENT '+count+' questions'),'prompt count mismatch');
      const opts=field(qs.items,'options');
      assert(opts.minItems===5&&opts.maxItems===5,'exactly five options');
      const allowed=field(qs.items,'phase').enum;
      assert(JSON.stringify(allowed)===JSON.stringify([...new Set(phases)]),'phase enum mismatch');
      const cat=field(qs.items,'category').enum;
      for (const name of ['chirurgie','radiologie','technique_operatoire']) assert(cat.includes(name),'category missing');
    }
  });
}
Deno.test('Fiche / clinical case section count align',()=>{
  assert(field(ficheSchema,'sections').minItems===10,'fiche sections must be 10');
  assert(field(ficheSchema,'sections').maxItems===10,'fiche sections max must be 10');
  assert(field(caseSchema,'stages').minItems===4,'clinical phases must be 4');
  assert(field(caseSchema,'stages').maxItems===4,'clinical phases max must be 4');
});
Deno.test('Invalid batch size cannot reach Groq',()=>{
  for(const count of [0,7,15,20]){
    let failed=false;
    try {qcmSchema(count,[1]);}catch(_){failed=true;}
    assert(failed,'must reject batch of '+count);
  }
});
Deno.test('20 course questions in 10+10 and 15 clinical questions in 10+5',()=>{
  for(const [target,expected] of [[20,[10,10]],[15,[10,5]],[10,[10]]] as const){
    const batches=[] as number[];
    let offset=0;
    while(offset<target){const count=Math.min(10,target-offset);batches.push(count); offset+=count;}
    assert(JSON.stringify(batches)===JSON.stringify(expected),'wrong batch splitting for '+target);
    for(const count of batches)qcmSchema(count,[1,2,3,4]);
  }
});
Deno.test('QCM Groq image schema stays compact, expanded contract supports previews',()=>{
  const schema=(qcmSchema(10,[1]) as any).properties.questions.items.properties.image_requests.items;
  const fields=Object.keys(schema.properties);
  assert(JSON.stringify(fields)===JSON.stringify(['query','modality','purpose','image_type','plane','required_features']),'compact image fields');
  const items:any[]=[{image_requests:[{query:'CT free air',modality:'CT',purpose:'pneumoperitoneum',image_type:'radiology_scan',plane:'axial',required_features:['free air']}]},{image_requests:[]}];
  expandQcmImages(items);
  assert(items[0].image_requests[0].preferred_sources[0]==='Radiology Assistant','source order');
  assert(items[0].image_requests[0].allow_article_figures,'external image previews');
  assert(items[1].image_requests.length===0,'no fabricated image');
});

Deno.test('Fiche de reference residanat : standards pedagogiques conserves',()=>{
  const contract=generationContract('fiche');
  const instruction=contract.outputInstructions;
  for(const needle of [
    'Cours de RÉSIDANAT','EXACTEMENT 10 sections',
    'rapports anatomiques','physiopathologie','clinique et gravité',
    'protocole imagerie','classifications','indications et alternatives',
    'étapes opératoires','complications et surveillance',
    'synthèse décisionnelle','4 à 6 key_points','study_core',
  ]) assert(instruction.includes(needle),'Reference-quality fiche contract regressed: '+needle);
  const section=(ficheSchema.properties as any).sections.items;
  assert(section.properties.content.minLength===650,'Course chapters must stay substantial');
  assert(section.properties.key_points.minItems===4,'Detailed taught points required');
  assert((ficheSchema.properties as any).sections.minItems===10,'Ten chapters required');
});

Deno.test('QCM de cours et de cas : profondeur residanat sans schema additionnel',()=>{
  const course=generationContract('course_qcms',{count:10});
  const clinical=generationContract('case_qcms',{count:10});
  const standard=['NIVEAU RÉSIDANAT STRICT','décisions cliniques','radiologiques et opératoires','critères discriminants','gravité et terrain','complications et surveillance','Chaque option A–E'];
  for(const contract of [course,clinical]){
    for(const needle of standard)assert(contract.outputInstructions.includes(needle),contract.mode+' level instruction missing '+needle);
    const question=(contract.schema.properties as any).questions;
    assert(question.minItems===10&&question.maxItems===10,contract.mode+' must retain ten questions');
    const options=question.items.properties.options;
    assert(options.minItems===5&&options.maxItems===5,contract.mode+' must retain five explained options');
  }
  // Ce verrou pédagogique ne doit pas ajouter de champs au JSON ou modifier
  // le format technique qui vient d'être stabilisé.
  const courseWithDifferentPrompt=generationContract('course_qcms',{count:10});
  assert(JSON.stringify(course.schema)===JSON.stringify(courseWithDifferentPrompt.schema),'QCM schema unstable');
});
