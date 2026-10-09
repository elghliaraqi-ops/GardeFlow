import {
  generationContract, qcmSchema, ficheSchema, caseSchema,
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
Deno.test('all four generator prompts and schemas enforce the same image-selection contract',()=>{
  for(const mode of ['fiche','course_qcms','case','case_qcms'] as const){
    const contract=generationContract(mode);
    const instructions=contract.outputInstructions;
    let images:any;
    if(mode==='fiche')images=field(field(ficheSchema,'sections').items,'image_requests');
    else if(mode==='case')images=field(field(caseSchema,'stages').items,'image_requests');
    else images=field(field(qcmSchema(10,[1,2,3,4]),'questions').items,'image_requests');
    const props=Object.keys(images.items.properties);
    for(const key of [
      'query','modality','purpose','image_type','anatomy',
      'plane','required_features','excluded_features',
    ]){
      assert(props.includes(key),mode+' schema missing '+key);
      assert(instructions.includes(key),mode+' prompt missing '+key);
    }
    const types=images.items.properties.image_type.enum;
    for(const type of ['anatomical_diagram','radiology_scan','operative_diagram','clinical_photo']){
      assert(types.includes(type),mode+' missing image type '+type);
      assert(instructions.includes(type),mode+' missing visual selection rule '+type);
    }
    assert(images.items.additionalProperties===false,'extraneous image URL must not be allowed');
  }
});
