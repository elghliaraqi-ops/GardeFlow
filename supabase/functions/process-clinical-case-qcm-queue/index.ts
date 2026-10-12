import {radiologyAssistantContext,radiologyPriorityPolicy} from './radiology_assistant.ts';
import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const AXES = ['cours_fondamental','diagnostic','explorations','prise_en_charge','recommandations'];
const TOPICS = ['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'];
const GROQ_MODEL = Deno.env.get('GROQ_TEXT_MODEL')?.trim() || 'openai/gpt-oss-120b';
const GROQ_TIMEOUT_MS = 70000;
const LIT_TIMEOUT_MS = 12000;
const CURRENT_YEAR = 2026;
const RECENT_FROM_YEAR = CURRENT_YEAR - 4;
const MAX_SOURCES = 7;
const GROQ_MAX_OUTPUT = 3150;
const GROQ_REDUCED_OUTPUT = 2450;
const MAX_CONTEXT_CHARS = 3600;
const MAX_CATALOG_CHARS = 2100;

type Source = {
  title:string; url:string; organization:string; year:string|number; year_num:number;
  kind:'recommandation'|'consensus'|'revue'|'essai_clinique'; abstract:string;
  origin:'Europe PMC'|'PubMed'|'ClinicalTrials.gov'; dedupe_key:string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {status, headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}});
}
function scrub(value: unknown, max = 2200) {
  let x = String(value ?? '').trim(); if (!x) return '';
  x = x.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[email masqué]')
    .replace(/\b\d{4}-\d{2}-\d{2}\b/g,'[date masquée]')
    .replace(/\b[0-3]?\d[/-][01]?\d[/-]\d{2,4}\b/g,'[date masquée]')
    .replace(/\+?\d[\d .()/-]{7,}\d/g,'[téléphone masqué]')
    .replace(/\b(nom|prénom|prenom|ipp|cin|dossier(?: patient)?|date de naissance|né(?:e)? le|adresse|domicile|téléphone|telephone|tel)\b\s*[:=-]\s*[^,;\n]{1,140}/gi,'$1 : [masqué]')
    .replace(/\b(?:M\.|Mr|Mme|Monsieur|Madame)\s+[A-ZÀ-ÖØ-Ý][A-Za-zÀ-ÿ'’-]{1,40}(?:\s+[A-ZÀ-ÖØ-Ý][A-Za-zÀ-ÿ'’-]{1,40})?/g,'[identité masquée]')
    .replace(/\b[A-Z]{1,4}\d{5,}\b/gi,'[identifiant masqué]')
    .replace(/\b\d{7,}\b/g,'[identifiant masqué]');
  return x.slice(0,max).trim();
}
function safeCase(post:any){
  const fields:Record<string,string>={
    age_band:scrub(post.age_band,80),sex:scrub(post.sex,40),
    presentation:scrub(post.presentation,550),history:scrub(post.history,350),
    clinical_exam:scrub(post.clinical_exam,500),
    complementary_exams:scrub(post.complementary_exams,500),
    imaging_conclusion:scrub(post.imaging_conclusion,400),
    assessment:scrub(post.assessment,580),plan:scrub(post.plan,470),
    disposition:scrub(post.disposition,280),
    specialist_service:scrub(post.specialist_service,140),
  };
  const clean:Record<string,string>={};let left=MAX_CONTEXT_CHARS;
  for(const [key,value] of Object.entries(fields)){
    if(!value||left<30)continue;
    clean[key]=value.slice(0,left);left-=clean[key].length;
  }
  return clean;
}
function stripHtml(v:unknown){return String(v??'').replace(/<[^>]*>/g,' ').replace(/&nbsp;/gi,' ').replace(/&amp;/gi,'&').replace(/\s+/g,' ').trim()}
function canonicalUrl(v:unknown){try{const u=new URL(String(v??'').trim());if(!['http:','https:'].includes(u.protocol))return'';u.hash='';return `${u.protocol}//${u.hostname.toLowerCase()}${u.pathname.replace(/\/+$/,'')||'/'}`}catch{return''}}
function yearOf(v:unknown){const y=Number(String(v??'').match(/\b(19|20)\d{2}\b/)?.[0]??0);return Number.isInteger(y)&&y>1900&&y<=CURRENT_YEAR+1?y:0}
function kindFromText(text:string):Source['kind']{const h=text.toLowerCase();if(/consensus/.test(h))return'consensus';if(/guideline|practice guideline|clinical practice guideline|recommendation/.test(h))return'recommandation';if(/randomized controlled trial|randomised controlled trial|clinical trial|phase [234]/.test(h))return'essai_clinique';return'revue'}
function serviceSearchTerms(service:string){const s=service.toLowerCase();if(s.includes('uro'))return'urolithiasis renal colic urology';if(s.includes('pneumo'))return'pneumonia respiratory pulmonology';if(s.includes('cardio'))return'acute coronary syndrome cardiology chest pain';if(s.includes('neuro'))return'acute stroke neurology';if(s.includes('trauma')||s.includes('ortho'))return'orthopedic trauma fracture';if(s.includes('visc')||s.includes('chir'))return'acute abdomen general surgery';if(s.includes('gyn'))return'gynecology emergency';return `${service} medicine`}

