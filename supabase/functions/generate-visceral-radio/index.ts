import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { generationContract, type GenerationContract } from './generation_contract.ts';
import { resolveMedicalPreviews } from './medical_image_previews.ts';

// GardeFlow Practice · Viscéral × Radio. Private, on-demand generation.
// Only technical JSON parsing/count checks; no secondary medical reviewer.
const OWNER = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c';
const TABLE = 'practice_visceral_radio_sessions';
const topics = [
  'Appendicite aiguë et appendicectomie','Occlusion du grêle sur bride','Hernie inguinale et cure TAPP',
  'Hernie étranglée','Cholécystite aiguë et cholécystectomie','Lithiase de la voie biliaire principale',
  'Angiocholite aiguë','Pancréatite aiguë','Nécrose pancréatique infectée','Cancer de la tête du pancréas',
  'Cancer du rectum et IRM de stadification','Cancer du côlon droit','Diverticulite sigmoïdienne compliquée',
  'Péritonite par perforation digestive','Ulcère gastroduodénal perforé','Cancer gastrique',
  'Hémorragie digestive haute','Achalasie et myotomie','Reflux gastro-œsophagien et fundoplicature',
  'Hernie hiatale para-œsophagienne','Ischémie mésentérique aiguë','Traumatisme splénique',
  'Abcès hépatique','Carcinome hépatocellulaire et résection hépatique','Métastases hépatiques colorectales',
  'Kyste hydatique hépatique','Cholangiocarcinome hilaire','Fistule digestive postopératoire',
  'Fuite anastomotique colorectale','Occlusion colique tumorale','Maladie de Crohn et résection iléocæcale',
  'Rectocolite hémorragique et colectomie','Hémorroïdes et complications','Fissure et fistule anales',
  'Goitre multinodulaire et thyroïdectomie','Tumeur surrénalienne et surrénalectomie',
  'Éventration et reconstruction pariétale','Abcès intra-abdominal postopératoire',
  'Syndrome du compartiment abdominal','Traumatisme abdominal fermé et TDM'
];
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, x-client-info, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
function answer(body: unknown, status=200): Response { return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}}); }
function str(v: unknown, max=20000):string { return String(v??'').slice(0,max); }
// Never clip a JSON string in the middle of a quotation/escape sequence.
// The context sent to Groq always remains a valid JSON document.
function compact(value: unknown, maxChars = 26000): string {
  const json = JSON.stringify(value ?? null);
  if (json.length <= maxChars) return json;
  for (const limit of [3200, 2000, 1200, 600, 300, 150]) {
    const prune = (item: any): any => {
      if (typeof item === 'string') return item.slice(0, limit);
      if (Array.isArray(item)) return item.map(prune);
      if (item && typeof item === 'object') {
        return Object.fromEntries(Object.entries(item).map(([key, content]) => [key, prune(content)]));
      }
      return item;
    };
    const candidate = JSON.stringify(prune(value));
    if (candidate.length <= maxChars) return candidate;
  }
  // Retain a valid JSON wrapper even for unexpectedly oversized input.
  return JSON.stringify({ abridged_context: json.slice(0, maxChars - 150) });
}

