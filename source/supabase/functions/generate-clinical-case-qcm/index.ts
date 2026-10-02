import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const axes = ['cours_fondamental','diagnostic','explorations','prise_en_charge','recommandations'] as const;
const topics = ['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'] as const;
const sourceKinds = ['recommandation','consensus','revue','cours'] as const;
const timeoutMs = 60000;
const maxPayloadChars = 14000;

type WebSource = { title: string; url: string };

function cors(req: Request): Record<string,string> {
  const origin = req.headers.get('Origin')?.trim() ?? '';
  const allow = (Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS') ?? '').split(',').map(x=>x.trim()).filter(Boolean);
  const h: Record<string,string> = {
    'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods':'POST, OPTIONS',
  };
  if (!origin) return h;
  if (allow.length === 0) h['Access-Control-Allow-Origin']='*';
  else if (allow.includes(origin)) { h['Access-Control-Allow-Origin']=origin; h['Vary']='Origin'; }
  return h;
}

function reply(req: Request, body: unknown, status=200) {
  return new Response(JSON.stringify(body), {
    status,
    headers:{...cors(req),'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'},
  });
}

function code(v: unknown, fallback='unknown') {
  const x=String(v??'').trim();
  return /^[a-zA-Z0-9_.:-]{1,80}$/.test(x)?x:fallback;
}

function log(event: string, fields: Record<string,unknown>={}) {
  console.log(JSON.stringify({event,...fields}));
}

async function userHash(id: string) {
  try {
    const d=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(id));
    return Array.from(new Uint8Array(d).slice(0,6)).map(x=>x.toString(16).padStart(2,'0')).join('');
  } catch (_) { return 'hash_unavailable'; }
}

function scrub(value: unknown, max=2200) {
  let x=String(value??'').trim();
  if (!x) return '';
  x=x.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[email masqué]');
  x=x.replace(/\b\d{4}-\d{2}-\d{2}\b/g,'[date masquée]');
  x=x.replace(/\b[0-3]?\d[/-][01]?\d[/-]\d{2,4}\b/g,'[date masquée]');
  x=x.replace(/\+?\d[\d .()/-]{7,}\d/g,'[téléphone masqué]');
  x=x.replace(/\b(nom|prénom|prenom|ipp|cin|dossier(?: patient)?|date de naissance|né(?:e)? le|adresse|address|domicile|téléphone|telephone|tel)\b\s*[:=-]\s*[^,;\n]{1,140}/gi,'$1 : [masqué]');
  x=x.replace(/\b(?:M\.|Mr|Mme|Monsieur|Madame)\s+[A-ZÀ-ÖØ-Ý][A-Za-zÀ-ÿ'’-]{1,40}(?:\s+[A-ZÀ-ÖØ-Ý][A-Za-zÀ-ÿ'’-]{1,40})?/g,'[identité masquée]');
  x=x.replace(/\b[A-Z]{1,4}\d{5,}\b/gi,'[identifiant masqué]');
  x=x.replace(/\b\d{7,}\b/g,'[identifiant masqué]');
  return x.slice(0,max).trim();
}

function safeCase(post:any) {
  const build=(limit:number)=>({
    age_band:scrub(post.age_band,80), sex:scrub(post.sex,40),
    presentation:scrub(post.presentation,limit), history:scrub(post.history,limit),
    clinical_exam:scrub(post.clinical_exam,limit), complementary_exams:scrub(post.complementary_exams,limit),
    imaging_conclusion:scrub(post.imaging_conclusion,limit), assessment:scrub(post.assessment,limit),
    plan:scrub(post.plan,limit), disposition:scrub(post.disposition,Math.min(limit,700)),
    specialist_service:scrub(post.specialist_service,300),
  });
  let result=build(2200);
  if (JSON.stringify(result).length>maxPayloadChars) result=build(900);
  return result;
}

function canonicalUrl(value:unknown) {
  try {
    const u=new URL(String(value??'').trim());
    if (!['http:','https:'].includes(u.protocol)) return '';
    u.hash=''; u.search='';
    const p=u.pathname.replace(/\/+$/,'')||'/';
    return `${u.protocol}//${u.hostname.toLowerCase()}${p}`;
  } catch (_) { return ''; }
}

