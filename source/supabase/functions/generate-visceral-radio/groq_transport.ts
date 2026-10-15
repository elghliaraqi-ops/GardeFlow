import {generationContract, type GenerationContract} from './generation_contract.ts';

// One Groq request normally; only technical JSON failures get one alternate attempt.
// No medical second opinion, independent reviewer, or fabricated result.
type Fetcher=typeof fetch;
type Options={apiKey?:string;model?:string;fetcher?:Fetcher};
const endpoint='https://api.groq.com/openai/v1/chat/completions';
const profiles={
 fiche:{desired:5900,min:3600},
 course_qcms:{desired:5600,min:3200},
 case_qcms:{desired:5600,min:3200},
 case:{desired:3800,min:1800},
 surgical_techniques:{desired:1800,min:650},
};
const formatGuide={
 fiche:'JSON title,summary,sections:[10 objects {key,title,content,key_points,image_requests}],operative_techniques:[{name,indications,steps}],study_core,references. Content: 650-900 caractères explicatifs/ch., 4-6 faits expliqués/ch., 10-20 faits study_core. 1-3 techniques, 4-6 étapes. image_requests=[] sauf image utile.',
 case:'JSON title,patient,difficulty,recommended_qcms,stages:[4 objects {phase,title,narrative,clinical_findings,imaging_findings,decisions,image_requests}],final_diagnosis,learning_points,references.',
 course_qcms:'JSON questions:[N objects {phase,category,statement,course_section_key,teaching_point,options:[{key:"A",text,correct,explanation},... jusqu’à E],global_explanation,reference,image_requests}]. Les cinq explications par question sont cliniques.',
 case_qcms:'JSON questions:[N objects {phase,category,statement,course_section_key,teaching_point,options:[{key:"A",text,correct,explanation},... jusqu’à E],global_explanation,reference,image_requests}]. Même patient, phases chronologiques.',
 surgical_techniques:'JSON operative_techniques:[1 à 3 objects {name,indications,steps:[4 à 6 étapes]}].',
};
// Derive the actual provider instructions from the same schema used by validation.
// Groq GPT-OSS supports strict schema decoding. Keep prose requirements in the prompt,
// and send a decoder-safe subset of the same validation schema.
export function schemaShape(schema:any):string {
 if(Array.isArray(schema.enum))return schema.enum.map((v:any)=>JSON.stringify(v)).join('|');
 if(schema.type==='object')return '{'+Object.entries(schema.properties??{}).map(([k,v])=>k+':'+schemaShape(v)).join(',')+'}';
 if(schema.type==='array')return '['+schemaShape(schema.items)+']'+
   (schema.minItems===schema.maxItems&&typeof schema.minItems==='number'?' x'+schema.minItems:
    ' ('+(schema.minItems??0)+'..'+(schema.maxItems??'n')+')');
 return schema.type+(schema.type==='string'&&(schema.minLength||schema.maxLength)?
   '('+(schema.minLength??0)+'..'+(schema.maxLength??'n')+' caractères)':'');
}
// Constrained decoding supports only a subset of JSON Schema. We still validate
// the complete original schema locally (including exact batch sizes).
export function strictDecoderSchema(schema:any):any {
 const base:any={type:schema.type};
 if(Array.isArray(schema.enum))base.enum=schema.enum;
 if(schema.type==='object'){
   const properties=schema.properties??{};
   base.properties=Object.fromEntries(Object.entries(properties).map(([key,value])=>[key,strictDecoderSchema(value)]));
   base.required=Object.keys(properties);
   base.additionalProperties=false;
 }else if(schema.type==='array')base.items=strictDecoderSchema(schema.items);
 return base;
}
export function formatInstructions(contract:GenerationContract):string {
 return formatGuide[contract.mode]+'\nTYPES ET VALEURS OBLIGATOIRES (notation descriptive, retourner un vrai objet JSON): '+
   schemaShape(contract.schema)+'. Chaque champ est requis; string signifie texte, jamais objet/tableau. Aucun champ supplémentaire.';
}
export function groqBudget(contract:GenerationContract,prompt:string){
 const input=prompt+'\n'+contract.outputInstructions+'\n'+formatInstructions(contract);
 const inputEstimate=Math.ceil((input.length+390)/3.6)+220;
 const cfg=profiles[contract.mode];
 const five=contract.requestedCount===5;
 const desired=five?3300:cfg.desired, minimum=five?1750:cfg.min;
 const budget=Math.min(desired,7900-inputEstimate);
 if(budget<minimum)throw new Error('groq_request_too_large');
 return budget;
}
function object(x:any):x is Record<string,any>{return x!==null&&typeof x==='object'&&!Array.isArray(x);}
/** Preserve supplied citation text; never invent a source for missing metadata. */
export function referenceText(value:unknown):string {
 if(typeof value==='string')return value.trim();
 if(value==null)return '';
 if(Array.isArray(value))return value.map(referenceText).filter(Boolean).join(' ; ');
 if(object(value)){
   return [...new Set(['title','citation','text','source','authors','year','url','doi']
     .map(k=>typeof value[k]==='string'?value[k].trim():k==='year'&&typeof value[k]==='number'?String(value[k]):'')
     .filter(Boolean))].join(' — ');
 }
 return '';
}
// Lossless presentation conversion: retain supplied labels, values and units.
// No inference, clinical completion or replacement of an absent patient.
export function clinicalText(value:unknown):string {
 if(typeof value==='string')return value;
 if(value===null)return 'null';
 if(Array.isArray(value))return value.map(clinicalText).join(' ; ');
 if(object(value))return Object.entries(value).map(([k,v])=>k+': '+clinicalText(v)).join(' ; ');
 return String(value);
}
function normalizeShape(schema:any,value:any):any {
 if(value==null)return value;
 if(schema.type==='string'&&(object(value)||Array.isArray(value)))return clinicalText(value);
 if(schema.type==='array'&&Array.isArray(value))return value.map(v=>normalizeShape(schema.items,v));
 if(schema.type==='object'&&object(value))return Object.fromEntries(Object.entries(schema.properties??{})
   .filter(([k])=>k in value).map(([k,v])=>[k,normalizeShape(v,value[k])]));
 return value;
}
function label(value:unknown):string {return String(value??'').normalize('NFD').replace(/\p{M}/gu,'').toLowerCase().trim();}
export function normalizeResponse(contract:GenerationContract,result:any){
 if(!object(result))return result;
 if(contract.mode==='case'){
   const difficulty=label(result.difficulty);
   const aliases:Record<string,string>={intermediate:'intermediaire',intermediaire:'intermediaire',moderate:'intermediaire',complex:'complexe',complexe:'complexe',difficult:'complexe',simple:'simple',easy:'simple'};
   if(aliases[difficulty])result.difficulty=aliases[difficulty];
 }
 // Keep the requested prefix of an overproduced batch; validate every retained question.
 // A surplus must not spend another provider request or erase a complete usable batch.
 if((contract.mode==='course_qcms'||contract.mode==='case_qcms')&&
    contract.requestedCount&&Array.isArray(result.questions)&&result.questions.length>contract.requestedCount)
   result.questions=result.questions.slice(0,contract.requestedCount);
 const nodes=contract.mode==='fiche'?result.sections:contract.mode==='case'?result.stages:
   (contract.mode==='course_qcms'||contract.mode==='case_qcms')?result.questions:[];
 if(Array.isArray(nodes))for(const [index,node] of nodes.entries()){
   if(!object(node))continue;
   if(contract.mode==='course_qcms'||contract.mode==='case_qcms'){
     node.reference=referenceText(node.reference);
     // Category is only a display label, never a correctness decision.
     const category=label(node.category);
     if(/radiolog|imag|scan|irm|tdm/.test(category))node.category='radiologie';
     else if(/techni|operat/.test(category))node.category='technique_operatoire';
     else if(/chirurg|surg/.test(category))node.category='chirurgie';
     if(node.category==null||node.category==='')node.category='non_classe';
     if(contract.mode==='course_qcms')node.phase=1;
     else if(contract.phaseSequence)node.phase=contract.phaseSequence[index];
   }
   if(node.image_requests==null)node.image_requests=[];
   if(Array.isArray(node.image_requests))node.image_requests=node.image_requests.slice(0,1).map((v:any)=>{
     if(!object(v))return v;
     const aliases:Record<string,string>={transverse:'axial',transversal:'axial',frontal:'coronal',sagittale:'sagittal',coronale:'coronal',multiple:'multiplanar',none:'not_applicable','n/a':'not_applicable',na:'not_applicable'};
     const plane=String(v.plane??'').trim().toLowerCase();
     v.plane=aliases[plane]??plane;
     const keys=['query','modality','purpose','image_type','plane','required_features'];
     return Object.fromEntries(keys.map(k=>[k,k==='required_features'?(v[k]??[]):v[k]]).filter(([_,value])=>value!==undefined));
   }).filter((v:any)=>object(v)&&['axial','sagittal','coronal','multiplanar','not_applicable'].includes(v.plane)&&['anatomical_diagram','radiology_scan','operative_diagram','clinical_photo'].includes(v.image_type)&&typeof v.query==='string'&&typeof v.modality==='string'&&typeof v.purpose==='string'&&Array.isArray(v.required_features)&&v.required_features.every((f:any)=>typeof f==='string'));
   if(Array.isArray(node.options))node.options.forEach((v:any,i:number)=>{
     if(object(v)&&i<5)v.key='ABCDE'[i];
   });
   if(typeof node.phase==='string'&&/^[1-4]$/.test(node.phase))node.phase=Number(node.phase);
 }
 if(contract.mode==='fiche'||contract.mode==='case')result.references=
   result.references==null?[]:(Array.isArray(result.references)?result.references:[result.references]).map(referenceText).filter(Boolean);
 if(contract.mode==='case'&&typeof result.recommended_qcms==='string'&&/^(10|15|20)$/.test(result.recommended_qcms))
   result.recommended_qcms=Number(result.recommended_qcms);
 return normalizeShape(contract.schema,result);
}
/** Technical validation only, using the existing contract unchanged. */
export function validateStructure(schema:any,value:any,path='$'):void{
 if(schema?.type==='object'){
   if(!object(value))throw new Error('json_object:'+path);
   const names=Object.keys(schema.properties||{});
   for(const k of schema.required||[])if(!(k in value))throw new Error('json_missing:'+path+'.'+k);
   if(schema.additionalProperties===false)for(const k of Object.keys(value))if(!names.includes(k))
     throw new Error('json_extra:'+path+'.'+k);
   for(const k of names)if(k in value)validateStructure(schema.properties[k],value[k],path+'.'+k);
 }else if(schema?.type==='array'){
   if(!Array.isArray(value))throw new Error('json_array:'+path);
   const exactStructure=/\.(questions|options|sections|stages)$/.test(path);
   const minimum=exactStructure?schema.minItems:(schema.minItems>0?1:0);
   if(typeof minimum==='number'&&value.length<minimum)throw new Error('json_array_short:'+path);
   if(exactStructure&&typeof schema.maxItems==='number'&&value.length>schema.maxItems)throw new Error('json_array_long:'+path);
   value.forEach((v:any,i:number)=>validateStructure(schema.items,v,path+'['+i+']'));
 }else if(schema?.type==='string'){
   if(typeof value!=='string')throw new Error('json_string:'+path);
   // Character targets guide writing; they are not structural validity or medical quality.
   // Never discard a complete response and spend another quota solely on prose length.
   if(!value.trim()&&/\.(content|statement|global_explanation|teaching_point|text|explanation|patient|narrative|final_diagnosis|title|name|indications)$/.test(path))throw new Error('json_text_empty:'+path);
 }else if(schema?.type==='integer'&&!Number.isInteger(value))throw new Error('json_integer:'+path);
 else if(schema?.type==='boolean'&&typeof value!=='boolean')throw new Error('json_boolean:'+path);
 if(Array.isArray(schema?.enum)&&!schema.enum.includes(value))throw new Error('json_enum:'+path);
}
export function parseJSON(text:unknown){
 if(typeof text!=='string'||!text.trim())throw new Error('groq_empty_response');
 let raw=text.trim();
 if(raw.startsWith('\x60\x60\x60')){
   raw=raw.replace(new RegExp('^\\x60{3}(?:json)?\\s*','i'),'')
     .replace(new RegExp('\\s*\\x60{3}$'),'').trim();
 }
 if(!raw.startsWith('{')){
   const start=raw.indexOf('{'),end=raw.lastIndexOf('}');
   if(start>=0&&end>start)raw=raw.slice(start,end+1);
 }
 try{const value=JSON.parse(raw);if(object(value))return value;}catch(_){}
 throw new Error('groq_invalid_json_response');
}
export function quotaInfo(body:any,headers:Headers){
 const message=String(body?.error?.message??'');
 const scope=/tokens per day|tokens.*\(TPD\)/i.test(message)?'tokens_per_day':
   /tokens per minute|tokens.*\(TPM\)/i.test(message)?'tokens_per_minute':
   /requests per day|requests.*\(RPD\)/i.test(message)?'requests_per_day':
   /requests per minute|requests.*\(RPM\)/i.test(message)?'requests_per_minute':'unknown';
 const after=headers.get('retry-after');
 let seconds=after&&Number.isFinite(Number(after))?Number(after):after?Math.max(0,(Date.parse(after)-Date.now())/1000):NaN;
 if(!Number.isFinite(seconds)){
   const retry=message.match(/try again in\s+([0-9.hms\s]+)/i)?.[1];
   if(retry){seconds=0;for(const m of retry.matchAll(/(\d+(?:\.\d+)?)\s*(h|m|s)/g))seconds+=Number(m[1])*({h:3600,m:60,s:1}[m[2]]??1);}
 }
 return {retryAfterSeconds:Number.isFinite(seconds)&&seconds>0?Math.min(86400,Math.ceil(seconds)):null,quotaScope:scope};
}
function errorResponse(status:number,body:any,headers:Headers){
 if(status===429)return Object.assign(new Error('groq_rate_limited'),quotaInfo(body,headers));
 // Groq can use HTTP 413 for exhausted token quotas, not only large requests.
 if(status===413){
   const reason=String(body?.error?.code??'')+' '+String(body?.error?.type??'')+' '+String(body?.error?.message??'');
   if(/rate_limit_exceeded|quota|tokens per (?:minute|day)|\bTP[MD]\b/i.test(reason))
     return Object.assign(new Error('groq_rate_limited'),quotaInfo(body,headers));
   return new Error('groq_request_too_large');
 }
 const code=String(body?.error?.code||body?.error?.type||'unknown_error').slice(0,90);
 return new Error('groq_http_'+status+':'+code);
}
export async function generateJson(
 contract:GenerationContract,prompt:string,settings:Options={}
):Promise<any>{
 const key=settings.apiKey??Deno.env.get('GROQ_API_KEY');
 if(!key)throw new Error('groq_key_missing');
 const model=settings.model??(settings.fetcher?'openai/gpt-oss-120b':Deno.env.get('GROQ_TEXT_MODEL')??'openai/gpt-oss-120b');
 if(!['openai/gpt-oss-120b','openai/gpt-oss-20b'].includes(model))
   throw new Error('groq_model_without_json_support');
 const max=groqBudget(contract,prompt);
 let failureReason='';
 const messages=[
   {role:'system',content:'Professeur en chirurgie viscérale et radiologie, niveau résidanat. Réponds exclusivement avec un objet JSON valide. Conserve les nuances cliniques et sources réelles.'},
   {role:'user',content:prompt+'\n'+contract.outputInstructions+'\n'+formatInstructions(contract)+
     '\nJSON UNIQUEMENT. Toutes les clés demandées et les comptes imposés, aucun texte hors JSON. Pour les QCM: une phrase clinique précise par option, sans répéter son texte; global_explanation complémentaire en 1-2 phrases. Conserver les nuances et les cinq corrections.'},
 ];
 const fetcher=settings.fetcher??fetch;
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),110000);
 try{
   for(let attempt=0;attempt<2;attempt++){
     const body:any={model,messages:attempt?[...messages,{role:'user',content:'Erreur technique exacte: '+failureReason+'. Le décodage précédent était techniquement invalide. Génère de nouveau un objet JSON complet, avec toutes les clés, tous les chapitres/questions et les explications.'}]:messages,
       reasoning_effort:'low',temperature:0.2,max_completion_tokens:max,stream:false};
     // Never fall back to unconstrained prose: a 400 from JSON-object mode
     // previously led to free text and then groq_invalid_structured_output.
     body.response_format=attempt===0
       ?{type:'json_schema',json_schema:{name:contract.name,strict:true,schema:strictDecoderSchema(contract.schema)}}
       :{type:'json_object'};
     let response:Response;
     try{response=await fetcher(endpoint,{method:'POST',signal:controller.signal,
       headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
       body:JSON.stringify(body)});}
     catch(e){throw new Error(e instanceof DOMException&&e.name==='AbortError'?'groq_timeout':'groq_network_error');}
     const data=await response.json().catch(()=>null);
     if(!response.ok){
       const code=String(data?.error?.code||data?.error?.type||'');
       const providerMessage=String(data?.error?.message??'');
       if(attempt===0&&response.status===400&&/json|schema|validat|response_format/i.test(code+' '+providerMessage)){
         console.warn('visceral_json_recovery',{mode:contract.mode,reason:'provider_schema_400',provider_code:code.slice(0,70)});
         continue;
       }
       if(response.status===429)console.warn('visceral_groq_quota',{mode:contract.mode,...quotaInfo(data,response.headers)});
       throw errorResponse(response.status,data,response.headers);
     }
     try{
       if(data?.choices?.[0]?.finish_reason==='length')throw new Error('groq_output_token_limit');
       const parsed=normalizeResponse(contract,parseJSON(data?.choices?.[0]?.message?.content));
       validateStructure(contract.schema,parsed);
       if(Array.isArray(parsed.questions)&&parsed.questions.some((q:any)=>!q.options.some((o:any)=>o.correct===true)))
         throw new Error('json_no_correct_option');
       return parsed;
     }catch(e){
       failureReason=String((e as Error).message).slice(0,130);
       // A truncated ten-question answer cannot be repaired by repeating it at the same budget.
       // Regenerate two bounded halves, retaining all fifty clinical corrections.
       if(contract.requestedCount===10&&
          (contract.mode==='course_qcms'||contract.mode==='case_qcms')&&
          (failureReason==='groq_output_token_limit'||
           failureReason==='groq_invalid_json_response'||
           failureReason==='groq_empty_response'||
           failureReason.startsWith('json_array_short:$.questions')||
           failureReason.startsWith('json_array:$.questions'))){
         // A malformed ten-QCM JSON is often a truncated output even after finish=stop.
         // On success there is still just one provider call. Split only on failure.
         console.warn('visceral_qcm_bounded_recovery',{mode:contract.mode,reason:failureReason});
         const qs=(contract.schema as any).properties.questions.items;
         const half=(offset:number)=>generationContract(contract.mode,{
           count:5,
           phases:contract.phaseSequence?.slice(offset,offset+5)??qs.properties.phase.enum,
           courseKeys:qs.properties.course_section_key.enum??[],
         });
         const phases=(offset:number)=>contract.phaseSequence
           ?' Phases obligatoires de ces cinq questions: '+contract.phaseSequence.slice(offset,offset+5).join(',')+'.'
           :'';
         const first=await generateJson(half(0),prompt+'\nTRANSPORT FRACTIONNÉ: produire uniquement questions 1 à 5, exactement cinq questions.'+phases(0),settings);
         const second=await generateJson(half(5),prompt+'\nTRANSPORT FRACTIONNÉ: produire uniquement questions 6 à 10, exactement cinq questions. Éviter les doublons: '+JSON.stringify(first.questions.map((q:any)=>q.statement))+phases(5),settings);
         const combined={questions:[...first.questions,...second.questions]};
         validateStructure(contract.schema,combined);
         return combined;
       }
       if(attempt===0){
         console.warn('visceral_json_recovery',{mode:contract.mode,reason:String((e as Error).message).slice(0,130)});
         continue;
       }
       console.warn('visceral_json_rejected',{mode:contract.mode,reason:String((e as Error).message).slice(0,130)});
       throw new Error('groq_invalid_structured_output');
     }
   }
   throw new Error('groq_invalid_structured_output');
 }finally{clearTimeout(timeout);}
}