function extract(payload:any): string {
  if(typeof payload?.output_text==='string')return payload.output_text;
  for(const item of payload?.output??[])for(const c of item?.content??[])if(typeof c?.text==='string')return c.text;
  return '';
}
async function groq(contract: GenerationContract, prompt: string) {
  const key = Deno.env.get('GROQ_API_KEY');
  if (!key) throw new Error('groq_key_missing');
  // Strict JSON Schema is available for these models; never silently fall
  // back to best-effort JSON (the source of json_validate_failed in Practice).
  const model = Deno.env.get('GROQ_TEXT_MODEL') || 'openai/gpt-oss-120b';
  if (!['openai/gpt-oss-120b', 'openai/gpt-oss-20b'].includes(model)) {
    throw new Error('groq_model_without_strict_json_schema_support');
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 110000);
  try {
    const payload = {
      model,
      messages: [
        {
          role: 'system',
          content: 'Tu es enseignant universitaire en chirurgie viscérale et radiologie. ' +
            'Tu produis uniquement du JSON conforme au contrat partagé. ' +
            'Les détails médicaux suivent le cas fourni, sans invention de source.',
        },
        { role: 'user', content: prompt + '\n\n' + contract.outputInstructions },
      ],
      response_format: {
        type: 'json_schema',
        json_schema: {
          name: contract.name,
          strict: true,
          schema: contract.schema,
        },
      },
      reasoning_effort: 'medium',
      max_completion_tokens: 20000,
      stream: false,
    };
    const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: 'Bearer ' + key,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    const data = await response.json().catch(() => null);
    if (!response.ok) {
      const code = str(data?.error?.code || data?.error?.type || 'unknown_error', 100);
      throw new Error('groq_http_' + response.status + ':' + code);
    }
    if (data?.choices?.[0]?.finish_reason === 'length') {
      throw new Error('groq_output_token_limit');
    }
    const raw = data?.choices?.[0]?.message?.content;
    if (typeof raw !== 'string' || !raw.trim()) throw new Error('groq_empty_response');
    try {
      return JSON.parse(raw);
    } catch (_) {
      // Technical failure only: no independent medical/content reviewing.
      throw new Error('groq_invalid_json_response');
    }
  } finally {
    clearTimeout(timer);
  }
}

