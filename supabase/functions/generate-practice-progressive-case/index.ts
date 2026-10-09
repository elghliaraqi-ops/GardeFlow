import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {medicalEvidencePolicy,recentGuidelineCatalog,findOpenverseMedicalPreview} from './medical_evidence_media.ts';
import {progressiveAxes,progressiveJsonContract,validateProgressiveAxisSequence} from './progressive_question_sequence.ts';
import {medicalImageSchema,medicalImagePrompt,medicalImageCorrectionSuffix} from './medical_image_contract.ts';

const topics=['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'];
const specialties=['Chirurgie viscérale','Orthopédie','Cardiologie','Neurologie','Urologie','ORL','Gynécologie','Réanimation','Pneumologie','Gastro-entérologie','Néphrologie','Endocrinologie','Dermatologie','Psychiatrie','Pédiatrie','Ophtalmologie','Neurochirurgie','Chirurgie thoracique','Chirurgie vasculaire','Maladies infectieuses','Médecine interne'];
// Reuse the same clinical dossier fields and Groq Responses contract as generate-random-clinical-case.
const caseTextFields=['location','chief_complaint','interrogatoire','personal_surgical_history',
 'personal_medical_history','family_surgical_history','family_medical_history','consultation_reason',
 'illness_history','clinical_exam','complementary_exams','imaging_conclusion','assessment','plan',
 'specialist_service','hospitalization_service'] as const;
const caseBoolFields=['specialist_opinion_requested','specialist_opinion_done','waiting',
 'prescription_done','discharged','hospitalized'] as const;
const caseProperties:Record<string,unknown>={
 age:{type:'integer',minimum:1,maximum:105},
 sex:{type:'string',enum:['F','M','Autre','Non précisé']}
};
for(const field of caseTextFields)caseProperties[field]={type:'string'};
for(const field of caseBoolFields)caseProperties[field]={type:'boolean'};
const clinicalCaseSchema={type:'object',additionalProperties:false,required:['case'],
 properties:{case:{type:'object',additionalProperties:false,
 required:['age','sex',...caseTextFields,...caseBoolFields],properties:caseProperties}}};
// Exactly the clinicalCaseSchema case fields; no unrelated QCMs in this response.
const clinicalCaseJsonExample={case:{
 age:58,sex:'M',
 ...Object.fromEntries(caseTextFields.map(field=>[field,'REMPLACER par une donnée clinique cohérente'])),
 ...Object.fromEntries(caseBoolFields.map(field=>[field,false]))
}};
const clinicalCaseJsonContract='Répondre par un seul objet JSON contenant uniquement case. '+
 'L’objet case doit avoir exactement les champs '+
 Object.keys((clinicalCaseSchema.properties.case as {properties:Record<string,unknown>}).properties).join(', ')+
 '. Tous les textes sont des chaînes, age est entier, sex vaut F/M/Autre/Non précisé, '+
 'les décisions sont booléennes. Exemple JSON SYNTAXIQUEMENT VALIDE : '+
 JSON.stringify(clinicalCaseJsonExample)+
 '. Remplacer chaque placeholder par des données médicales cohérentes sans recopier les exemples.';

const referenceSchema={type:'object',additionalProperties:false,required:['url'],properties:{url:{type:'string'}}};
const itemSchema={type:'object',additionalProperties:false,required:['axis','question','options','correct_index','correction','topic','references','image_search_query','image_request'],
 properties:{axis:{type:'string',enum:progressiveAxes},question:{type:'string'},options:{type:'array',minItems:4,maxItems:4,items:{type:'string'}},correct_index:{type:'integer',minimum:0,maximum:3},
 correction:{type:'string'},topic:{type:'string',enum:topics},references:{type:'array',minItems:1,maxItems:3,items:referenceSchema},image_search_query:{type:'string'},image_request:medicalImageSchema}};
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