async function timedFetch(url:string, init:RequestInit={}, timeout=LIT_TIMEOUT_MS){const c=new AbortController();const t=setTimeout(()=>c.abort(),timeout);try{return await fetch(url,{...init,signal:c.signal})}finally{clearTimeout(t)}}

async function fetchEuropePmc(query:string,pageSize=10):Promise<Source[]>{
  const params=new URLSearchParams({query,format:'json',resultType:'core',pageSize:String(pageSize),synonym:'true'});
  const res=await timedFetch(`https://www.ebi.ac.uk/europepmc/webservices/rest/search?${params}`,{headers:{Accept:'application/json'}});
  if(!res.ok)throw new Error(`europepmc_http_${res.status}`); const p=await res.json().catch(()=>null); const rows=Array.isArray(p?.resultList?.result)?p.resultList.result:[]; const out:Source[]=[];
  for(const item of rows){const title=scrub(stripHtml(item?.title),700);const pmid=String(item?.pmid??'').trim();const doi=String(item?.doi??'').trim();let url='';if(/^10\.\d{4,9}\//i.test(doi))url=`https://doi.org/${doi}`;else if(/^\d+$/.test(pmid))url=`https://europepmc.org/article/MED/${pmid}`;else if(item?.source&&item?.id)url=`https://europepmc.org/article/${encodeURIComponent(item.source)}/${encodeURIComponent(item.id)}`;if(!title||!canonicalUrl(url))continue;const types=Array.isArray(item?.pubTypeList?.pubType)?item.pubTypeList.pubType:[];const kind=kindFromText(`${title} ${types.join(' ')}`);const y=yearOf(item?.pubYear||item?.firstPublicationDate);const org=scrub(item?.journalTitle||item?.publisher||'Europe PMC',300)||'Europe PMC';const abs=scrub(stripHtml(item?.abstractText),1800);out.push({title,url,organization:org,year:y||'Non précisé',year_num:y,kind,abstract:abs,origin:'Europe PMC',dedupe_key:doi?`doi:${doi.toLowerCase()}`:pmid?`pmid:${pmid}`:`url:${canonicalUrl(url)}`})}
  return out;
}

async function fetchPubMed(query:string,pageSize=8):Promise<Source[]>{
  const sp=new URLSearchParams({db:'pubmed',term:query,retmode:'json',retmax:String(pageSize),sort:'pub date',datetype:'pdat',mindate:`${RECENT_FROM_YEAR}/01/01`,maxdate:`${CURRENT_YEAR}/12/31`});
  const sr=await timedFetch(`https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?${sp}`,{headers:{Accept:'application/json'}});if(!sr.ok)throw new Error(`pubmed_search_${sr.status}`);const sj=await sr.json().catch(()=>null);const ids=Array.isArray(sj?.esearchresult?.idlist)?sj.esearchresult.idlist:[];if(!ids.length)return[];
  const sm=new URLSearchParams({db:'pubmed',id:ids.join(','),retmode:'json'});const rr=await timedFetch(`https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?${sm}`,{headers:{Accept:'application/json'}});if(!rr.ok)throw new Error(`pubmed_summary_${rr.status}`);const rj=await rr.json().catch(()=>null);const out:Source[]=[];
  for(const id of ids){const x=rj?.result?.[id];if(!x)continue;const title=scrub(stripHtml(x.title),700);if(!title)continue;const aids=Array.isArray(x.articleids)?x.articleids:[];const doi=String(aids.find((a:any)=>String(a?.idtype).toLowerCase()==='doi')?.value??'').trim();const types=Array.isArray(x.pubtype)?x.pubtype:[];const kind=kindFromText(`${title} ${types.join(' ')}`);const y=yearOf(x.pubdate||x.epubdate);const org=scrub(x.fulljournalname||x.source||'PubMed',300)||'PubMed';const url=`https://pubmed.ncbi.nlm.nih.gov/${id}/`;out.push({title,url,organization:org,year:y||'Non précisé',year_num:y,kind,abstract:'',origin:'PubMed',dedupe_key:doi?`doi:${doi.toLowerCase()}`:`pmid:${id}`})}
  return out;
}

async function fetchClinicalTrials(condition:string,pageSize=12):Promise<Source[]>{
  const sp=new URLSearchParams({format:'json',pageSize:String(pageSize),'query.cond':condition,sort:'LastUpdatePostDate:desc'});
  const res=await timedFetch(`https://clinicaltrials.gov/api/v2/studies?${sp}`,{headers:{Accept:'application/json'}});if(!res.ok)throw new Error(`ctgov_http_${res.status}`);const p=await res.json().catch(()=>null);const rows=Array.isArray(p?.studies)?p.studies:[];const out:Source[]=[];
  for(const s of rows){if(s?.hasResults!==true&&!s?.resultsSection)continue;const ps=s?.protocolSection??{};const id=String(ps?.identificationModule?.nctId??'').trim();const title=scrub(ps?.identificationModule?.briefTitle||ps?.identificationModule?.officialTitle,700);if(!id||!title)continue;const status=ps?.statusModule??{};const resultDate=status?.resultsFirstPostDateStruct?.date||status?.lastUpdatePostDateStruct?.date||'';const y=yearOf(resultDate);const sponsor=scrub(ps?.sponsorCollaboratorsModule?.leadSponsor?.name||'ClinicalTrials.gov',300)||'ClinicalTrials.gov';const abs=scrub(ps?.descriptionModule?.briefSummary,1800);out.push({title,url:`https://clinicaltrials.gov/study/${id}`,organization:sponsor,year:y||'Non précisé',year_num:y,kind:'essai_clinique',abstract:abs,origin:'ClinicalTrials.gov',dedupe_key:`nct:${id.toLowerCase()}`})}
  return out.slice(0,5);
}

function sourceRank(s:Source){const k=s.kind==='recommandation'?0:s.kind==='consensus'?1:s.kind==='revue'?2:3;const origin=s.origin==='Europe PMC'?0:s.origin==='PubMed'?1:2;return[k,-s.year_num,origin]}
function compareSources(a:Source,b:Source){const A=sourceRank(a),B=sourceRank(b);for(let i=0;i<A.length;i++){if(A[i]!==B[i])return A[i]-B[i]}return 0}
async function literature(clean:any):Promise<Source[]>{
  const seed=scrub(clean.assessment||clean.imaging_conclusion||clean.presentation,350);const service=scrub(clean.specialist_service,120);const english=serviceSearchTerms(service);const recent=`FIRST_PDATE:[${RECENT_FROM_YEAR}-01-01 TO ${CURRENT_YEAR}-12-31]`;const guidance='(TITLE:guideline OR TITLE:consensus OR TITLE:recommendation OR TITLE:recommendations OR "practice guideline" OR "clinical practice guideline")';const evidence='(TITLE:"systematic review" OR TITLE:"meta-analysis" OR "systematic review" OR "meta-analysis")';
  const tasks:Promise<Source[]>[]=[
    fetchEuropePmc(`(${english}) AND ${guidance} AND ${recent} sort_date:y`,12),
    fetchEuropePmc(`(${english}) AND ${evidence} AND ${recent} sort_date:y`,10),
    fetchPubMed(`(${english}) AND (Guideline[Publication Type] OR Practice Guideline[Publication Type] OR Consensus Development Conference[Publication Type])`,8),
    fetchPubMed(`(${english}) AND (Systematic Review[Publication Type] OR Meta-Analysis[Publication Type] OR Randomized Controlled Trial[Publication Type])`,10),
    fetchClinicalTrials(english,15)
  ];
  if(seed)tasks.push(fetchEuropePmc(`(${seed}) AND ${recent} sort_date:y`,8));
  const results=await Promise.allSettled(tasks);const map=new Map<string,Source>();for(const r of results)if(r.status==='fulfilled')for(const s of r.value){const k=s.dedupe_key||canonicalUrl(s.url);const old=map.get(k);if(!old||compareSources(s,old)<0)map.set(k,s)}
  let all=[...map.values()].sort(compareSources);
  const topGuidance=all.filter(s=>s.kind==='recommandation'||s.kind==='consensus').slice(0,8);
  const reviews=all.filter(s=>s.kind==='revue').slice(0,6);
  const trials=all.filter(s=>s.kind==='essai_clinique').sort((a,b)=>b.year_num-a.year_num).slice(0,4);
  const selected=new Map<string,Source>();for(const s of [...topGuidance,...reviews,...trials,...all]){if(selected.size>=MAX_SOURCES)break;selected.set(s.dedupe_key||canonicalUrl(s.url),s)}
  return [...selected.values()];
}

function correction(text:string,refs:Source[]){if(!refs.length)return (text+'\n\n§SOURCES§\nRéférences externes indisponibles lors de la génération : contenu pédagogique IA non vérifié. Vérifier les recommandations de référence avant toute décision clinique.').slice(0,9000);return `${text}\n\n§SOURCES§\n${refs.map(r=>`${r.kind}|||${r.title}|||${r.organization}|||${r.year}|||${r.url}`).join('\n')}`.slice(0,9000)}
function parseJsonText(text:string){return JSON.parse(String(text??'').trim().replace(/^```(?:json)?\s*/i,'').replace(/\s*```$/,'').trim())}
const outputSchema={type:'object',additionalProperties:false,required:['qcms'],properties:{qcms:{type:'array',minItems:5,maxItems:5,items:{type:'object',additionalProperties:false,required:['axis','question','options','correct_index','correction','topic','source_indexes'],properties:{axis:{type:'string',enum:AXES},question:{type:'string'},options:{type:'array',minItems:4,maxItems:4,items:{type:'string'}},correct_index:{type:'integer',minimum:0,maximum:3},correction:{type:'string'},topic:{type:'string',enum:TOPICS},source_indexes:{type:'array',minItems:0,maxItems:3,items:{type:'integer',minimum:1,maximum:MAX_SOURCES}}}}}}};
async function finish(admin:any,postId:string,ok:boolean,errorCode?:string){await admin.rpc('clinical_case_finish_qcm_generation',{p_post_id:postId,p_success:ok,p_error_code:errorCode??null})}
async function groqRequest(key:string,prompt:string,strict:boolean,
    maxOutput=GROQ_MAX_OUTPUT){
  const c=new AbortController(),t=setTimeout(()=>c.abort(),GROQ_TIMEOUT_MS);
  try{
    const body:any={
      model:GROQ_MODEL,messages:[{role:'user',content:prompt}],
      temperature:0.2,reasoning_effort:'low',
      max_completion_tokens:maxOutput,stream:false,
      response_format:strict
        ?{type:'json_schema',json_schema:{name:'gardeflow_qcms',strict:true,schema:outputSchema}}
        :{type:'json_object'},
    };
    const res=await fetch('https://api.groq.com/openai/v1/chat/completions',{
      method:'POST',signal:c.signal,
      headers:{Authorization:'Bearer '+key,
        'Content-Type':'application/json',Accept:'application/json'},
      body:JSON.stringify(body),
    });
    return {res,payload:await res.json().catch(()=>null)};
  }finally{clearTimeout(t)}
}

Deno.serve(async(req:Request)=>{
  if(req.method!=='POST')return json({ok:false,error:'method_not_allowed'},405);
  const url=Deno.env.get('SUPABASE_URL'),serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),groqKey=Deno.env.get('GROQ_API_KEY');if(!url||!serviceKey||!groqKey)return json({ok:false,error:'server_configuration_unavailable'},503);
  const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});const supplied=req.headers.get('x-qcm-worker-key')??'';const{data:cfg,error:cfgErr}=await admin.from('clinical_case_qcm_worker_config').select('sync_key').eq('id',true).maybeSingle();if(cfgErr||!cfg||supplied!==String(cfg.sync_key))return json({ok:false,error:'unauthorized'},401);
  const{data:claims,error:claimErr}=await admin.rpc('clinical_case_worker_claim_next');if(claimErr)return json({ok:false,error:'claim_failed'},503);const claim=Array.isArray(claims)?claims[0]:null;if(!claim?.post_id)return json({ok:true,processed:false,status:'idle'});const postId=String(claim.post_id);
  try{
    const sel='id,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan,disposition,specialist_service';const{data:post,error:postErr}=await admin.from('clinical_case_posts').select(sel).eq('id',postId).maybeSingle();if(postErr||!post)throw new Error('case_not_found');const clean=safeCase(post);const sources=await literature(clean);if(!sources.length)console.warn(JSON.stringify({event:'literature_unavailable_graceful_fallback',post_id:postId}));
    const sourceCatalog=sources.map((s,i)=>'['+(i+1)+'] '+s.kind+
      ' '+s.year+' '+scrub(s.title,145)+' '+s.url).join('\n')
      .slice(0,MAX_CATALOG_CHARS);
    const shape='{"qcms":[{"axis":"cours_fondamental","question":"...","options":["...","...","...","..."],"correct_index":0,"correction":"...","topic":"examen","source_indexes":[1]}]}';
    const conciseRules='Tu es enseignant médical francophone. Date 11 octobre 2026. '+
      'Génère EXACTEMENT CINQ QCM, un pour chaque axe dans cet ordre : '+
      AXES.join(', ')+'. Chaque QCM possède 4 options distinctes, UNE seule juste, '+
      'correction médicale contextualisée en 2 à 3 phrases, maximum 65 mots. '+
      'Les questions portent exclusivement sur CE patient : bases, diagnostic, '+
      'examens, prise en charge, puis recommandations. '+
      'N\'invente aucune source ni recommandation récente. '+
      'source_indexes : indices présents dans le catalogue seulement, '+
      'ou [] si absence de références vérifiées. '+
      'Réponds UNIQUEMENT en JSON avec les champs axis, question, options, '+
      'correct_index, correction, topic, source_indexes et la racine qcms.';
    const prompt=radiologyPriorityPolicy+await radiologyAssistantContext(JSON.stringify(clean).slice(0,2200))+conciseRules+
      '\nAXES : '+AXES.join(', ')+
      '\nTOPICS : '+TOPICS.join(', ')+
      '\nCAS ANONYMISÉ : '+JSON.stringify(clean)+
      '\nCATALOGUE DE SOURCES RÉELLES : '+(sourceCatalog||'Indisponible');
    const shorterPrompt=conciseRules+
      '\nAXES : '+AXES.join(', ')+
      '\nTOPICS : '+TOPICS.join(', ')+
      '\nCAS ANONYMISÉ : '+JSON.stringify({
        age_band:clean.age_band,sex:clean.sex,
        presentation:scrub(clean.presentation,280),
        clinical_exam:scrub(clean.clinical_exam,290),
        complementary_exams:scrub(clean.complementary_exams,330),
        assessment:scrub(clean.assessment,340),plan:scrub(clean.plan,260),
      })+
      '\nCATALOGUE DE SOURCES RÉELLES : '+(sourceCatalog.slice(0,700)||'Indisponible');
    if(prompt.length>9200||shorterPrompt.length>5500)
      throw new Error('groq_prompt_budget_exceeded');
    let{res:provider,payload}=await groqRequest(groqKey,prompt,true);
    if(!provider.ok&&provider.status===413){
      console.warn(JSON.stringify({event:'clinical_qcm_413_compact_retry',
        prompt_chars:prompt.length,compact_chars:shorterPrompt.length}));
      ({res:provider,payload}=await groqRequest(
        groqKey,shorterPrompt,true,GROQ_REDUCED_OUTPUT));
    }
    if(!provider.ok&&provider.status===400&&
        String(payload?.error?.code??'')==='json_validate_failed'){
      ({res:provider,payload}=await groqRequest(
        groqKey,shorterPrompt,false,GROQ_REDUCED_OUTPUT));
    }
    if(!provider.ok){
      console.warn(JSON.stringify({
        event:'clinical_qcm_groq_http_error',
        http_status:provider.status,
        retry_after_seconds:Math.max(0,Math.min(86400,Number(provider.headers.get('retry-after'))||0)),
        remaining_requests:provider.headers.get('x-ratelimit-remaining-requests'),
        remaining_tokens:provider.headers.get('x-ratelimit-remaining-tokens'),
        limit_tokens:provider.headers.get('x-ratelimit-limit-tokens'),
        error_code:String(payload?.error?.code||'').slice(0,60),
      }));
      if(provider.status===401||provider.status===403)throw new Error('authorization_failed');
      if(provider.status===429)throw new Error('groq_rate_limited');
      if(provider.status===413)throw new Error('groq_request_too_large');
      if(provider.status===400||provider.status===404)throw new Error('groq_request_invalid');
      throw new Error('groq_provider_unavailable');
    }
    const rawText=payload?.choices?.[0]?.message?.content;if(typeof rawText!=='string'||!rawText.trim())throw new Error('groq_invalid_json');const generated=parseJsonText(rawText),raw=Array.isArray(generated?.qcms)?generated.qcms:[];if(raw.length!==5)throw new Error('invalid_qcm_count');const guidanceIndex=sources.findIndex(s=>s.kind==='recommandation'||s.kind==='consensus');const seen=new Set<string>();
    const normalized=raw.map((q:any,i:number)=>{const axis=String(q?.axis??'').trim();if(axis!==AXES[i])throw new Error('invalid_axis_order');const question=scrub(q?.question,1200),options=Array.isArray(q?.options)?q.options.map((x:any)=>scrub(x,420)).filter(Boolean):[],ci=Number(q?.correct_index),corr=scrub(q?.correction,5500),topic=String(q?.topic??'').trim();if(!question||question.length<12||seen.has(question.toLowerCase())||options.length!==4||new Set(options).size!==4||!Number.isInteger(ci)||ci<0||ci>3||!corr||corr.length<20||!TOPICS.includes(topic))throw new Error(`invalid_qcm_${i+1}`);seen.add(question.toLowerCase());let idxs=Array.isArray(q?.source_indexes)?q.source_indexes.map((x:any)=>Number(x)).filter((x:number)=>Number.isInteger(x)&&x>=1&&x<=sources.length):[];idxs=[...new Set(idxs)].slice(0,3);if(!idxs.length&&sources.length)idxs=[1];if(i===4&&guidanceIndex>=0&&!idxs.includes(guidanceIndex+1))idxs=[guidanceIndex+1,...idxs].slice(0,3);const refs=idxs.map((x:number)=>sources[x-1]).filter(Boolean);return{position:i+1,question,options,correct_index:ci,correction:correction(corr,refs),topic}});
    const{error:commitErr}=await admin.rpc('clinical_case_commit_generated_qcms',{p_post_id:postId,p_qcms:normalized});if(commitErr)throw new Error('database_write_failed');await Promise.all([admin.from('clinical_case_qcms').update({ai_provider:'groq'}).eq('post_id',postId),admin.from('clinical_case_posts').update({qcm_ai_provider:'groq'}).eq('id',postId)]);await finish(admin,postId,true);
    const counts=Object.fromEntries(['Europe PMC','PubMed','ClinicalTrials.gov'].map(o=>[o,sources.filter(s=>s.origin===o).length]));console.log(JSON.stringify({event:'qcm_worker_success',post_id:postId,provider:'groq',model:GROQ_MODEL,qcm_count:5,source_count:sources.length,source_origins:counts,guidance_count:sources.filter(s=>s.kind==='recommandation'||s.kind==='consensus').length,latest_source_year:Math.max(...sources.map(s=>s.year_num),0)}));return json({ok:true,processed:true,status:'ready',post_id:postId,count:5,source_origins:counts});
  }catch(e:any){const code=String(e?.message??'generation_failed').replace(/[^a-zA-Z0-9_:-]/g,'').slice(0,80)||'generation_failed';await finish(admin,postId,false,code).catch(()=>null);console.error(JSON.stringify({event:'qcm_worker_failed',post_id:postId,error_code:code}));return json({ok:false,processed:true,post_id:postId,error:code},code==='groq_rate_limited'?429:503)}
});
