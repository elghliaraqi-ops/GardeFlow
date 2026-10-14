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
export function groqBudget(contract:GenerationContract,prompt:string){
 const input=prompt+'\n'+contract.outputInstructions+'\n'+formatGuide[contract.mode];
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
export function normalizeResponse(contract:GenerationContract,result:any){
 if(!object(result))return result;
 const nodes=contract.mode==='fiche'?result.sections:contract.mode==='case'?result.stages:
   (contract.mode==='course_qcms'||contract.mode==='case_qcms')?result.questions:[];
 if(Array.isArray(nodes))for(const node of nodes){
   if(!object(node))continue;
   if(contract.mode==='course_qcms'||contract.mode==='case_qcms')node.reference=referenceText(node.reference);
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
 if((contract.mode==='fiche'||contract.mode==='case')&&result.references==null)result.references=[];
 if(contract.mode==='case'&&typeof result.recommended_qcms==='string'&&/^(10|15|20)$/.test(result.recommended_qcms))
   result.recommended_qcms=Number(result.recommended_qcms);
 return result;
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
   if(typeof schema.minItems==='number'&&value.length<schema.minItems)throw new Error('json_array_short:'+path);
   if(typeof schema.maxItems==='number'&&value.length>schema.maxItems)throw new Error('json_array_long:'+path);
   value.forEach((v:any,i:number)=>validateStructure(schema.items,v,path+'['+i+']'));
 }else if(schema?.type==='string'){
   if(typeof value!=='string')throw new Error('json_string:'+path);
   if(typeof schema.minLength==='number'&&value.length<schema.minLength)throw new Error('json_text_short:'+path);
   if(typeof schema.maxLength==='number'&&value.length>schema.maxLength)throw new Error('json_text_long:'+path);
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
function errorResponse(status:number,body:any,after:string|null){
 if(status===429){const wait=Number(after||0);return Object.assign(new Error('groq_rate_limited'),{
   retryAfterSeconds:Number.isFinite(wait)&&wait>0?Math.min(3600,Math.ceil(wait)):60});}
 if(status===413)return new Error('groq_request_too_large');
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
   {role:'user',content:prompt+'\n'+contract.outputInstructions+'\n'+formatGuide[contract.mode]+
     '\nJSON UNIQUEMENT. Toutes les clés demandées et les comptes imposés, aucun texte hors JSON. Pour les QCM: une phrase clinique précise par option, sans répéter son texte; global_explanation complémentaire en 1-2 phrases. Conserver les nuances et les cinq corrections.'},
 ];
 const fetcher=settings.fetcher??fetch;
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),110000);
 try{
   for(let attempt=0;attempt<2;attempt++){
     const body:any={model,messages:attempt?[...messages,{role:'user',content:'Erreur technique exacte: '+failureReason+'. Le décodage précédent était techniquement invalide. Génère de nouveau un objet JSON complet, avec toutes les clés, tous les chapitres/questions et les explications.'}]:messages,
       reasoning_effort:'low',temperature:0.2,max_completion_tokens:max,stream:false};
     if(attempt===0)body.response_format={type:'json_object'};
     let response:Response;
     try{response=await fetcher(endpoint,{method:'POST',signal:controller.signal,
       headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
       body:JSON.stringify(body)});}
     catch(e){throw new Error(e instanceof DOMException&&e.name==='AbortError'?'groq_timeout':'groq_network_error');}
     const data=await response.json().catch(()=>null);
     if(!response.ok){
       const code=String(data?.error?.code||data?.error?.type||'');
       if(attempt===0&&response.status===400&&/json|schema|validat/i.test(code)){
         console.warn('visceral_json_recovery',{mode:contract.mode,reason:'provider_json_400'});
         continue;
       }
       throw errorResponse(response.status,data,response.headers.get('retry-after'));
     }
     try{
       if(data?.choices?.[0]?.finish_reason==='length')throw new Error('groq_output_token_limit');
       const parsed=normalizeResponse(contract,parseJSON(data?.choices?.[0]?.message?.content));
       validateStructure(contract.schema,parsed);
       return parsed;
     }catch(e){
       failureReason=String((e as Error).message).slice(0,130);
       // A truncated ten-question answer cannot be repaired by repeating it at the same budget.
       // Regenerate two bounded halves, retaining all fifty clinical corrections.
       if(failureReason==='groq_output_token_limit'&&contract.requestedCount===10){
         const qs=(contract.schema as any).properties.questions.items;
         const half=generationContract(contract.mode,{count:5,phases:qs.properties.phase.enum,courseKeys:qs.properties.course_section_key.enum??[]});
         const phases=prompt.match(/séquence obligatoire des phase par question: ([1-4,]+)/)?.[1].split(',');
         const phaseNote=(offset:number)=>phases?' Pour ces cinq questions, phases obligatoires dans cet ordre: '+phases.slice(offset,offset+5).join(',')+'.':'';
         const first=await generateJson(half,prompt+'\nTRANSPORT FRACTIONNÉ PRIORITAIRE: produire seulement les questions 1 à 5 du lot initial, EXACTEMENT 5 questions.'+phaseNote(0),settings);
         const second=await generateJson(half,prompt+'\nTRANSPORT FRACTIONNÉ PRIORITAIRE: produire seulement les questions 6 à 10 du lot initial, EXACTEMENT 5 questions. Ne pas répéter ces énoncés: '+JSON.stringify(first.questions.map((q:any)=>q.statement))+phaseNote(5),settings);
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