type MedicalLink={stage:number;title:string;url:string;preview_image_url:string;license:string};
type MedicalImageSearch={query:string;label:string;accept:RegExp};
async function verifiedExternalMedia(spec:MedicalImageSearch):Promise<MedicalLink|null>{
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),5500);
 try{
  const args=new URLSearchParams({
   action:'query',format:'json',generator:'search',
   gsrsearch:spec.query,gsrnamespace:'6',gsrlimit:'8',
   prop:'imageinfo',iiprop:'url|mime|extmetadata',iiurlwidth:'600'
  });
  const response=await fetch('https://commons.wikimedia.org/w/api.php?'+args,{
   signal:ctrl.signal,headers:{Accept:'application/json'}
  });
  if(!response.ok)return null;
  const payload=await response.json() as {query?:{pages?:Record<string,{
   title?:string;imageinfo?:{thumburl?:string;descriptionurl?:string;
    mime?:string;extmetadata?:{LicenseShortName?:{value?:string}}}[]
  }>}};
  for(const page of Object.values(payload.query?.pages??{})){
   const title=plain(page.title,180);
   if(!spec.accept.test(title))continue;
   const item=page.imageinfo?.[0];
   if(!item||!/^image\/(png|jpeg|gif|svg\+xml|webp)$/.test(String(item.mime??'')))continue;
   const preview=String(item.thumburl??''),url=String(item.descriptionurl??'');
   const license=plain(item.extmetadata?.LicenseShortName?.value,90);
   if(!/CC[\s-]?(?:BY|0)|public\s*domain|PD-/i.test(license))continue;
   try{
    if(new URL(preview).protocol!=='https:'||
       new URL(preview).hostname!=='upload.wikimedia.org'||
       new URL(url).protocol!=='https:'||
       new URL(url).hostname!=='commons.wikimedia.org')continue;
   }catch{continue;}
   return {stage:1,title:spec.label+' · '+title.replace(/^File:/i,''),
    url,preview_image_url:preview,license};
  }
  return null;
 }catch{return null;}finally{clearTimeout(timer);}
}
async function externalMedicalIllustrations(dossier:Record<string,unknown>):
 Promise<MedicalLink[]>{
 // Generic anatomical/ECG educational material only, not reconstructed patient exams.
 const text=[dossier.complementary_exams,dossier.imaging_conclusion]
  .map(x=>String(x??'').toLowerCase()).join(' ');
 const searches:MedicalImageSearch[]=[];
 // Only illustrate a resting normal/sinus ECG when those findings are actually described.
 // For other ECG findings, omit the thumbnail rather than implying the wrong trace.
 if((/\becg\b|électrocardio|electrocardio/.test(text))&&
    /rythme sinusal|ecg[^.]{0,80}normal|sans[^.]{0,50}décalage/.test(text))
  searches.push({query:'normal sinus rhythm 12 lead ECG',label:'ECG sinusal illustratif',
    accept:/^(?=.*(?:ecg|electrocardio))(?=.*(?:normal|sinus|12.lead))/i});
 if(/coronarograph|cathétérisme coronair|coronary angio|sténose.*coronair/i.test(text))
  searches.push({query:'coronary arteries anatomical illustration',
   label:'Schéma des artères coronaires',accept:/coronary|coronaire/i});
 if(/radiographie|x-ray|radiograph/.test(text)&&searches.length<2)
  searches.push({query:'chest x ray anatomy labeled',label:'Radiographie illustrative',
   accept:/chest.*x.ray|thorax.*radiograph|chest.*radiograph/i});
 if(/irm|mri/.test(text)&&searches.length<2)
  searches.push({query:'brain MRI anatomy',label:'IRM anatomique illustrative',
   accept:/mri|magnetic resonance|irm/i});
 if(/échographie|echographie|ultrasound/.test(text)&&searches.length<2)
  searches.push({query:'ultrasound anatomy medical',label:'Échographie illustrative',
   accept:/ultrasound|ultrason|echograph/i});
 if(/scanner|tomodensitom|ct scan/.test(text)&&searches.length<2)
  searches.push({query:'CT scan anatomy medical',label:'Scanner anatomique illustratif',
   accept:/ct.scan|computed tomography|tomodensitom/i});
 // Parallel, bounded, all-optional external requests. Never store image bytes.
 const found=await Promise.all(searches.slice(0,2).map(async spec=>{
  const primary=await verifiedExternalMedia(spec);
  if(primary)return primary;
  const candidate=await findOpenverseMedicalPreview(spec.query,spec.accept);
  return candidate?{
   stage:1,title:spec.label+' · '+candidate.title+
    ' · '+candidate.creator+' · '+candidate.license,
   url:candidate.source_url,preview_image_url:candidate.preview_url,
   license:candidate.license+' · '+candidate.creator
  }:null;
 }));
 return found.filter((entry):entry is MedicalLink=>entry!==null);
}