async function guidelines(topic:string):Promise<string> {
  // Retrieval is input context, not a separate verification/reviewer pipeline.
  const query='('+topic+') AND (GUIDELINE OR CONSENSUS OR RECOMMENDATION)';
  try{
    const u='https://www.ebi.ac.uk/europepmc/webservices/rest/search?'+new URLSearchParams({query,format:'json',pageSize:'5',sort:'FIRST_PDATE_D desc'}).toString();
    const r=await fetch(u,{signal:AbortSignal.timeout(6500)});
    if(!r.ok)return 'Aucune référence en ligne fournie. Ne prétends pas avoir vérifié une mise à jour.';
    const d=await r.json();
    return (d?.resultList?.result??[]).map((x:any)=>[str(x.title,230),str(x.authorString,130),str(x.firstPublicationDate,25),x.doi?'https://doi.org/'+x.doi:'https://europepmc.org/article/MED/'+x.id].join(' | ')).join('\n').slice(0,2800) || 'Aucune recommandation vérifiée fournie.';
  }catch(_){return 'Aucune recommandation récupérée. Ne prétends pas avoir vérifié les dernières mises à jour.';}
}
const medicalRules=[
 'Tu es professeur de chirurgie viscérale et radiologue abdominal. Enseigne à un résident de chirurgie sur cinq ans, en français.',
 'Allie systématiquement chirurgie viscérale, radiologie, anatomie et techniques opératoires.',
 'Applique les recommandations les plus récentes dont tu disposes; ne dis jamais avoir vérifié une source non fournie.',
 'Ne crée ni citation ni année ni lien fictif. Distingue consensus, controverse et incertitude.',
 'Pour les images: fournis seulement des requêtes de recherche et des descriptions précises, jamais des URL.',
 'Les images doivent correspondre aux signes radiologiques/techniques discutés et servir d’illustration externe, pas d’image du patient fictif.',
 'Ne fais aucun contrôle indépendant après génération; auto-cohérence interne dans ta production.'
].join('\n');
function sourcePrompt(topic:string, refs:string){return medicalRules+'\nSUJET CENTRAL (IMMUTABLE): '+topic+'\nRÉFÉRENCES RÉCUPÉRÉES (ne cite que des références réellement pertinentes):\n'+refs+'\n';}
function validQuestions(obj:any,count:number,phaseLimit=4) {
  if(!Array.isArray(obj?.questions)||obj.questions.length!==count)throw new Error('invalid_question_count');
  for(const q of obj.questions) {
    if(!Array.isArray(q.options)||q.options.length!==5||q.options.map((o:any)=>o.key).join('')!=='ABCDE'||!q.options.some((o:any)=>o.correct===true))throw new Error('invalid_question_format');
    if(!Number.isInteger(q.phase)||q.phase<1||q.phase>phaseLimit)throw new Error('invalid_question_phase');
  }
}
function sanitized(x:any):any {
  if(Array.isArray(x))return x.map(sanitized);
  if(x&&typeof x==='object') {
    const out:any={};
    for(const [k,v]of Object.entries(x))if(!/(^|_)(image_url|thumbnail_url|preview_url|external_image_url)$/i.test(k))out[k]=sanitized(v);
    return out;
  }
  return x;
}
Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return answer({error:'method_not_allowed'},405);
  const url=Deno.env.get('SUPABASE_URL'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!service)return answer({error:'backend_not_configured'},503);
  const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');
  if(!token)return answer({error:'unauthorized'},401);
  const db=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:authError}=await db.auth.getUser(token);
  if(authError||!user)return answer({error:'unauthorized'},401);
  if(user.id!==OWNER)return answer({error:'forbidden'},403);
  try{
    const input=await req.json().catch(()=>({})),action=str(input.action,40),id=str(input.id,45);
    if(action==='images')return answer(await resolveMedicalPreviews(str(input.query,240),str(input.modality,60)));
    if(action==='list'){
      const {data,error}=await db.from(TABLE).select('*').eq('owner_id',user.id).order('created_at',{ascending:false}).limit(80);
      if(error)throw error;
      return answer({sessions:data});
    }
    if(action==='create') {
      const {data:recent}=await db.from(TABLE).select('topic').eq('owner_id',user.id).order('created_at',{ascending:false}).limit(8);
      const avoid=new Set((recent||[]).map((x:any)=>x.topic));
      const candidates=topics.filter(t=>!avoid.has(t));
      const pool=candidates.length?candidates:topics;
      const topic=pool[crypto.getRandomValues(new Uint32Array(1))[0]%pool.length];
      const evidence=await guidelines(topic);
      const prompt=sourcePrompt(topic,evidence)+
        '\nMODE FICHE: rédige un cours synthétique mais complet en 10 sections : définition, anatomie, physiopathologie, clinique, biologie, radiologie (protocoles, sémiologie, complications), prise en charge actualisée, techniques opératoires étape par étape, suites/complications, dix points-clés. Chaque section donne du contenu substantiel, précis et utile au bloc. Le contenu image_requests décrit les signes à illustrer. study_core condense les notions à utiliser pour les QCM.';
      const fiche=sanitized(await groq(generationContract('fiche'),prompt));
      if(!fiche?.title||!Array.isArray(fiche?.sections))throw new Error('incomplete_fiche');
      const {data,error}=await db.from(TABLE).insert({owner_id:user.id,topic,title:str(fiche.title,220),fiche,medical_sources:evidence}).select().single();
      if(error)throw error;
      return answer({session:data});
    }
    if(!/^[0-9a-f-]{36}$/i.test(id))return answer({error:'invalid_id'},400);
    const {data:session,error:readError}=await db.from(TABLE).select('*').eq('id',id).eq('owner_id',user.id).single();
    if(readError||!session)return answer({error:'session_not_found'},404);
    let patch:any={updated_at:new Date().toISOString()};
    if(action==='course_qcms'){
      const existing=Array.isArray(session.course_qcms)?session.course_qcms:[];
      if(existing.length>=20)return answer({session});
      const count=Math.min(10,20-existing.length);
      const prompt=sourcePrompt(session.topic,session.medical_sources||'')+
        '\nMODE QCM DE FICHE: EXACTEMENT '+count+' QCM, cinq propositions A-E, une ou plusieurs réponses exactes, expliquer individuellement chaque proposition et donner une explication synthétique. Les QCM portent EXCLUSIVEMENT sur le contenu de la fiche, pas sur un autre sujet. Mélange anatomie, chirurgie, radiologie, techniques. category précise le domaine. phase=1 pour tous les QCM de cours. Aucune redite.\nFICHE:\n'+compact(session.fiche,34000)+
        '\nQUESTIONS DÉJÀ CRÉÉES:\n'+compact(existing.map((q:any)=>q.statement),4000);
      const produced=await groq(generationContract('course_qcms',{count}),prompt);
      validQuestions(produced,count);
      patch.course_qcms=[...existing,...sanitized(produced.questions)];
    }else if(action==='case'){
      if(session.case_data)return answer({session});
      const prompt=sourcePrompt(session.topic,session.medical_sources||'')+
        '\nMODE CAS CLINIQUE: construis un patient FICTIF, même sujet médical exact que la fiche. Quatre étapes chronologiques: (1) admission/examen, (2) biologie et imagerie, (3) diagnostic/prise en charge/intervention, (4) suites/complications/suivi. Les décisions respectent les recommandations. Radiologie réellement centrale, prévoir images de sémiologie qui correspondent à ton scénario; les images sont externes, illustratives, jamais du patient fictif. Ne révèle pas le diagnostic dans la phase 1. Le dossier complet contient le diagnostic pour les générations ultérieures. Propose recommended_qcms 10 (simple), 15 (intermédiaire) ou 20 (complexe).\nSYNTHÈSE FICHE:\n'+compact(session.fiche?.study_core,9000);
      const scenario=sanitized(await groq(generationContract('case'),prompt));
      if(!Array.isArray(scenario.stages)||scenario.stages.length!==4)throw new Error('invalid_case_stages');
      patch.case_data=scenario;patch.case_target=scenario.recommended_qcms;
    }else if(action==='case_qcms'){
      if(!session.case_data)return answer({error:'case_required'},409);
      const existing=Array.isArray(session.case_qcms)?session.case_qcms:[];
      const target=[10,15,20].includes(session.case_target)?session.case_target:10;
      if(existing.length>=target)return answer({session});
      const count=Math.min(10,target-existing.length);
      const offset=existing.length;
      const phaseSequence=Array.from({length:count},(_,i)=>Math.min(4,1+Math.floor((offset+i)/target*4)));
      const prompt=sourcePrompt(session.topic,session.medical_sources||'')+
        '\nMODE QCM DE CAS: EXACTEMENT '+count+' QCM, cinq propositions A-E et corrections détaillées par proposition. Il s’agit du MÊME PATIENT de ce dossier. Les questions suivent la chronologie clinique et concernent examen, signes de gravité, bilan, imagerie, diagnostic, conduite à tenir, intervention, suivi. Ne formule AUCUNE question générique hors cas. Respecte la séquence obligatoire des phase par question: '+phaseSequence.join(',')+'. La phase correspond à la partie du cas utilisable. Jamais de révélation d’un événement futur dans la question ou sa correction. Rattache chaque proposition aux faits du patient. image_requests pour questions d’imagerie.\nDOSSIER COMPLET (NE PAS divulguer précocement):\n'+compact(session.case_data,31000)+
        '\nQUESTIONS PRÉCÉDENTES:\n'+compact(existing.map((q:any)=>q.statement),4000);
      const produced=await groq(generationContract('case_qcms',{count,phases:phaseSequence}),prompt);
      validQuestions(produced,count);
      produced.questions.forEach((q:any,i:number)=>{q.phase=phaseSequence[i];});
      patch.case_qcms=[...existing,...sanitized(produced.questions)];
    }else if(action==='progress'){
      patch.progress={...(session.progress||{}),...(input.progress||{})};
    }else return answer({error:'unknown_action'},400);
    const {data,error}=await db.from(TABLE).update(patch).eq('id',session.id).eq('owner_id',user.id).select().single();
    if(error)throw error;
    return answer({session:data});
  }catch(e){
    const msg=str((e as Error).message,260);
    console.error('visceral_radio_error',{error:msg});
    return answer({error:'generation_failed',detail:msg},502);
  }
});