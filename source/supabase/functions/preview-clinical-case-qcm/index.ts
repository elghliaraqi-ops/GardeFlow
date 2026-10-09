import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
type Ref={title:string;url:string;kind:string;organization:string;year:string};
type Choice={axis:string;question:string;options:string[];correct_index:number;correction:string;topic:string;references:Ref[];image_search_query:string};
type Item={position:number;question:string;options:string[];correct_index:number;correction:string;topic:string};
const axes=['cours_fondamental','diagnostic','explorations','prise_en_charge','recommandations'] as const;
const topics=['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'] as const;
const kinds=['recommandation','consensus','revue','cours'] as const;
const refSchema={type:'object',additionalProperties:false,required:['title','organization','year','url','kind'],properties:{title:{type:'string'},organization:{type:'string'},year:{type:'string'},url:{type:'string'},kind:{type:'string',enum:kinds}}};
const schema={type:'object',additionalProperties:false,required:['qcms'],properties:{qcms:{type:'array',minItems:5,maxItems:5,items:{type:'object',additionalProperties:false,required:['axis','question','options','correct_index','correction','topic','references','image_search_query'],properties:{
 axis:{type:'string',enum:axes},question:{type:'string'},options:{type:'array',minItems:4,maxItems:4,items:{type:'string'}},
 correct_index:{type:'integer',minimum:0,maximum:3},correction:{type:'string'},topic:{type:'string',enum:topics},
 references:{type:'array',minItems:1,maxItems:3,items:refSchema},image_search_query:{type:'string'}
}}}}};
function clean(x:unknown,n=1600):string {
 let s=String(x??'').replace(/<[^>]*>/g,' ').replace(/[\x00-\x1f]/g,' ').replace(/\s+/g,' ').trim();
 s=s.replace(/\b(?:nom|prénom|prenom|ipp|cin|dossier|adresse|téléphone|telephone|email)\s*[:=-]\s*\S+/gi,'[masqué]')
 .replace(/\b(?:M\.|Mr|Mme|Monsieur|Madame)\s+[A-ZÀ-Ý][A-Za-zÀ-ÿ'’-]{1,40}(?:\s+[A-ZÀ-Ý][A-Za-zÀ-ÿ'’-]{1,40})?/g,'[masqué]')
 .replace(/\b[A-Z]{1,4}\d{5,}\b|\b\d{7,}\b/gi,'[masqué]');
 return s.slice(0,n);
}
function urlKey(x:unknown):string {
 try{const u=new URL(String(x??''));return u.protocol==='https:'?u.origin+u.pathname.replace(/\/+$/,''):'';}catch{return '';}
}
function headers(req:Request):HeadersInit {
 return {'Access-Control-Allow-Origin':req.headers.get('Origin')??'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
}
function response(req:Request,o:Record<string,unknown>,code=200):Response {
 return new Response(JSON.stringify(o),{status:code,headers:{...headers(req),'Content-Type':'application/json','Cache-Control':'no-store'}});
}
async function literature(post:Record<string,unknown>):Promise<Ref[]> {
 const key=clean([post.specialist_service,post.assessment||post.imaging_conclusion].filter(Boolean).join(' '),170);
 if(!key)return [];
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),12000);
 try{
 const q=new URLSearchParams({query:key,format:'json',resultType:'core',pageSize:'18'});
 const res=await fetch('https://www.ebi.ac.uk/europepmc/webservices/rest/search?'+q,{signal:ctrl.signal});
 if(!res.ok)return [];
 const parsed=await res.json() as {resultList?:{result?:Record<string,unknown>[]}};
 const urls=new Set<string>();
 return (parsed.resultList?.result??[]).flatMap((r):Ref[]=>{
 const title=clean(r.title,400),doi=String(r.doi??''),pmid=String(r.pmid??'');
 const url=/^10\.\d{4,9}\//.test(doi)?'https://doi.org/'+doi:/^\d+$/.test(pmid)?'https://europepmc.org/article/MED/'+pmid:'';
 const k=urlKey(url);if(!k||urls.has(k)||!title)return [];urls.add(k);
 const label=(title+' '+String(r.pubTypeList??'')).toLowerCase();
 return [{title,url,kind:/consensus/.test(label)?'consensus':/guideline|recommendation/.test(label)?'recommandation':'revue',
 organization:clean(r.journalTitle||'Europe PMC',120),year:clean(r.pubYear,12)}];
 });
 }catch{return [];}finally{clearTimeout(timer);}
}
async function wikimedia(term:string):Promise<{name:string;url:string;source:string}|null> {
 if(!term.trim())return null;
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),6500);
 try{
 const q=new URLSearchParams({action:'query',format:'json',origin:'*',generator:'search',gsrsearch:clean(term,120),gsrnamespace:'6',gsrlimit:'2',prop:'imageinfo',iiprop:'url',iiurlwidth:'540'});
 const res=await fetch('https://commons.wikimedia.org/w/api.php?'+q,{signal:ctrl.signal});
 if(!res.ok)return null;
 const data=await res.json() as {query?:{pages?:Record<string,{title?:string;imageinfo?:{thumburl?:string;descriptionurl?:string}[]}>}};
 for(const p of Object.values(data.query?.pages??{})){
 const u=String(p.imageinfo?.[0]?.thumburl??''),s=String(p.imageinfo?.[0]?.descriptionurl??'');
 try{if(new URL(u).protocol==='https:'&&new URL(u).hostname==='upload.wikimedia.org'&&new URL(s).protocol==='https:'&&new URL(s).hostname==='commons.wikimedia.org')return {name:clean(p.title,120),url:u,source:s};}
 catch{continue;}
 }return null;
 }catch{return null;}finally{clearTimeout(timer);}
}
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:headers(req)});
 if(req.method!=='POST')return response(req,{ok:false,error:'method_not_allowed'},405);
 const origin=req.headers.get('Origin')??'',allowed=(Deno.env.get('GARDEFLOW_ALLOWED_ORIGINS')??'').split(',').map(x=>x.trim()).filter(Boolean);
 if(origin&&allowed.length>0&&!allowed.includes(origin))return response(req,{ok:false,error:'origin_not_allowed'},403);
 const dbUrl=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 const auth=req.headers.get('Authorization')??'';
 if(!auth.startsWith('Bearer '))return response(req,{ok:false,error:'authentication_required'},401);
 if(!dbUrl||!anon||!service)return response(req,{ok:false,error:'configuration_unavailable'},503);
 const caller=createClient(dbUrl,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const admin=createClient(dbUrl,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const who=await caller.auth.getUser(),uid=who.data.user?.id;
 if(who.error||!uid)return response(req,{ok:false,error:'authentication_failed'},401);
 const {data:profile}=await admin.from('profiles').select('id,role,account_status').eq('id',uid).maybeSingle();
 if(!profile||profile.account_status!=='active')return response(req,{ok:false,error:'account_inactive'},403);
 const body=await req.json().catch(()=>null) as Record<string,unknown>|null;
 if(!body)return response(req,{ok:false,error:'invalid_request'},400);
 const postId=String(body.post_id??'');
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
 if(!uuid.test(postId))return response(req,{ok:false,error:'invalid_post_id'},400);
 const {data:post}=await admin.from('clinical_case_posts')
 .select('id,author_id,published_at,specialist_service,age_band,sex,presentation,history,clinical_exam,complementary_exams,imaging_conclusion,assessment,plan')
 .eq('id',postId).maybeSingle();
 if(!post||!post.published_at)return response(req,{ok:false,error:'case_not_ready'},404);
 if(post.author_id!==uid&&profile.role!=='admin')return response(req,{ok:false,error:'authorization_failed'},403);
 const action=String(body.action??'preview');
 if(action==='confirm'||action==='discard'){
 const previewId=String(body.preview_id??'');
 if(!uuid.test(previewId))return response(req,{ok:false,error:'invalid_preview_id'},400);
 const method=action==='confirm'?'clinical_case_confirm_qcm_preview':'clinical_case_discard_qcm_preview';
 const {data,error}=await admin.rpc(method,{p_post_id:postId,p_user_id:uid,p_preview_id:previewId});
 if(error)return response(req,{ok:false,error:'preview_expired_or_invalid'},409);
 return response(req,{ok:true,status:action==='confirm'?'ready':'discarded',...(action==='confirm'?{count:Number(data)}:{})});
 }
 if(action!=='preview')return response(req,{ok:false,error:'invalid_action'},400);
 const qty=Number(body.quantity),level=String(body.difficulty??'');
 if(![5,10,20].includes(qty)||!['facile','intermediaire','avance'].includes(level))
 return response(req,{ok:false,error:'invalid_parameters'},400);
 const groq=Deno.env.get('GROQ_API_KEY');
 if(!groq)return response(req,{ok:false,error:'groq_unavailable'},503);
 const {data:existing,error:readErr}=await admin.from('clinical_case_qcms').select('question,position').eq('post_id',postId).order('position');
 if(readErr)return response(req,{ok:false,error:'database_unavailable'},503);
 if((existing??[]).length<5||(existing??[]).length+qty>100)
 return response(req,{ok:false,error:'qcm_limit_reached'},409);
 const claim=await admin.rpc('clinical_case_claim_qcm_extension',{p_post_id:postId,p_user_id:uid});
 if(claim.error||!Array.isArray(claim.data)||claim.data.length===0)
 return response(req,{ok:false,error:'generation_guard_unavailable'},503);
 const gate=claim.data[0] as {claimed:boolean;error_code?:string;retry_after?:string};
 if(!gate.claimed)return response(req,{ok:false,error:gate.error_code??'generation_in_progress',retry_after:gate.retry_after},gate.error_code==='extension_cooldown'?429:409);
 let done=false;
 try{
 const refs=await literature(post);if(!refs.length)throw Error('literature_sources_unavailable');
 const byUrl=new Map(refs.map(r=>[urlKey(r.url),r]));
 const catalog=refs.map(r=>[r.kind,r.title,r.organization,r.year,r.url].join(' | ')).join('\n');
 const past=(existing??[]).map(x=>clean(x.question,300));
 const proposed:Item[]=[];
 const model=String(Deno.env.get('GROQ_TEXT_MODEL')??'').trim()||'openai/gpt-oss-120b';
 const context=JSON.stringify({service:clean(post.specialist_service,140),age:clean(post.age_band,50),sex:clean(post.sex,30),
 presentation:clean(post.presentation),history:clean(post.history),exam:clean(post.clinical_exam),
 complementary:clean(post.complementary_exams),imaging:clean(post.imaging_conclusion),assessment:clean(post.assessment),plan:clean(post.plan)});
 for(let part=0;part<qty/5;part++){
 const forbidden=past.concat(proposed.map(q=>q.question)).slice(-100).join('\n');
 const prompt='Génère exactement 5 QCM médicaux de niveau '+level+' (facile=externat, intermediaire=internat, avance=expert), en français. 4 propositions, une seule réponse, correction précise 3-6 phrases et références exclusivement parmi Europe PMC. Axes dans cet ordre: '+axes.join(', ')+'. Recherche image_search_query en anglais si pertinente, sinon chaîne vide. Aucune donnée personnelle. Ne reproduis pas les questions déjà écrites. JSON strict.\nCAS ANONYMISÉ:\n'+context+'\nSOURCES:\n'+catalog+'\nNE PAS RÉPÉTER:\n'+forbidden;
 const ctrl=new AbortController(),timer=setTimeout(()=>ctrl.abort(),55000);let remote:Response;
 try{remote=await fetch('https://api.groq.com/openai/v1/chat/completions',{method:'POST',signal:ctrl.signal,headers:{Authorization:'Bearer '+groq,'Content-Type':'application/json'},
 body:JSON.stringify({model,messages:[{role:'user',content:prompt}],temperature:0.2,reasoning_effort:'medium',reasoning_format:'hidden',stream:false,max_completion_tokens:9500,
 response_format:{type:'json_schema',json_schema:{name:'practice_preview',strict:true,schema}}})});}
 finally{clearTimeout(timer);}
 const raw=await remote.json().catch(()=>null);
 if(!remote.ok)throw Error(remote.status===429?'groq_rate_limited':'groq_unavailable');
 const content=raw?.choices?.[0]?.message?.content;
 const decoded=JSON.parse(typeof content==='string'?content:Array.isArray(content)?content.map((v:{text?:string})=>v.text??'').join(''):'') as {qcms?:Choice[]};
 if(!Array.isArray(decoded.qcms)||decoded.qcms.length!==5)throw Error('invalid_qcm_count');
 for(let i=0;i<5;i++){
 const q=decoded.qcms[i],question=clean(q.question,1200),cor=clean(q.correction,5500);
 const opts=Array.isArray(q.options)?q.options.map(x=>clean(x,420)):[];
 const sources=Array.isArray(q.references)?q.references.flatMap((r):Ref[]=>{const found=byUrl.get(urlKey(r.url));return found?[found]:[];}):[];
 const uniqueRefs=[...new Map(sources.map(x=>[x.url,x])).values()].slice(0,3);
 if(q.axis!==axes[i]||question.length<12||cor.length<20||opts.length!==4||new Set(opts).size!==4||
 !Number.isInteger(q.correct_index)||q.correct_index<0||q.correct_index>3||!topics.includes(q.topic as typeof topics[number])||!uniqueRefs.length)
 throw Error('invalid_generated_qcm');
 const normalize=(s:string)=>s.toLowerCase().replace(/\s+/g,' ').trim();
 if(past.some(x=>normalize(x)===normalize(question))||proposed.some(x=>normalize(x.question)===normalize(question)))throw Error('duplicate_questions');
 const image=q.image_search_query?await wikimedia(q.image_search_query):null;
 const links=image?'\n\n§IMAGES§\n'+[image.name,image.url,image.source].join('|||'):'';
 const correction=(cor+links+'\n\n§SOURCES§\n'+uniqueRefs.map(x=>[x.kind,x.title,x.organization,x.year,x.url].join('|||')).join('\n')).slice(0,11000);
 proposed.push({position:proposed.length+1,question,options:opts,correct_index:q.correct_index,correction,topic:q.topic});
 }
 }
 const staged=await admin.rpc('clinical_case_stage_qcm_preview',{p_post_id:postId,p_user_id:uid,p_qcms:proposed,p_difficulty:level});
 if(staged.error||!staged.data)throw Error('preview_staging_failed');
 done=true;
 return response(req,{ok:true,status:'preview',preview_id:staged.data,quantity:qty,difficulty:level,expires_in_minutes:15,
 questions:proposed.map(({question,options,topic})=>({question,options,topic}))});
 }catch(e){
 const code=e instanceof Error?e.message:'generation_failed';
 return response(req,{ok:false,error:['literature_sources_unavailable','groq_rate_limited','groq_unavailable','duplicate_questions','invalid_generated_qcm','invalid_qcm_count','preview_staging_failed'].includes(code)?code:'generation_failed'},503);
 }finally{
 if(!done){try{await admin.rpc('clinical_case_finish_qcm_extension',{p_post_id:postId,p_success:false,p_error_code:'preview_failed'});}catch(_){/* Best-effort unlock. */}}
 }
});