const batchSchema={type:'object',additionalProperties:false,required:['qcms'],
 properties:{qcms:{type:'array',minItems:5,maxItems:5,items:itemSchema}}};

// Call the exact Groq Responses API pathway used by the existing fictitious case generator.
// Unlike the previous combined request, this call contains NO QCMs.
function extractCaseOutput(payload:Record<string,unknown>):string {
 if(typeof payload.output_text==='string')return payload.output_text.trim();
 const parts:string[]=[];
 for(const raw of (Array.isArray(payload.output)?payload.output:[])){
  const item=raw as Record<string,unknown>;
  if(item.type!=='message')continue;
  for(const rawPart of (Array.isArray(item.content)?item.content:[])){
   const part=rawPart as Record<string,unknown>;
   if((part.type==='output_text'||part.type==='text')&&typeof part.text==='string')
    parts.push(part.text);
  }
 }
 return parts.join('').trim();
}
async function generateCaseDossier(specialty:string):Promise<Record<string,unknown>> {
 const key=Deno.env.get('GROQ_API_KEY');
 if(!key)throw Error('groq_configuration_missing');
 const model=Deno.env.get('GROQ_CASE_MODEL')?.trim()||'openai/gpt-oss-20b';
 const evidence=await recentGuidelineCatalog(specialty);
 const prompt=medicalEvidencePolicy+'\nRECOMMANDATIONS INDEXÉES :\n'+
  (evidence||'Aucune recommandation actuelle confirmée par la recherche, ne fais pas d’affirmation datée.')+
  '\nCrée UN cas clinique ENTIÈREMENT FICTIF, pédagogique et vraisemblable pour des internes en médecine. '+
  'Spécialité imposée : '+specialty+'. Niveau : intermédiaire ou complexe. '+
  'Pas de nom, initiales, date de naissance, adresse, téléphone ni identifiant réel. '+
  'Rédige en français médical précis, avec signes positifs ET négatifs utiles. '+
  'Remplis toutes les rubriques du formulaire, constantes et biologie chiffrées plausibles, imagerie si utile. '+
  'Examen, résultats, synthèse et conduite à tenir doivent être cohérents. '+
  'Dans plan, détailler décisions de traitement, surveillance et évolution clinique ou suivi. '+
  'Les booléens des décisions doivent correspondre à la prise en charge. '+
  'Aucune fausse bibliographie, pas de conseils pour un vrai patient. '+clinicalCaseJsonContract;
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),45000);
 try{
  const response=await fetch('https://api.groq.com/openai/v1/responses',{
   method:'POST',signal:ctrl.signal,
   headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
   body:JSON.stringify({model,instructions:'Réponds seulement selon le schéma JSON fourni.',
    input:prompt,reasoning:{effort:'low'},text:{format:{
     type:'json_schema',name:'random_clinical_case',schema:clinicalCaseSchema
    }},store:false,max_output_tokens:5500})
  });
  if(!response.ok){
   console.warn('progressive_case_dossier_http',{status:response.status,model});
   if(response.status===429)throw Error('groq_rate_limited');
   if(response.status===401||response.status===403)throw Error('groq_auth_failed');
   throw Error(response.status===400?'groq_request_rejected':'groq_provider_unavailable');
  }
  const payload=await response.json().catch(()=>null) as Record<string,unknown>|null;
  let decoded:Record<string,unknown>;
  try{decoded=JSON.parse(extractCaseOutput(payload??{})) as Record<string,unknown>;}
  catch{throw Error('invalid_case_json');}
  const raw=decoded.case as Record<string,unknown>|undefined;
  if(!raw||typeof raw!=='object')throw Error('invalid_case_format');
  const age=Number(raw.age),sex=plain(raw.sex,20);
  if(!Number.isInteger(age)||age<1||age>105||!['F','M','Autre','Non précisé'].includes(sex))
   throw Error('invalid_case_demographics');
  const result:Record<string,unknown>={age,sex};
  for(const field of caseTextFields)result[field]=plain(raw[field],2600);
  for(const field of caseBoolFields)result[field]=raw[field]===true;
  for(const [field,min] of Object.entries({consultation_reason:15,illness_history:30,
   clinical_exam:30,assessment:20,plan:30})){
   if(String(result[field]).length<min)throw Error('invalid_case_format');
  }
  result.location='Simulation pédagogique · '+specialty;
  const requested=result.specialist_opinion_requested===true;
  result.specialist_service=requested?plain(result.specialist_service,140):'';
  result.specialist_opinion_done=requested&&result.specialist_opinion_done===true;
  if(result.hospitalized===true)result.discharged=false;
  if(result.discharged===true)result.hospitalized=false;
  if(result.hospitalized!==true)result.hospitalization_service='';
  return result;
 }finally{clearTimeout(timer);}
}
function narrativeFromCase(c:Record<string,unknown>):
 {title:string;stem:string;stages:{title:string;narrative:string}[]} {
 const field=(name:string,max=1700)=>plain(c[name],max);
 const stem=plain('Patient fictif de '+String(c.age)+' ans, sexe '+String(c.sex)+
  '. '+field('consultation_reason',500)+'. '+field('illness_history',1200),2400);
 const stages=[
  {title:'Admission et examen clinique',
   narrative:plain(stem+' Examen clinique : '+field('clinical_exam'),2400)},
  {title:'Examens complémentaires et diagnostic',
   narrative:plain('Bilan demandé et obtenu : '+field('complementary_exams')+
    '. Imagerie : '+(field('imaging_conclusion')||'Non indiquée dans ce scénario.')+
    '. Interrogatoire complémentaire : '+field('interrogatoire',800),2400)},
  {title:'Décisions thérapeutiques et conduite à tenir',
   narrative:plain('Synthèse diagnostique : '+field('assessment')+
    '. Stratégie thérapeutique : '+field('plan'),2400)},
  {title:'Évolution, surveillance et suivi',
   narrative:plain('Orientation et évolution du patient fictif : '+
    (c.hospitalized===true?'Hospitalisation en '+field('hospitalization_service',140)+'. ':
     c.discharged===true?'Retour à domicile organisé. ':'Surveillance en cours. ')+
    'Plan de surveillance et suivi : '+field('plan')+
    '. Contexte clinique : '+field('assessment'),2400)}
 ];
 if(stem.length<150||stages.some(stage=>stage.narrative.length<120))
  throw Error('invalid_stage_format');
 return {title:plain('Cas fictif · '+field('chief_complaint',140),180),stem,stages};
}

