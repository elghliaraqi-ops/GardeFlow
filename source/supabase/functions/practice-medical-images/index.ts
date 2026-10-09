import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import {resolveMedicalPreviews,proxyMedicalImage} from './medical_image_previews.ts';

// Shared Practice media resolver. External public images only; no image
// storage, no untrusted URLs to Groq, no second medical AI reviewer.
const cors={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization,apikey,x-client-info,content-type',
  'Access-Control-Allow-Methods':'GET,POST,OPTIONS',
};
const send=(data:unknown,status=200)=>new Response(JSON.stringify(data),{
  status,headers:{...cors,'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}
});
Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='GET'&&req.method!=='POST')return send({error:'method_not_allowed'},405);
  const url=Deno.env.get('SUPABASE_URL');
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!service)return send({error:'backend_not_configured'},503);
  const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');
  if(!token)return send({error:'unauthorized'},401);
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error}=await admin.auth.getUser(token);
  if(error||!user||user.is_anonymous===true)return send({error:'unauthorized'},401);
  if(req.method==='GET'){
    const asset=new URL(req.url).searchParams.get('asset')||'';
    if(!asset)return send({error:'asset_missing'},400);
    return proxyMedicalImage(asset);
  }
  const body=await req.json().catch(()=>null);
  if(!body||body.action!=='images')return send({error:'invalid_action'},400);
  if(!body.image_request||typeof body.image_request!=='object')return send({error:'image_request_required'},400);
  try{return send(await resolveMedicalPreviews(body.image_request));}
  catch(e){console.error('practice_medical_images',{error:String(e).slice(0,150)});
    return send({images:[],medical_searches:[],unavailable_reason:'external_source_unavailable'});}
});
