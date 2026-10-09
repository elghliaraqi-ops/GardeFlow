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
async function literatureEuropePmc(specialty:string):Promise<Ref[]> {
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
async function literaturePubMed(specialty:string):Promise<Ref[]> {
 // NCBI fallback: retain only references with PubMed identifiers confirmed by the API.
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),15000);
 try{
  const qs=new URLSearchParams({db:'pubmed',term:specialty+' AND (practice guideline[Publication Type] OR systematic review[Publication Type] OR review[Publication Type])',retmode:'json',retmax:'12'});
  const res=await fetch('https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?'+qs,{signal:ctrl.signal});
  if(!res.ok)return [];
  const search=await res.json() as {esearchresult?:{idlist?:string[]}};
  const ids=(search.esearchresult?.idlist??[]).filter(id=>/^\d+$/.test(id)).slice(0,12);
  if(!ids.length)return [];
  const lookup=new URLSearchParams({db:'pubmed',id:ids.join(','),retmode:'json'});
  const summary=await fetch('https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?'+lookup,{signal:ctrl.signal});
  if(!summary.ok)return [];
  const data=await summary.json() as {result?:Record<string,unknown>};
  return ids.flatMap((id):Ref[]=>{
   const item=data.result?.[id] as Record<string,unknown>|undefined;
   const title=plain(item?.title,350);
   if(!title)return [];
   const date=String(item?.pubdate??'');
   const year=date.match(/\b(?:19|20)\d{2}\b/)?.[0]??'';
   const kind=/guideline|recommendation/i.test(title)?'recommandation':/consensus/i.test(title)?'consensus':'revue';
   return [{title,url:'https://pubmed.ncbi.nlm.nih.gov/'+id+'/',year,organization:plain(item?.fulljournalname??'PubMed',160),kind}];
  });
 }catch{return [];}finally{clearTimeout(timer);}
}
async function literature(specialty:string):Promise<Ref[]> {
 const primary=await literatureEuropePmc(specialty);
 if(primary.length)return primary;
 console.warn('independent_case_literature_primary_unavailable',{provider:'europe_pmc'});
 return await literaturePubMed(specialty);
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
const caseBatchSchema=JSON.parse(JSON.stringify(schema));
caseBatchSchema.properties.qcms.minItems=5;
caseBatchSchema.properties.qcms.maxItems=5;

async function newGroqBatch(prompt:string,format:Record<string,unknown>):Promise<Record<string,unknown>> {
 const key=Deno.env.get('GROQ_API_KEY');
 if(!key)throw Error('groq_configuration_missing');
 const config=(Deno.env.get('GROQ_TEXT_MODEL')??'').trim();
 const model=['openai/gpt-oss-20b','openai/gpt-oss-120b'].includes(config)
  ?config:'openai/gpt-oss-120b';
 let code='groq_unavailable';
 for(const strict of [true,false]){
  const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),48000);
  try{
   const response=await fetch('https://api.groq.com/openai/v1/chat/completions',{
    method:'POST',signal:ctrl.signal,
    headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
    body:JSON.stringify({
     model,messages:[{role:'user',content:prompt}],
     temperature:0.2,reasoning_effort:'low',reasoning_format:'hidden',
     max_completion_tokens:7000,stream:false,
     response_format:strict
      ?{type:'json_schema',json_schema:{name:'practice_daily_batch',strict:true,schema:format}}
      :{type:'json_object'}
    })
   });
   if(!response.ok){
    const raw=await response.json().catch(()=>null);
    console.warn('daily_groq_http',{status:response.status,model,
     reason:String(raw?.error?.code??raw?.error?.type??'').slice(0,70)});
    if(response.status===401||response.status===403)throw Error('groq_auth_failed');
    if(response.status===429)throw Error('groq_rate_limited');
    code=response.status===400?'groq_request_rejected':'groq_provider_unavailable';
    continue;
   }
   const raw=await response.json().catch(()=>null);
   const content=raw?.choices?.[0]?.message?.content;
   if(typeof content==='string'){
    try{const parsed=JSON.parse(content);
     if(parsed&&typeof parsed==='object'&&!Array.isArray(parsed))return parsed;
    }catch{/* If JSON mode fails, retry with the fallback. */}
   }
   code='groq_invalid_json';
  }catch(err){
   const e=err instanceof Error?err:Error('groq_network_error');
   if(['groq_auth_failed','groq_rate_limited'].includes(e.message))throw e;
   code=e.name==='AbortError'?'groq_timeout':e.message;
   console.warn('daily_groq_exception',{code,model});
  }finally{clearTimeout(timer);}
 }
 throw Error(code);
}