async function newGroqBatch(
 prompt:string,format:Record<string,unknown>,preferred?:string
):Promise<Record<string,unknown>> {
 const key=Deno.env.get('GROQ_API_KEY');
 if(!key)throw Error('groq_configuration_missing');
 // Independent training uses the smaller model by default; the configured override is optional.
 const configured=(Deno.env.get('GROQ_PROGRESSIVE_CASE_MODEL')??'').trim();
 const primary=preferred??(
  ['openai/gpt-oss-20b','openai/gpt-oss-120b'].includes(configured)
   ?configured:'openai/gpt-oss-20b'
 );
 const models=[primary,primary==='openai/gpt-oss-20b'?'openai/gpt-oss-120b':'openai/gpt-oss-20b'];
 let code='groq_unavailable',rateLimited=0;
 // Complex first-case schemas are more reliable in JSON object mode on GPT-OSS.
 const isCaseFormat=Boolean(
  (format.properties as Record<string,unknown>|undefined)?.case_stages
 );
 for(const model of models){
  for(const strict of [false]){ // JSON object mode avoids Groq strict-schema 400 responses.
   const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),38000);
   try{
    const response=await fetch('https://api.groq.com/openai/v1/chat/completions',{
     method:'POST',signal:ctrl.signal,
     headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
     body:JSON.stringify({
      model,messages:[{role:'user',content:prompt}],
      temperature:0.15,reasoning_effort:'low',reasoning_format:'hidden',
      max_completion_tokens:5200,stream:false,
      response_format:strict
       ?{type:'json_schema',json_schema:{name:'practice_progressive_case_batch',strict:true,schema:format}}
       :{type:'json_object'}
     })
    });
    if(response.status===429){
     rateLimited++;
     const retryAfter=Number(response.headers.get('retry-after')??'');
     console.warn('progressive_groq_rate_limit',{model,
      retry_after_seconds:Number.isFinite(retryAfter)?Math.max(0,Math.min(3600,retryAfter)):null});
     code='groq_rate_limited';
     break; // A different model may have separate available quota; no hot-loop retries.
    }
    if(!response.ok){
     const raw=await response.json().catch(()=>null);
     const reason=String(raw?.error?.code??raw?.error?.type??'').slice(0,70);
     console.warn('progressive_groq_http',{status:response.status,model,reason});
     if(response.status===401||response.status===403)throw Error('groq_auth_failed');
     code=response.status===400?'groq_request_rejected':'groq_provider_unavailable';
     if(strict&&response.status===400)continue; // Unsupported/malformed strict JSON: try JSON mode.
     break;
    }
    const raw=await response.json().catch(()=>null);
    const content=raw?.choices?.[0]?.message?.content;
    if(typeof content==='string'){
     try{
      const parsed=JSON.parse(content);
      if(parsed&&typeof parsed==='object'&&!Array.isArray(parsed))return parsed;
     }catch{/* Validate again using a different output format. */}
    }
    code='groq_invalid_json';
   }catch(err){
    const e=err instanceof Error?err:Error('groq_network_error');
    if(e.message==='groq_auth_failed')throw e;
    code=e.name==='AbortError'?'groq_timeout':e.message;
    console.warn('progressive_groq_exception',{code,model});
    break;
   }finally{clearTimeout(timer);}
  }
 }
 if(rateLimited===models.length)throw Error('groq_rate_limited');
 throw Error(code);
}