function addGroundingSources(metadata:any,map:Map<string,WebSource>) {
  for(const chunk of metadata?.groundingChunks??[]) {
    const raw=String(chunk?.web?.uri??'').trim();
    const key=canonicalUrl(raw);
    if(key&&!map.has(key)) map.set(key,{title:scrub(chunk?.web?.title,500)||'Source médicale',url:raw});
  }
}

async function geminiLiveResearch(apiKey:string,model:string,prompt:string):Promise<{text:string;sources:WebSource[]}> {
  return await new Promise((resolve,reject)=>{
    const url=`wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${encodeURIComponent(apiKey)}`;
    const ws=new WebSocket(url);
    const transcript:string[]=[];
    const sourceMap=new Map<string,WebSource>();
    let settled=false;
    let promptSent=false;
    const done=(err?:Error)=>{
      if(settled)return;
      settled=true;
      clearTimeout(timer);
      try{ws.close(1000,'done');}catch(_){}
      if(err) reject(err); else resolve({text:transcript.join('').trim(),sources:[...sourceMap.values()]});
    };
    const timer=setTimeout(()=>done(new Error('gemini_live_timeout')),timeoutMs);
    ws.addEventListener('open',()=>{
      try {
        ws.send(JSON.stringify({setup:{
          model:`models/${model}`,
          generationConfig:{responseModalities:['AUDIO'],temperature:0.1,maxOutputTokens:7000},
          outputAudioTranscription:{},
          tools:[{googleSearch:{}}],
        }}));
      } catch(_) { done(new Error('gemini_live_setup_failed')); }
    });
    ws.addEventListener('message',async(ev)=>{
      if(settled)return;
      try {
        const raw=typeof ev.data==='string'?ev.data:ev.data instanceof Blob?await ev.data.text():String(ev.data??'');
        const msg=JSON.parse(raw);
        if(msg?.setupComplete&&!promptSent){
          promptSent=true;
          ws.send(JSON.stringify({clientContent:{
            turns:[{role:'user',parts:[{text:prompt}]}],
            turnComplete:true,
          }}));
          return;
        }
        const sc=msg?.serverContent;
        if(sc){
          if(typeof sc?.outputTranscription?.text==='string') transcript.push(sc.outputTranscription.text);
          addGroundingSources(sc?.groundingMetadata,sourceMap);
          if(sc?.turnComplete===true) done();
        }
      } catch(_) { done(new Error('gemini_live_invalid_message')); }
    });
    ws.addEventListener('error',()=>done(new Error('gemini_live_network_error')));
    ws.addEventListener('close',(ev)=>{if(!settled)done(new Error(`gemini_live_closed_${ev.code}`));});
  });
}

function extractInteractionText(payload:any) {
  if(typeof payload?.output_text==='string') return payload.output_text;
  const parts:string[]=[];
  for(const item of payload?.outputs??payload?.steps??[]) {
    if(item?.type==='model_output') for(const block of item?.content??[]) if(typeof block?.text==='string') parts.push(block.text);
    else if(item?.type==='text'&&typeof item?.text==='string') parts.push(item.text);
  }
  return parts.join('\n');
}

function parseJsonText(text:string) {
  return JSON.parse(text.trim().replace(/^```(?:json)?\s*/i,'').replace(/\s*```$/,'').trim());
}

const referenceSchema={type:'object',additionalProperties:false,required:['title','organization','year','url','kind'],properties:{
  title:{type:'string'},organization:{type:'string'},year:{type:'string'},url:{type:'string'},kind:{type:'string',enum:sourceKinds}
}};
const qcmSchema={type:'object',additionalProperties:false,required:['axis','question','options','correct_index','correction','topic','references'],properties:{
  axis:{type:'string',enum:axes},question:{type:'string'},options:{type:'array',minItems:4,maxItems:4,items:{type:'string'}},
  correct_index:{type:'integer',minimum:0,maximum:3},correction:{type:'string'},topic:{type:'string',enum:topics},
  references:{type:'array',minItems:1,maxItems:3,items:referenceSchema}
}};
const outputSchema={type:'object',additionalProperties:false,required:['qcms'],properties:{qcms:{type:'array',minItems:5,maxItems:5,items:qcmSchema}}};
const generic=[/dans ce cas(?: clinique)?/i,/document(?:é|ée|és|ées)/i,/quelle synthèse clinique a été retenue/i,/quelle prise en charge a été/i,/quelle orientation a été/i,/quel avis spécialisé a été/i];
function correction(text:string,refs:any[]) {return `${text}\n\n§SOURCES§\n${refs.map(r=>`${r.kind}|||${r.title}|||${r.organization}|||${r.year}|||${r.url}`).join('\n')}`.slice(0,9000);}
function retrySeconds(v:unknown){const t=Date.parse(String(v??''));return Number.isFinite(t)?Math.max(1,Math.ceil((t-Date.now())/1000)):null;}

