import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {dailyQcmFingerprint,validateDailyBatch,validCachedDailyQuestion} from './daily_qcm_validation.ts';
import {medicalEvidencePolicy,findOpenverseMedicalPreview} from './medical_evidence_media.ts';
import {medicalImageSchema,medicalImagePrompt,emptyMedicalImageRequest,medicalImageCorrectionSuffix} from './medical_image_contract.ts';

const topics=['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'];
const specialties=['cardiology','acute abdominal surgery','respiratory medicine','neurology','urology','gastroenterology','emergency medicine','infectious diseases','endocrinology','nephrology','pediatrics','obstetrics','orthopedics','critical care','hematology','dermatology'];
// Prompts and data contract share one count and one set of fields.
const referenceSchema={type:'object',additionalProperties:false,required:['url'],properties:{url:{type:'string'}}};
const itemSchema={type:'object',additionalProperties:false,
 required:['question','options','correct_index','correction','topic','references','source_ids','image_search_query','image_request'],
 properties:{question:{type:'string'},options:{type:'array',minItems:4,maxItems:4,items:{type:'string'}},
  correct_index:{type:'integer',minimum:0,maximum:3},correction:{type:'string'},
  topic:{type:'string',enum:topics},references:{type:'array',minItems:0,maxItems:3,items:referenceSchema},
  source_ids:{type:'array',minItems:1,maxItems:3,items:{type:'integer',minimum:1,maximum:8}},
  image_search_query:{type:'string'},image_request:medicalImageSchema}};
function dailyBatchSchema(count:number){
 return {type:'object',additionalProperties:false,required:['qcms'],
  properties:{qcms:{type:'array',minItems:count,maxItems:count,items:itemSchema}}};
}
function dailyJsonContract(count:number):string{
 const sample={qcms:Array.from({length:count},(_,i)=>({
  question:'REMPLACER par une vraie question médicale '+(i+1),
  options:['Proposition clinique A','Proposition clinique B','Proposition clinique C','Proposition clinique D'],
  correct_index:0,correction:'REMPLACER par une explication clinique conforme aux sources fournies.',
  topic:'examen',references:[],source_ids:[1],image_search_query:'',image_request:emptyMedicalImageRequest}))};
 return 'CONTRAT JSON : '+count+' QCM dans un objet racine contenant uniquement qcms. '+
  'Champs exacts pour chaque QCM : '+Object.keys(itemSchema.properties).join(', ')+'. '+
  'references peut être [] car source_ids (1 à 3 indices de la bibliographie vérifiée) suffit. '+
  'Quatre options distinctes, correct_index entre 0 et 3, topic parmi '+topics.join('/')+
  '. Ne jamais recopier les placeholders. Exemple JSON valide : '+JSON.stringify(sample)+
  '. '+medicalImagePrompt+' Aucun Markdown, préambule ni champ supplémentaire.';
}