async function checkAndFormat(batch:Record<string,unknown>,refs:Ref[],seen:Set<string>,batchIndex:0|1)
 :Promise<Record<string,unknown>[]>{
 if(!Array.isArray(batch.qcms)||batch.qcms.length!==5)throw Error('invalid_generated_question_count');
 if(!validateProgressiveAxisSequence(batch.qcms,batchIndex))throw Error('invalid_clinical_axis_order');
 const map=new Map(refs.map(x=>[canon(x.url),x]));
 const output:Record<string,unknown>[]=[];
 for(const [index,raw] of batch.qcms.entries()){
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
  const failure=question.length<12?'question_short':
   options.length!==4?'option_count':
   options.some(x=>x.length<1)?'option_empty':
   new Set(options.map(cleanKey)).size!==4?'duplicate_options':
   correction.length<25?'correction_short':
   !Number.isInteger(correct)||correct<0||correct>3?'invalid_correct_index':
   !references.length?'unverified_reference':
   !topics.includes(topic)?'invalid_topic':
   seen.has(fingerprint)?'duplicate_question':'';
  if(failure){
   console.warn('progressive_qcm_rejected',{position:index+1,reason:failure});
   throw Error('invalid_generated_questions');
  }
  seen.add(fingerprint);
  output.push({axis:progressiveAxes[batchIndex*5+index],question,options,correct_index:correct,correction,topic,
   references,illustration_query:String(q.image_search_query??''),image_request:q.image_request});
 }
 // Image requests accompany the explanation as JSON metadata only.
 // Images are selected at view-time; no wrong or broken URLs are persisted.
 return output.map(item=>{
  const urls='\n\n§SOURCES§\n'+(item.references as Ref[])
    .map(r=>[r.kind,r.title,r.organization,r.year,r.url].join('|||')).join('\n');
  return {
   question:item.question,options:item.options,correct_index:item.correct_index,
   axis:item.axis,topic:item.topic,
   correction:String(item.correction)+medicalImageCorrectionSuffix(item.image_request,item.illustration_query)+urls
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
 const uid=userData.user?.id;
 if(authErr||!uid)return send(req,{ok:false,error:'auth_failed'},401);
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:profile,error:profileError}=await admin.from('profiles').select('id,account_status').eq('id',uid).maybeSingle();
 if(profileError||!profile||profile.account_status!=='active')return send(req,{ok:false,error:'account_inactive'},403);
 let draftId:string|null=null;
 try {
   // Completely independent from official daily challenges, scores and XP.
   // Validated cases are stored in a private owner-scoped table, never Storage.
   const body=await req.json().catch(()=>({})) as Record<string,unknown>;
   const requestedId=plain(body?.case_id,40);
   let specialty:string;
   let simulated:Record<string,unknown>;
   let caseTitle:string,caseStem:string,stages:{title:string;narrative:string}[];
   if(requestedId){
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestedId))
     return send(req,{ok:false,error:'invalid_case_id'},400);
    const {data:stored,error:readError}=await admin.from('practice_generated_cases')
     .select('id,specialty,case_title,case_stem,case_stages,case_payload,generation_status,questions,created_at')
     .eq('owner_id',uid).eq('id',requestedId).maybeSingle();
    if(readError||!stored)return send(req,{ok:false,error:'case_not_found'},404);
    if(stored.generation_status==='ready')return send(req,{
     ok:true,mode:'cas_progressif_independant',case_id:stored.id,
     created_at:stored.created_at,specialty:stored.specialty,
     case_title:stored.case_title,case_stem:stored.case_stem,
     case_stages:stored.case_stages,case_payload:stored.case_payload,
     questions:stored.questions});
    draftId=stored.id;
    specialty=String(stored.specialty);
    simulated=stored.case_payload as Record<string,unknown>;
    caseTitle=String(stored.case_title);caseStem=String(stored.case_stem);
    stages=stored.case_stages as {title:string;narrative:string}[];
    if(!simulated||typeof simulated!=='object'||!Array.isArray(stages)||stages.length!==4)
     throw Error('saved_dossier_invalid');
    console.info('progressive_case_draft_resumed',{draft:true});
   }else{
    specialty=specialties[numericSeed(casablancaDay()+crypto.randomUUID())%specialties.length];
    // PHASE 1: first generate a full fictional dossier as in random clinical cases.
    simulated=await generateCaseDossier(specialty);
    const display=narrativeFromCase(simulated);
    caseTitle=display.title;caseStem=display.stem;stages=display.stages;
    // Persist this valid dossier BEFORE its QCMs so failures can be resumed later.
    const {data:draft,error:saveError}=await admin.from('practice_generated_cases')
     .insert({owner_id:uid,specialty,case_title:caseTitle,case_stem:caseStem,
      case_stages:stages,case_payload:simulated,generation_status:'pending',questions:[]})
     .select('id').single();
    if(saveError||!draft?.id){
     console.warn('progressive_case_draft_storage_failure',{code:saveError?.code??'empty'});
     throw Error('case_storage_failed');
    }
    draftId=draft.id;
    console.info('progressive_case_draft_saved',{saved:true});
   }
   // Find actual medical references for this scenario, with specialty-level fallback.
   const targetedQuery=plain(simulated.assessment,90);
   let refs=targetedQuery.length>8?await literature(targetedQuery):[];
   if(!refs.length)refs=await literature(specialty);
   if(!refs.length)throw Error('literature_unavailable');
   // PHASE 2: QCMs are about this preexisting simulated clinical dossier, never a course bank.
   const context=JSON.stringify(simulated);
   const refList=refs.slice(0,6).map(r=>[r.title,r.year,r.url].join(' | ')).join('\n');
   const common=medicalEvidencePolicy+'\nGénère EXACTEMENT cinq QCM originaux et CONTEXTUALISÉS à ce patient fictif. '+
    'Chaque question porte sur une décision motivée par les symptômes, constantes, examens ou évolution de CE dossier, '+
    'pas sur un chapitre de cours théorique. '+
    'Chaque QCM doit contenir exactement question, options (4 réponses distinctes), correct_index (0 à 3), '+
    'correction détaillée, topic (motif/symptome/examen/imagerie/synthese/prise_en_charge/orientation/avis_specialise), '+
    'references (1 à 3 objets {url}), image_search_query (vide si non pertinent), image_request avec champs du schéma. '+medicalImagePrompt+' '+
    'Utilise seulement les liens bibliographiques suivants :\n'+refList;
   const early=progressiveJsonContract(0)+'\n'+
    'Génère exactement les QCM 1 à 5, pour CE patient et pas un cours : '+
    '1 SYMPTÔMES : identifier manifestations positives, négatives et signes d’alerte; '+
    '2 EXAMEN CLINIQUE : examen ciblé, constantes et degré d’urgence; '+
    '3 HYPOTHÈSES DIAGNOSTIQUES : diagnostic principal et différentiels plausibles; '+
    '4 CLASSIFICATION / GRAVITÉ : stadification ou score UNIQUEMENT si les critères sont disponibles; '+
    '5 EXAMENS COMPLÉMENTAIRES : choisir et hiérarchiser les examens indiqués. '+
    'Ne révèle jamais traitement final, résultats futurs ni évolution avant leur étape. '+
    common+'\nDOSSIER CLINIQUE FICTIF (source unique) :\n'+context;
   const seen=new Set<string>();
   let questions:Record<string,unknown>[]=[];
   for(let attempt=0;attempt<2;attempt++){
    try{
     const first=await newGroqBatch(early,batchSchema,
      attempt===1?'openai/gpt-oss-120b':undefined);
     const localSeen=new Set<string>();
     const accepted=await checkAndFormat(first,refs,localSeen,0);
     questions=accepted;
     for(const fingerprint of localSeen)seen.add(fingerprint);
     break;
    }catch(err){
     const code=err instanceof Error?err.message:'groq_invalid_response';
     if(['groq_auth_failed','groq_rate_limited','groq_configuration_missing'].includes(code))throw err;
     console.warn('progressive_case_qcm_retry',{code,attempt:attempt+1});
     if(attempt===1)throw err;
    }
   }
   if(Number(questions.length)!==5)throw Error('invalid_generated_question_count');
   const continuation=progressiveJsonContract(1)+'\n'+
    'Toujours le MÊME patient fictif, questions 6 à 10 STRICTEMENT dans cet ordre : '+
    '6 INTERPRÉTATION ET DIAGNOSTIC : interpréter les examens disponibles et retenir le diagnostic; '+
    '7 DÉCISION THÉRAPEUTIQUE : sélectionner une option fondée sur gravité et recommandations; '+
    '8 CONDUITE À TENIR : traitement et intervention éventuelle, contre-indications, orientation; '+
    '9 SURVEILLANCE/RÉÉVALUATION : critères de réponse, signes d’alerte et bilans de contrôle; '+
    '10 COMPLICATIONS ET SUIVI : prévenir les complications et programmer le suivi. '+
    'Ne crée aucun autre patient, aucune question indépendante du dossier. '+
    'Ne répète pas les questions précédentes : '+
    questions.map(x=>String(x.question)).join(' / ')+'. '+common+
    '\nDOSSIER CLINIQUE FICTIF (source unique) :\n'+context;
   let secondBatch:Record<string,unknown>[]|null=null;
   for(let attempt=0;attempt<2;attempt++){
    try{
     const batch=await newGroqBatch(continuation,batchSchema,
      attempt===1?'openai/gpt-oss-120b':undefined);
     const localSeen=new Set(seen);
     secondBatch=await checkAndFormat(batch,refs,localSeen,1);
     for(const fingerprint of localSeen)seen.add(fingerprint);
     break;
    }catch(err){
     const code=err instanceof Error?err.message:'groq_invalid_response';
     if(['groq_auth_failed','groq_rate_limited','groq_configuration_missing'].includes(code))throw err;
     console.warn('progressive_case_second_qcm_retry',{code,attempt:attempt+1});
     if(attempt===1)throw err;
    }
   }
   if(!secondBatch||secondBatch.length!==5)throw Error('invalid_generated_question_count');
   questions.push(...secondBatch);
   if(questions.length!==10)throw Error('invalid_question_count');
   // Optional Wikimedia Commons link metadata only; no remote media file storage.
   const illustrations=await externalMedicalIllustrations(simulated);
   const persistedPayload={...simulated,external_media:illustrations};
   // Finalize the already persisted dossier only when all 10 QCMs pass validation.
   const {data:saved,error:saveErr}=await admin.from('practice_generated_cases')
    .update({questions,case_payload:persistedPayload,generation_status:'ready'})
    .eq('owner_id',uid).eq('id',draftId)
    .select('id,created_at').single();
   if(saveErr||!saved?.id){
    console.warn('progressive_case_storage_failure',{code:saveErr?.code??'empty'});
    throw Error('case_storage_failed');
   }
   console.info('progressive_case_saved',{specialty,question_count:questions.length});
   return send(req,{ok:true,mode:'cas_progressif_independant',
     case_id:saved.id,created_at:saved.created_at,specialty,
     case_title:caseTitle,case_stem:caseStem,case_stages:stages,
     case_payload:persistedPayload,questions});
 }catch(err){
   const code=err instanceof Error?err.message:'case_generation_failed';
   if(draftId){
    const {error:updateErr}=await admin.from('practice_generated_cases')
     .update({generation_status:'failed'}).eq('owner_id',uid).eq('id',draftId)
     .neq('generation_status','ready');
    if(updateErr)console.warn('progressive_case_draft_status_failure',{code:updateErr.code});
   }
   console.warn('independent_case_generation_failure',{code});
   return send(req,{ok:false,error:code,case_id:draftId,
    retryable:!['groq_auth_failed','groq_configuration_missing'].includes(code)},503);
 }
});