Deno.serve(async(req:Request)=>{
  const started=Date.now();
  const requestId=crypto.randomUUID();
  const executionId=code(Deno.env.get('SB_EXECUTION_ID'),'edge');
  let admin:any=null; let claimed=''; let postLog=''; let hash='';
  const meta=()=>({request_id:requestId,execution_id:executionId,post_id:postLog||undefined,user_hash:hash||undefined,duration_ms:Date.now()-started});
  const fail=(status:number,error:string,retryable:boolean,extra:Record<string,unknown>={})=>reply(req,{ok:false,error,retryable,...extra},status);
  const finish=async(success:boolean,error?:string)=>{if(!admin||!claimed)return;try{await admin.rpc('clinical_case_finish_qcm_generation',{p_post_id:claimed,p_success:success,p_error_code:error?code(error,'generation_failed'):null});}catch(_){log('generation_finish_state_failed',meta());}};

  if(req.method==='OPTIONS') return new Response(null,{status:204,headers:cors(req)});
  if(req.method!=='POST') return fail(405,'method_not_allowed',false);
  const origin=req.headers.get('Origin')?.trim()??'';
  const configured=(Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS')??'').split(',').map(x=>x.trim()).filter(Boolean);
  if(origin&&configured.length>0&&!configured.includes(origin)){log('cors_origin_denied',meta());return fail(403,'origin_not_allowed',false);}

  try {
    const supabaseUrl=Deno.env.get('SUPABASE_URL');
    const anonKey=Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const geminiKey=Deno.env.get('GEMINI_API_KEY');
    const auth=req.headers.get('Authorization')??'';
    if(!auth.startsWith('Bearer ')){log('authentication_failed',meta());return fail(401,'authentication_required',false);}
    if(!supabaseUrl||!anonKey||!serviceKey){log('server_configuration_missing',{...meta(),missing_supabase_url:!supabaseUrl,missing_anon_key:!anonKey,missing_service_role_key:!serviceKey});return fail(503,'server_configuration_unavailable',true);}

    const caller=createClient(supabaseUrl,anonKey,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
    admin=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:userData,error:userError}=await caller.auth.getUser();
    const uid=userData.user?.id;
    if(userError||!uid){log('authentication_failed',meta());return fail(401,'authentication_failed',false);}
    hash=await userHash(uid);
    const {data:profile,error:profileError}=await admin.from('profiles').select('id,account_status,role').eq('id',uid).maybeSingle();
    if(profileError||!profile||profile.account_status!=='active'){log('account_inactive',meta());return fail(403,'account_inactive',false);}

    const body=await req.json().catch(()=>null);
    if(!body||typeof body!=='object') return fail(400,'invalid_request',false);
    const practiceId=String((body as any).practice_case_id??'').trim();
    const requestedPost=String((body as any).post_id??'').trim();
    const force=(body as any).force_regenerate===true;
    const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if((!practiceId&&!requestedPost)||(practiceId&&requestedPost)) return fail(400,'exactly_one_case_identifier_required',false);
    if(practiceId&&!uuid.test(practiceId)) return fail(400,'invalid_case_id',false);
    if(requestedPost&&!uuid.test(requestedPost)) return fail(400,'invalid_post_id',false);

    const select='id,practice_case_id,author_id,published_at,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan,disposition,specialist_service,specialty_classification_source';
    let post:any=null; let resolvedPractice=practiceId;
    if(practiceId){
      const {data:pc,error:e}=await admin.from('practice_cases').select('id,user_id,is_draft').eq('id',practiceId).maybeSingle();
      if(e||!pc||pc.user_id!==uid){log('case_not_found',meta());return fail(404,'case_not_found',false);}
      if(pc.is_draft===true)return fail(409,'case_not_ready',false);
      const r=await admin.from('clinical_case_posts').select(select).eq('practice_case_id',practiceId).maybeSingle();
      if(r.error||!r.data)return fail(409,'case_not_ready',false);
      post=r.data;
    } else {
      const r=await admin.from('clinical_case_posts').select(select).eq('id',requestedPost).maybeSingle();
      if(r.error||!r.data||!r.data.published_at){log('case_not_found',meta());return fail(404,'case_not_found',false);}
      post=r.data; resolvedPractice=String(post.practice_case_id??'');
    }
    postLog=String(post.id);
    log('qcm_generation_started',meta());

    const existing=await admin.from('clinical_case_qcms').select('id,generation_source').eq('post_id',post.id);
    if(existing.error){log('database_read_failed',meta());return fail(503,'database_unavailable',true);}
    if((existing.data??[]).length===5&&(existing.data??[]).every((q:any)=>q.generation_source==='openai')) return reply(req,{ok:true,generated:false,status:'ready',count:5,post_id:post.id});

    const isAdmin=String(profile.role??'').toLowerCase()==='admin';
    const canForce=force&&(isAdmin||post.author_id===uid);
    const claimResult=await admin.rpc('clinical_case_claim_qcm_generation',{p_post_id:post.id,p_user_id:uid,p_force:canForce});
    if(claimResult.error||!Array.isArray(claimResult.data)||claimResult.data.length===0){log('generation_guard_unavailable',meta());return fail(503,'generation_guard_unavailable',true);}
    const c=claimResult.data[0]??{};
    if(c.claimed!==true){
      const status=String(c.status??'failed'),err=code(c.error_code,'retry_later'),retry=c.retry_after??null,seconds=retrySeconds(retry);
      if(status==='ready') return reply(req,{ok:true,generated:false,status:'ready',count:5,post_id:post.id});
      if(status==='running'){log('generation_already_running',meta());return fail(202,'generation_in_progress',true,{retry_after:retry,retry_after_seconds:seconds});}
      if(err==='rate_limit_exceeded'){log('rate_limit_exceeded',meta());return fail(429,'rate_limit_exceeded',true,{retry_after:retry,retry_after_seconds:seconds});}
      const permanent=['gemini_request_invalid','gemini_provider_auth_error','gemini_model_not_found','authentication_failed','authorization_failed','invalid_request'].includes(err);
      return fail(permanent?502:503,err,!permanent,{retry_after:retry,retry_after_seconds:seconds});
    }
    claimed=post.id;

    if(!geminiKey){log('gemini_key_missing',meta());await finish(false,'gemini_key_missing');claimed='';return fail(503,'gemini_unavailable',true,{retry_after_seconds:60});}
    const clean=safeCase(post),cleanJson=JSON.stringify(clean);
    if(cleanJson.length>maxPayloadChars){await finish(false,'payload_too_large');claimed='';return fail(400,'clinical_payload_too_large',false);}

    const researchModel=String(Deno.env.get('GEMINI_RESEARCH_MODEL')??'').trim()||'gemini-3.8-live';
    const generationModel=String(Deno.env.get('GEMINI_TEXT_MODEL')??'').trim()||'gemini-3.8-flash';
    const researchPrompt=`Tu es documentaliste médical. DATE DE RÉFÉRENCE : 2 octobre 2026.
Recherche avec Google Search des sources médicales fiables et directement pertinentes pour le cas ANONYMISÉ ci-dessous : sociétés savantes, autorités sanitaires, universités, NCBI/StatPearls, revues scientifiques, recommandations ou consensus.
Prépare une synthèse factuelle destinée à construire 5 QCM pour externes/internes : cours fondamental, diagnostic, explorations, prise en charge, recommandations.
Priorise les recommandations récentes. Évite Wikipédia, blogs, forums et sites commerciaux. N'essaie jamais d'identifier le patient et ne restitue jamais son dossier.
CAS ANONYMISÉ :
${cleanJson}`;

    let research:{text:string;sources:WebSource[]};
    log('gemini_research_started',{...meta(),model:researchModel,api:'live_audio_transcription'});
    try {
      research=await geminiLiveResearch(geminiKey,researchModel,researchPrompt);
    } catch(e) {
      const reason=code((e as Error)?.message,'gemini_live_error');
      log('gemini_http_error',{...meta(),phase:'research',provider_error:reason});
      const modelMissing=reason.includes('closed_1008')||reason.includes('closed_1003');
      await finish(false,modelMissing?'gemini_model_not_found':'gemini_network_error');claimed='';
      return fail(modelMissing?502:503,modelMissing?'gemini_request_invalid':'gemini_unavailable',!modelMissing);
    }
    if(!research.text||research.sources.length===0){
      const reason=!research.text?'gemini_empty_research':'missing_web_sources';
      log('qcm_validation_failed',{...meta(),phase:'research',reason});await finish(false,reason);claimed='';return fail(502,'gemini_invalid_response',true);
    }

    const sources=research.sources.slice(0,20);
    const sourceCatalog=sources.map((s,i)=>`${i+1}. ${s.title||'Source médicale'} — ${s.url}`).join('\n');
    const prompt=`Tu es responsable pédagogique de QCM pour externes et internes en médecine. DATE DE RÉFÉRENCE : 2 octobre 2026.
Le cas ci-dessous est anonymisé et sert uniquement d'ancrage thématique. N'essaie jamais d'identifier le patient et ne restitue jamais le dossier.
Crée EXACTEMENT 5 QCM autonomes et sourcés, dans cet ordre : cours_fondamental, diagnostic, explorations, prise_en_charge, recommandations.
Chaque QCM comporte exactement 4 propositions, une seule meilleure réponse, une correction factuelle de 3 à 6 phrases et 1 à 3 références réellement présentes dans le CATALOGUE DE SOURCES.
Pour chaque référence, recopie exactement l'URL du catalogue sans la modifier. Si l'année ou l'organisation ne sont pas certaines, utilise « Non précisé » plutôt que d'inventer.
QCM1 exige une source de type cours ; QCM2 à QCM4 exigent une source cours ou revue ; QCM5 exige une recommandation ou un consensus récent.
N'invente aucun URL, seuil, score, posologie ou recommandation. N'utilise pas “dans ce cas”, “toutes les réponses” ou “aucune des réponses”. Réponds en français et respecte strictement le schéma JSON.
CAS ANONYMISÉ :
${cleanJson}

SYNTHÈSE DOCUMENTAIRE GEMINI :
${research.text.slice(0,12000)}

CATALOGUE DE SOURCES CONSULTÉES :
${sourceCatalog}`;

    const controller=new AbortController();
    const timer=setTimeout(()=>controller.abort(),timeoutMs);
    let provider:Response;
    log('gemini_generation_started',{...meta(),model:generationModel,web_source_count:sources.length});
    try {
      provider=await fetch('https://generativelanguage.googleapis.com/v1beta/interactions',{
        method:'POST',signal:controller.signal,
        headers:{'x-goog-api-key':geminiKey,'Content-Type':'application/json'},
        body:JSON.stringify({model:generationModel,input:prompt,store:false,generation_config:{temperature:0.2,thinking_level:'low'},response_format:{type:'text',mime_type:'application/json',schema:outputSchema}})
      });
    } catch(e) {
      const timeout=e instanceof DOMException&&e.name==='AbortError';
      log('gemini_http_error',{...meta(),phase:'generation',provider_error:timeout?'timeout':'network'});
      await finish(false,timeout?'gemini_timeout':'gemini_network_error');claimed='';return fail(503,'gemini_unavailable',true);
    } finally {clearTimeout(timer);}

    const providerId=code(provider.headers.get('x-request-id')??provider.headers.get('x-goog-request-id'),'unavailable');
    const payload=await provider.json().catch(()=>null);
    if(!provider.ok){
      const status=provider.status;
      const pstatus=code(payload?.error?.status,`http_${status}`);
      const ptype=code(payload?.error?.details?.[0]?.reason??payload?.error?.status,'provider_error');
      const schemaProblem=status===400&&JSON.stringify(payload?.error??{}).toLowerCase().includes('schema');
      log(schemaProblem?'gemini_invalid_schema':'gemini_http_error',{...meta(),phase:'generation',provider_status:status,provider_code:pstatus,provider_type:ptype,provider_request_id:providerId});
      const permanent=[400,401,403,404].includes(status);
      const finishCode=schemaProblem?'gemini_invalid_schema':status===400?'gemini_request_invalid':status===404?'gemini_model_not_found':status===429?'gemini_rate_limited':status>=500?'gemini_provider_unavailable':status===401||status===403?'gemini_provider_auth_error':'gemini_provider_error';
      await finish(false,finishCode);claimed='';return fail(permanent?502:503,permanent?'gemini_request_invalid':'gemini_unavailable',!permanent);
    }
    if(!payload||typeof payload!=='object'){log('gemini_invalid_json',{...meta(),provider_request_id:providerId});await finish(false,'gemini_invalid_json');claimed='';return fail(502,'gemini_invalid_response',true);}

    let generated:any;
    try {
      const raw=extractInteractionText(payload).trim();
      if(!raw)throw new Error('empty_model_output');
      generated=parseJsonText(raw);
    } catch(_) {
      log('gemini_invalid_json',{...meta(),provider_request_id:providerId});await finish(false,'gemini_invalid_json');claimed='';return fail(502,'gemini_invalid_response',true);
    }

    const consulted=new Set(sources.map(s=>canonicalUrl(s.url)));
    try {
      const raw=Array.isArray(generated?.qcms)?generated.qcms:[];
      if(raw.length!==5)throw new Error('invalid_qcm_count');
      const allowedTopics=new Set<string>(topics),allowedAxes=new Set<string>(axes),allowedKinds=new Set<string>(sourceKinds);
      const normalized=raw.map((q:any,i:number)=>{
        const opts=Array.isArray(q?.options)?q.options.map((x:unknown)=>scrub(x,420)).filter(Boolean):[];
        const question=scrub(q?.question,1200),corr=scrub(q?.correction,5500),ci=Number(q?.correct_index),topic=String(q?.topic??'').trim(),axis=String(q?.axis??'').trim();
        const refs=(Array.isArray(q?.references)?q.references:[]).map((r:any)=>({title:scrub(r?.title,600),organization:scrub(r?.organization,300),year:scrub(r?.year,40),url:String(r?.url??'').trim(),kind:String(r?.kind??'').trim()})).filter((r:any)=>r.title&&r.organization&&r.year&&canonicalUrl(r.url)&&allowedKinds.has(r.kind)&&consulted.has(canonicalUrl(r.url)));
        if(!question||question.length<12||!corr||corr.length<20||opts.length!==4||new Set(opts).size!==4||!Number.isInteger(ci)||ci<0||ci>3||!allowedTopics.has(topic)||!allowedAxes.has(axis)||refs.length<1||generic.some(p=>p.test(question)))throw new Error(`invalid_qcm_${i+1}`);
        const kinds=new Set(refs.map((r:any)=>r.kind));
        if(i===0&&!kinds.has('cours'))throw new Error('qcm_1_missing_course_source');
        if(i>=1&&i<=3&&![...kinds].some(k=>k==='cours'||k==='revue'))throw new Error(`qcm_${i+1}_missing_teaching_source`);
        if(i===4&&![...kinds].some(k=>k==='recommandation'||k==='consensus'))throw new Error('qcm_5_missing_guideline_source');
        return {axis,position:i+1,question,options:opts,correct_index:ci,correction:correction(corr,refs.slice(0,3)),topic};
      });
      if(normalized.some((q:any,i:number)=>q.axis!==axes[i]))throw new Error('invalid_axis_order');
      if(new Set(normalized.map((q:any)=>q.question.toLowerCase().replace(/\s+/g,' ').trim())).size!==5)throw new Error('duplicate_questions');
      const persisted=normalized.map(({axis:_axis,...q}:any)=>q);
      const commit=await admin.rpc('clinical_case_commit_generated_qcms',{p_post_id:post.id,p_qcms:persisted});
      if(commit.error){log('database_write_failed',{...meta(),db_code:code(commit.error.code,'rpc_error')});await finish(false,'database_write_failed');claimed='';return fail(503,'database_unavailable',true);}
    } catch(e) {
      const reason=code((e as Error)?.message,'qcm_validation_failed');
      log('qcm_validation_failed',{...meta(),reason});await finish(false,reason);claimed='';return fail(502,'gemini_invalid_response',true);
    }

    await finish(true);claimed='';
    log('qcm_generation_success',{...meta(),provider:'gemini',qcm_count:5,web_source_count:sources.length,provider_request_id:providerId,research_model:researchModel,generation_model:generationModel});
    return reply(req,{ok:true,generated:true,status:'ready',count:5,provider:'gemini',post_id:post.id,practice_case_id:resolvedPractice});
  } catch(e) {
    const err=code((e as Error)?.message,'generation_failed');
    await finish(false,err);claimed='';log('qcm_generation_failed',{...meta(),error_code:err});return fail(503,'generation_unavailable',true);
  }
});