type Ref={title:string;url:string;year:string;organization:string;kind:string};
function plain(value:unknown,max=2500):string {
 return String(value??'').replace(/<[^>]+>/g,' ').replace(/[\x00-\x1f]/g,' ').replace(/\s+/g,' ').trim().slice(0,max);
}
function canon(value:unknown):string {
 try{const u=new URL(String(value??''));return u.protocol==='https:'?u.origin+u.pathname.replace(/\/+$/,''):'';}catch{return '';}
}
function cleanKey(value:string):string {return value.toLowerCase().replace(/\s+/g,' ').trim();}
function numericSeed(s:string):number {let v=2166136261;for(const c of s){v^=c.charCodeAt(0);v=Math.imul(v,16777619);}return v>>>0;}
function cors(req:Request):HeadersInit {return {'Access-Control-Allow-Origin':req.headers.get('Origin')??'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};}
function send(req:Request,obj:Record<string,unknown>,status=200):Response {
 return new Response(JSON.stringify(obj),{status,headers:{...cors(req),'Content-Type':'application/json','Cache-Control':'no-store'}});
}
function casablancaDay():string {
 const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Casablanca',day:'2-digit',month:'2-digit',year:'numeric'}).formatToParts(new Date());
 const v=Object.fromEntries(parts.map(x=>[x.type,x.value]));
 return v.year+'-'+v.month+'-'+v.day;
}
async function literature(specialty:string):Promise<Ref[]> {
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),12000);
 try{
 const qs=new URLSearchParams({query:specialty+' AND (guideline OR consensus OR review OR recommendation)',format:'json',resultType:'core',pageSize:'20'});
 const res=await fetch('https://www.ebi.ac.uk/europepmc/webservices/rest/search?'+qs,{signal:ctrl.signal});
 if(!res.ok)return [];
 const data=await res.json() as {resultList?:{result?:Record<string,unknown>[]}};
 const found=new Map<string,Ref>();
 for(const item of data.resultList?.result??[]){
 const title=plain(item.title,350),doi=String(item.doi??''),pmid=String(item.pmid??'');
 const url=/^10\.\d{4,9}\//i.test(doi)?'https://doi.org/'+doi:/^\d+$/.test(pmid)?'https://europepmc.org/article/MED/'+pmid:'';
 const key=canon(url);if(!key||!title||found.has(key))continue;
 const titleLower=title.toLowerCase();
 found.set(key,{title,url,year:plain(item.pubYear,12),organization:plain(item.journalTitle||'Europe PMC',160),
 kind:/guideline|recommendation/.test(titleLower)?'recommandation':/consensus/.test(titleLower)?'consensus':'revue'});
 }return [...found.values()].slice(0,14);
 }catch{return [];}finally{clearTimeout(timer);}
}
async function commons(query:string):Promise<{name:string;url:string;source:string}|null> {
 if(!query.trim())return null;
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),6000);
 try{
 const q=new URLSearchParams({action:'query',format:'json',origin:'*',generator:'search',gsrsearch:plain(query,130),gsrnamespace:'6',gsrlimit:'2',prop:'imageinfo',iiprop:'url',iiurlwidth:'600'});
 const r=await fetch('https://commons.wikimedia.org/w/api.php?'+q,{signal:ctrl.signal});
 if(!r.ok)return null;
 const data=await r.json() as {query?:{pages?:Record<string,{title?:string;imageinfo?:{thumburl?:string;descriptionurl?:string}[]}>}};
 for(const page of Object.values(data.query?.pages??{})){
 const img=page.imageinfo?.[0],url=String(img?.thumburl??''),source=String(img?.descriptionurl??'');
 try{if(new URL(url).protocol==='https:'&&new URL(url).hostname==='upload.wikimedia.org'&&new URL(source).protocol==='https:'&&new URL(source).hostname==='commons.wikimedia.org')
 return {name:plain(page.title,140),url,source};}catch{continue;}
 }return null;
 }catch{return null;}finally{clearTimeout(timer);}
}


const batchSchema={type:'object',additionalProperties:false,required:['qcms'],
 properties:{qcms:{type:'array',minItems:5,maxItems:5,items:itemSchema}}};
// QCM schema is now supplied dynamically via dailyBatchSchema(missing).

async function newGroqBatch(
 prompt:string,format:Record<string,unknown>,overrideModel?:string,timeoutMs=30000
):Promise<Record<string,unknown>> {
 const key=Deno.env.get('GROQ_API_KEY');
 if(!key)throw Error('groq_configuration_missing');
 // Prefer smaller model to reduce token consumption; one backup attempt per batch.
 const configured=(Deno.env.get('GROQ_DAILY_MODEL')??'').trim();
 const model=overrideModel??(
  ['openai/gpt-oss-20b','openai/gpt-oss-120b'].includes(configured)
   ?configured:'openai/gpt-oss-20b');
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),Math.min(30000,Math.max(8000,timeoutMs)));
 try{
  const response=await fetch('https://api.groq.com/openai/v1/chat/completions',{
   method:'POST',signal:ctrl.signal,
   headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
   body:JSON.stringify({
    model,messages:[{role:'user',content:prompt}],
    temperature:0.12,reasoning_effort:'low',reasoning_format:'hidden',
    max_completion_tokens:5400,stream:false,
    // Strict json_schema caused Groq json_validate_failed 400 in production.
    response_format:{type:'json_object'}
   })
  });
  if(!response.ok){
   const raw=await response.json().catch(()=>null);
   const reason=String(raw?.error?.code??raw?.error?.type??'').slice(0,65);
   console.warn('daily_groq_http',{status:response.status,model,reason,retry_after:response.headers.get('retry-after')??''});
   if(response.status===401||response.status===403)throw Error('groq_auth_failed');
   if(response.status===429)throw Error('groq_rate_limited');
   if(response.status>=500)throw Error('groq_provider_unavailable');
   throw Error('groq_request_rejected');
  }
  const raw=await response.json().catch(()=>null);
  const content=raw?.choices?.[0]?.message?.content;
  if(typeof content==='string'){
   try{
    const parsed=JSON.parse(content);
    if(parsed&&typeof parsed==='object'&&!Array.isArray(parsed))return parsed;
   }catch{/* Object mode can occasionally still be invalid. */}
  }
  throw Error('groq_invalid_json');
 }catch(err){
  const e=err instanceof Error?err:Error('groq_network_error');
  if(e.name==='AbortError')throw Error('groq_timeout');
  if(['groq_auth_failed','groq_rate_limited','groq_provider_unavailable',
    'groq_request_rejected','groq_invalid_json'].includes(e.message))throw e;
  console.warn('daily_groq_exception',{model,code:'network_error'});
  throw Error('groq_network_error');
 }finally{clearTimeout(timer);}
}

