import {createClient} from 'npm:@supabase/supabase-js@2.57.4';

const topics=['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'];
const specialties=['cardiology','acute abdominal surgery','respiratory medicine','neurology','urology','gastroenterology','emergency medicine','infectious diseases','endocrinology','nephrology','pediatrics','obstetrics','orthopedics','critical care','hematology','dermatology'];
const referenceSchema={type:'object',additionalProperties:false,required:['url'],properties:{url:{type:'string'}}};
const itemSchema={type:'object',additionalProperties:false,required:['question','options','correct_index','correction','topic','references','image_search_query'],
 properties:{question:{type:'string'},options:{type:'array',minItems:4,maxItems:4,items:{type:'string'}},correct_index:{type:'integer',minimum:0,maximum:3},
 correction:{type:'string'},topic:{type:'string',enum:topics},references:{type:'array',minItems:1,maxItems:3,items:referenceSchema},image_search_query:{type:'string'}}};
const schema={type:'object',additionalProperties:false,required:['case_title','case_stem','case_stages','qcms'],
 properties:{case_title:{type:'string'},case_stem:{type:'string'},case_stages:{type:'array',minItems:4,maxItems:4,items:{type:'object',additionalProperties:false,required:['title','narrative'],properties:{title:{type:'string'},narrative:{type:'string'}}}},qcms:{type:'array',minItems:10,maxItems:10,items:itemSchema}}};
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
 if(!['cours','cas_clinique'].includes(mode))return send(req,{ok:false,error:'invalid_mode'},400);
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
   if(mode==='cours'){
     const {data:qcms,error}=await admin.from('clinical_case_qcms')
       .select('id,post_id,question,options,correct_index,correction,topic')
       .eq('generation_source','openai').order('id').limit(500);
     if(error||!qcms||qcms.length<10)throw Error('qcm_bank_unavailable');
     const pool=qcms.map(q=>({...q,seed:numericSeed(date+':'+String(q.id))})).sort((a,b)=>a.seed-b.seed);
     const selected=[] as typeof pool, seen=new Set<string>();
     for(const q of pool){if(!seen.has(q.post_id)){selected.push(q);seen.add(q.post_id);}if(selected.length===10)break;}
     if(selected.length!==10)throw Error('qcm_bank_insufficient');
     questions=selected.map(q=>({question:q.question,options:q.options,correct_index:q.correct_index,correction:q.correction,topic:q.topic}));
   }else{
     const groq=Deno.env.get('GROQ_API_KEY');
     if(!groq)throw Error('groq_unavailable');
     const specialty=specialties[numericSeed(date)%specialties.length];
     const refs=await literature(specialty);
     if(!refs.length)throw Error('literature_unavailable');
     const mapped=new Map(refs.map(r=>[canon(r.url),r]));
     const referenceList=refs.map(r=>[r.kind,r.title,r.organization,r.year,r.url].join(' | ')).join('\n');
     const prompt='Crée un SEUL cas clinique FICTIF complet et totalement inventé, en français, dans la spécialité '+specialty+
      '. Le cas doit avoir une anamnèse, un examen clinique, un bilan biologique et/ou radiologique, et une évolution pédagogique. '+
      'Il sert de fil rouge à EXACTEMENT 10 QCM progressifs. Fournis QUATRE étapes à révéler dans cet ordre : '+
      '(1) Admission / symptômes et examen clinique : QCM 1 et 2 ; '+
      '(2) Investigations (biologie, ECG/imagerie, résultats) : QCM 3, 4 et 5 ; '+
      '(3) Décision thérapeutique / priorités : QCM 6, 7 et 8 ; '+
      '(4) Évolution, complications et suivi : QCM 9 et 10. '+
      'Retourne case_stages tableau de quatre objets avec pour chaque étape un récit autonome de 100 mots environ et un title. '+
      'STRICTEMENT AUCUN SPOILER : le récit étape 1 n’annonce aucun examen futur, résultat, diagnostic final, prise en charge ou issue. '+
      'Les QCM de chaque étape utilisent UNIQUEMENT les informations déjà révélées dans celle-ci ou avant. '+
      'Pour chaque QCM: 4 réponses possibles, une seule exacte, correction IA claire de 3-6 phrases, et 1-3 citations avec URL recopiées EXACTEMENT de la liste Europe PMC. '+
      'Ne donne JAMAIS d’informations sur un vrai patient et n’imagine pas de sources. Les images sont facultatives : image_search_query en ANGLAIS si une radio, ECG, TDM, scanner ou schéma aiderait, sinon chaîne vide. '+ 
      'case_title court; case_stem est un dossier fictif complet, cohérent et suffisamment détaillé. '+
      'QUESTION / NIVEAU : médical externat/internat; 10 questions distinctes, sans référence au numéro des autres questions. Format JSON strict.\\nSOURCES EUROPE PMC:\\n'+referenceList;
     const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),55000);
     let res:Response;
     try {
       res=await fetch('https://api.groq.com/openai/v1/chat/completions',{method:'POST',signal:ctrl.signal,
       headers:{Authorization:'Bearer '+groq,'Content-Type':'application/json'},
       body:JSON.stringify({model:Deno.env.get('GROQ_TEXT_MODEL')||'openai/gpt-oss-120b',
       messages:[{role:'user',content:prompt}],temperature:0.2,reasoning_effort:'medium',reasoning_format:'hidden',
       max_completion_tokens:14500,stream:false,response_format:{type:'json_schema',json_schema:{name:'practice_daily_case',strict:true,schema}}})});
     }finally{clearTimeout(timer);}
     if(!res.ok)throw Error(res.status===429?'groq_rate_limited':'groq_unavailable');
     const raw=await res.json().catch(()=>null);
     const content=raw?.choices?.[0]?.message?.content;
     const text=typeof content==='string'?content:Array.isArray(content)?content.map((x:{text?:string})=>x.text??'').join(''):'';
     const data=JSON.parse(text) as {case_title?:string;case_stem?:string;case_stages?:{title?:string;narrative?:string}[];qcms?:Record<string,unknown>[]};
     caseTitle=plain(data.case_title,180);caseStem=plain(data.case_stem,6500);
     if(!caseTitle||caseStem.length<150||!Array.isArray(data.qcms)||data.qcms.length!==10||
       !Array.isArray(data.case_stages)||data.case_stages.length!==4)throw Error('invalid_case_format');
     caseStages=data.case_stages.map(stage=>({title:plain(stage.title,140),narrative:plain(stage.narrative,2400)}));
     if(caseStages.some(stage=>stage.title.length<5||stage.narrative.length<120))throw Error('invalid_stage_format');
     const seen=new Set<string>();
     for(const q of data.qcms){
       const question=plain(q.question,1300),opts=Array.isArray(q.options)?q.options.map(x=>plain(x,420)):[],cor=plain(q.correction,6500);
       const index=Number(q.correct_index),topic=String(q.topic??'synthese');
       const sources=Array.isArray(q.references)?q.references.flatMap((r:Record<string,unknown>):Ref[]=>{
         const ref=mapped.get(canon(r.url));return ref?[ref]:[];
       }):[];
       const uniqueSources=[...new Map(sources.map(r=>[canon(r.url),r])).values()].slice(0,3);
       if(question.length<12||cor.length<20||opts.length!==4||new Set(opts).size!==4||
         !Number.isInteger(index)||index<0||index>3||!topics.includes(topic)||!uniqueSources.length||seen.has(cleanKey(question)))
         throw Error('invalid_generated_questions');
       seen.add(cleanKey(question));
       const illustration=String(q.image_search_query??'').trim()?await commons(String(q.image_search_query)):null;
       const imageSection=illustration?'\\n\\n§IMAGES§\\n'+[illustration.name,illustration.url,illustration.source].join('|||'):'';
       const sourceSection='\\n\\n§SOURCES§\\n'+uniqueSources.map(r=>[r.kind,r.title,r.organization,r.year,r.url].join('|||')).join('\n');
       questions.push({question,options:opts,correct_index:index,correction:(cor+imageSection+sourceSection).slice(0,11000),topic});
     }
   }
   if(questions.length!==10)throw Error('invalid_question_count');
   const inserted=await admin.from('practice_daily_challenges').upsert({challenge_date:date,mode,case_title:caseTitle,case_stem:caseStem,case_stages:caseStages,questions},{onConflict:'challenge_date,mode',ignoreDuplicates:true});
   if(inserted.error)throw Error('database_write_failed');
   return send(req,{ok:true,ready:true,day:date,mode,generated:true});
 }catch(e){
   const error=e instanceof Error?e.message:'generation_failed';
   return send(req,{ok:false,error,retryable:true},503);
 }finally{
   await admin.from('practice_daily_generation_claims').delete().eq('challenge_date',date).eq('mode',mode);
 }
});