async function checkAndFormat(batch:Record<string,unknown>,refs:Ref[],seen:Set<string>)
 :Promise<Record<string,unknown>[]>{
 if(!Array.isArray(batch.qcms)||batch.qcms.length!==5)throw Error('invalid_generated_question_count');
 const map=new Map(refs.map(x=>[canon(x.url),x]));
 const output:Record<string,unknown>[]=[];
 for(const raw of batch.qcms){
  const q=raw as Record<string,unknown>;
  const question=plain(q.question,1400),options=Array.isArray(q.options)
   ?q.options.map(x=>plain(x,450)):[];
  const correct=Number(q.correct_index),correction=plain(q.correction,6500);
  const topic=String(q.topic??'synthese'),fingerprint=cleanKey(question);
  const refObjects=Array.isArray(q.references)?q.references:[];
  const references=[...new Map(refObjects.flatMap((r:unknown)=>{
   const source=map.get(canon((r as {url?:string})?.url));
   return source?[[canon(source.url),source]]:[];
  }) as [string,Ref][]).values()].slice(0,3);
  if(question.length<12||options.length!==4||options.some(x=>x.length<1)||
   new Set(options.map(cleanKey)).size!==4||correction.length<25||
   !Number.isInteger(correct)||correct<0||correct>3||!references.length||
   !topics.includes(topic)||seen.has(fingerprint))throw Error('invalid_generated_questions');
  seen.add(fingerprint);
  output.push({question,options,correct_index:correct,correction,topic,
   references,illustration_query:String(q.image_search_query??'')});
 }
 // Parallel Wikimedia lookups avoid up to 60s sequential Edge timeout.
 return await Promise.all(output.map(async(item)=>{
  const query=String(item.illustration_query??'').trim();
  const picture=query?await commons(query):null;
  const img=picture?'\n\n§IMAGES§\n'+
    [picture.name,picture.url,picture.source].join('|||'):'';
  const urls='\n\n§SOURCES§\n'+(item.references as Ref[])
    .map(r=>[r.kind,r.title,r.organization,r.year,r.url].join('|||')).join('\n');
  return {
   question:item.question,options:item.options,correct_index:item.correct_index,
   topic:item.topic,correction:String(item.correction)+img+urls
  };
 }));
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
 const uid=userData.user?.id;
 if(authErr||!uid)return send(req,{ok:false,error:'auth_failed'},401);
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:profile,error:profileError}=await admin.from('profiles').select('id,account_status').eq('id',uid).maybeSingle();
 if(profileError||!profile||profile.account_status!=='active')return send(req,{ok:false,error:'account_inactive'},403);
 try {
   // Completely independent from official daily challenges, scores and XP.
   // Nothing is inserted into Supabase tables or Storage.
   const specialty=specialties[numericSeed(casablancaDay()+crypto.randomUUID())%specialties.length];
   const refs=await literature(specialty);
   if(!refs.length)throw Error('literature_unavailable');
   const refList=refs.map(r=>[r.title,r.year,r.url].join(' | ')).join('\n');
   const common='Réponds UNIQUEMENT en JSON. Format exigé : objet {qcms:[cinq objets]} ; '+
     'chaque QCM a exactement les clés question, options (4 textes), correct_index (0 à 3), '+
     'correction détaillée, topic (motif/symptome/examen/imagerie/synthese/prise_en_charge/orientation/avis_specialise), '+
     'references (tableau 1 à 3 objets {url}), image_search_query (texte). '+
     'Cinq QCM originaux EXACTEMENT par lot. Utilise exclusivement ces liens vérifiables :\n'+refList;
   const prompt='Crée un SEUL cas clinique entièrement FICTIF pour la formation médicale en '+specialty+
    '. JSON avec case_title, case_stem dossier complet (min 150 caractères) et case_stages : EXACTEMENT QUATRE objets {title,narrative}, '+
    'minimum 120 caractères par narrative. '+
    'Étape 1 admission et examen; étape 2 investigations, laboratoire et imagerie; '+
    'étape 3 décisions thérapeutiques; étape 4 complications, évolution et suivi. '+
    'Pas de spoiler dans une étape précoce. '+
    'Les cinq premiers QCM concernent l’admission (QCM 1-2) puis les investigations (QCM 3-5). '+common;
   let caseTitle='',caseStem='',stages:{title:string;narrative:string}[]=[];
   let questions:Record<string,unknown>[]=[];
   let firstError='invalid_case_format';
   // Retry only malformed/temporary Groq responses; never retry authentication or rate-limit failures.
   for(let attempt=0;attempt<2;attempt++){
    try{
     const instruction=attempt===0?prompt:prompt+
      '\nREGENERATION : objet racine avec case_title, case_stem (minimum 150 caracteres), '+
      'case_stages (4 etapes, narrative minimum 120 caracteres) et qcms (EXACTEMENT 5 questions). '+
      'Aucun Markdown, aucune cle manquante ni texte hors JSON.';
     const first=await newGroqBatch(instruction,caseBatchSchema);
     const title=plain(first.case_title,180),stem=plain(first.case_stem,6500);
     const rawStages=first.case_stages;
     if(!title||stem.length<150||!Array.isArray(rawStages)||rawStages.length!==4)
      throw Error('invalid_case_format');
     const parsedStages=rawStages.map((stage:{title?:string;narrative?:string})=>({
      title:plain(stage.title,140),narrative:plain(stage.narrative,2400)
     }));
     if(parsedStages.some(stage=>stage.title.length<5||stage.narrative.length<120))
      throw Error('invalid_stage_format');
     const seenAttempt=new Set<string>();
     const parsedQuestions=await checkAndFormat(first,refs,seenAttempt);
     caseTitle=title;caseStem=stem;stages=parsedStages;questions=parsedQuestions;
     break;
    }catch(err){
     const code=err instanceof Error?err.message:'groq_invalid_response';
     if(['groq_auth_failed','groq_rate_limited','groq_configuration_missing'].includes(code))throw err;
     firstError=code;
     console.warn('independent_case_first_batch_retry',{code,attempt:attempt+1});
    }
   }
   if(questions.length!==5)throw Error(firstError);
   const seen=new Set(questions.map(x=>cleanKey(String(x.question))));
   const continuation='Continue EXACTEMENT le même cas FICTIF, sans recréer un patient, en cinq nouveaux QCM (6-10). '+
     'Dossier complet : '+caseStem+'. Étapes : '+JSON.stringify(stages)+
     '. Questions 6,7,8 : décision thérapeutique; questions 9,10 : évolution/suivi. '+
     'Ne répète jamais ces questions : '+questions.map(x=>String(x.question)).join(' / ')+'. '+common;
   const second=await newGroqBatch(continuation,batchSchema);
   questions.push(...await checkAndFormat(second,refs,seen));
   if(questions.length!==10)throw Error('invalid_question_count');
   return send(req,{ok:true,mode:'cas_progressif_independant',
     case_title:caseTitle,case_stem:caseStem,case_stages:stages,questions});
 }catch(err){
   const code=err instanceof Error?err.message:'case_generation_failed';
   console.warn('independent_case_generation_failure',{code});
   return send(req,{ok:false,error:code,retryable:!['groq_auth_failed','groq_configuration_missing'].includes(code)},503);
 }
});