async function checkAndFormat(batch:Record<string,unknown>,refs:Ref[],seen:Set<string>)
 :Promise<Record<string,unknown>[]>{
 const result=validateDailyBatch(batch,refs,seen);
 for(const reason of result.rejected)
  console.warn('daily_ai_question_rejected',reason);
 // Image visuals are retrieved only when the learner opens a correction.
 // Never preselect a random book cover or persist image URLs in the QCM.
 return result.accepted.map(item=>{
  const urls='\n\n§SOURCES§\n'+item.references
    .map(r=>[r.kind,r.title,r.organization,r.year,r.url].join('|||')).join('\n');
  return {
    question:item.question,options:item.options,correct_index:item.correct_index,
    topic:item.topic,
    correction:item.correction+medicalImageCorrectionSuffix(item.image_request,item.illustration_query)+urls
  };
 });
}

Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors(req)});
 if(req.method!=='POST')return send(req,{ok:false,error:'method_not_allowed'},405);
 const allowed=(Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS')??'').split(',').map(x=>x.trim()).filter(Boolean);
 const origin=req.headers.get('Origin')??'';
 if(origin&&allowed.length&&!allowed.includes(origin))return send(req,{ok:false,error:'origin_not_allowed'},403);
 const auth=req.headers.get('Authorization')??'';
 if(!auth.startsWith('Bearer '))return send(req,{ok:false,error:'auth_required'},401);
 const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!anon||!service)return send(req,{ok:false,error:'config_missing'},503);
 const caller=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:userData,error:authErr}=await caller.auth.getUser();
 const uid=userData.user?.id;if(authErr||!uid)return send(req,{ok:false,error:'auth_failed'},401);
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:profile}=await admin.from('profiles').select('id,account_status').eq('id',uid).maybeSingle();
 if(!profile||profile.account_status!=='active')return send(req,{ok:false,error:'account_inactive'},403);
 const body=await req.json().catch(()=>null);
 const mode=String(body?.mode??'');
 if(mode!=='cours_ia')return send(req,{ok:false,error:'daily_challenge_ai_only'},400);
 const date=casablancaDay();
 const existing=await admin.from('practice_daily_challenges').select('challenge_date').eq('challenge_date',date).eq('mode',mode).maybeSingle();
 if(existing.data)return send(req,{ok:true,ready:true,day:date,mode,generated:false});
 if(existing.error)return send(req,{ok:false,error:'database_unavailable'},503);

 const claim=await admin.rpc('practice_daily_generation_claim',{p_day:date,p_mode:mode});
 if(claim.error)return send(req,{ok:false,error:'generation_guard_unavailable'},503);
 if(claim.data!==true)return send(req,{ok:false,error:'generation_in_progress',retryable:true},202);
 try {
   let questions:Record<string,unknown>[]=[];
   let caseTitle='',caseStem='';
   let caseStages:{title:string;narrative:string}[]=[];
   const specialty=specialties[numericSeed(date+mode)%specialties.length];
   const refs=await literature(specialty);
   if(!refs.length)throw Error('literature_unavailable');
   const refList=refs.slice(0,8).map((r,i)=>`[${i+1}] ${r.title} | ${r.year} | ${r.url}`).join('\n');
   const common=medicalEvidencePolicy+'\nSOURCES NUMÉROTÉES VÉRIFIÉES :\n'+refList+
    '\nChaque question est inédite, niveau internat, avec correction détaillée (3-5 phrases) '+ 
    'fondée sur ces sources et sans données personnelles. '+ 
    'image_search_query en anglais si une image externe aide, sinon vide.\n'+medicalImagePrompt+'\n';
   // A shared date-scoped checkpoint keeps good AI questions after a transient failure.
   const {data:checkpoint,error:checkpointReadError}=
    await admin.from('practice_daily_generation_batches')
      .select('batch_index,questions')
      .eq('challenge_date',date).eq('mode',mode);
   if(checkpointReadError){
    console.warn('daily_checkpoint_read_failed',{code:checkpointReadError.code});
    throw Error('checkpoint_unavailable');
   }
   const seen=new Set<string>();
   const runtimeDeadline=Date.now()+102000;
   if(mode==='cours_ia'){
    for(let index=0;index<2;index++){
     const goal=index===0?'Diagnostic, démarche clinique, examens et interprétation.':
      'Traitements, décisions, recommandations, complications et suivi.';
     const existingBatch=(checkpoint??[]).find(x=>x.batch_index===index);
     const rawCached=Array.isArray(existingBatch?.questions)?existingBatch.questions:[];
     const accepted:Record<string,unknown>[]=[];
     for(const q of rawCached){
      if(!validCachedDailyQuestion(q))continue;
      const fingerprint=dailyQcmFingerprint(q.question);
      if(seen.has(fingerprint))continue;
      seen.add(fingerprint);
      accepted.push(q);
      if(accepted.length>=5)break;
     }
     if(accepted.length>0)
      console.info('daily_batch_checkpoint_loaded',{batch:index+1,count:accepted.length});
     let batchError='generation_failed';
     for(let attempt=0;attempt<3&&accepted.length<5;attempt++){
      const available=runtimeDeadline-Date.now();
      if(available<11000)throw Error('generation_time_budget');
      const missing=5-accepted.length;
      const prompt='Crée EXACTEMENT '+missing+
       ' QCM IA NOUVEAUX de cours, niveau internat, en français, discipline '+specialty+
       '. Lot '+(index+1)+'/2. '+goal+
       ' Ne répète aucune de ces questions déjà conservées : '+
       [...questions,...accepted].map(q=>String(q.question)).join(' / ')+'. '+
       common+'\n'+dailyJsonContract(missing);
      const firstModel=(Deno.env.get('GROQ_DAILY_MODEL')??'').trim();
      const backup=firstModel==='openai/gpt-oss-120b'
       ?'openai/gpt-oss-20b':'openai/gpt-oss-120b';
      const selectedModel=attempt===1?backup:undefined;
      try{
       const response=await newGroqBatch(prompt,dailyBatchSchema(missing),selectedModel,
        Math.min(30000,available-2000));
       const candidateSeen=new Set(seen);
       const replacement=await checkAndFormat(response,refs,candidateSeen);
       for(const q of replacement){
        if(accepted.length>=5)break;
        const fingerprint=dailyQcmFingerprint(q.question);
        if(seen.has(fingerprint))continue;
        seen.add(fingerprint);
        accepted.push(q);
       }
       if(accepted.length>0){
        const {error:saveError}=await admin.from('practice_daily_generation_batches')
         .upsert({challenge_date:date,mode,batch_index:index,questions:accepted,
          updated_at:new Date().toISOString()},{onConflict:'challenge_date,mode,batch_index'});
        if(saveError){
         console.warn('daily_checkpoint_write_failed',{code:saveError.code});
         throw Error('checkpoint_unavailable');
        }
       }
       if(accepted.length<5)
        batchError='invalid_generated_questions';
       else batchError='';
      }catch(err){
       batchError=err instanceof Error?err.message:'generation_failed';
       console.warn('daily_ai_batch_retry',{batch:index+1,attempt:attempt+1,
        accepted:accepted.length,code:batchError});
       if(['groq_auth_failed','groq_configuration_missing',
        'checkpoint_unavailable'].includes(batchError))throw err;
       if(batchError==='groq_rate_limited'&&attempt>=1)break;
      }
     }
     if(accepted.length!==5)throw Error(batchError||'invalid_generated_questions');
     questions.push(...accepted);
    }
   }
   if(questions.length!==10)throw Error('invalid_question_count');
   const inserted=await admin.from('practice_daily_challenges').upsert({challenge_date:date,mode,case_title:caseTitle,case_stem:caseStem,case_stages:caseStages,questions},{onConflict:'challenge_date,mode',ignoreDuplicates:true});
   if(inserted.error)throw Error('database_write_failed');
   return send(req,{ok:true,ready:true,day:date,mode,generated:true});
 }catch(e){
   const error=e instanceof Error?e.message:'generation_failed';
   console.warn('practice_daily_ai_failure',{code:error,mode,date});
   return send(req,{ok:false,error,retryable:!['groq_auth_failed','groq_configuration_missing'].includes(error)},503);
 }finally{
   await admin.from('practice_daily_generation_claims').delete().eq('challenge_date',date).eq('mode',mode);
 }
});
