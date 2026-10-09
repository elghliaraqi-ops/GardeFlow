import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const enc = new TextEncoder();

function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? enc.encode(input) : input;
  let binary = '';
  bytes.forEach((b) => binary += String.fromCharCode(b));
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemPkcs8ToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function googleAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemPkcs8ToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(unsigned));
  const assertion = `${unsigned}.${b64url(new Uint8Array(signature))}`;
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!res.ok) throw new Error(`OAuth Google ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.access_token;
}

async function sendFcm(
  sa: any,
  access: string,
  token: string,
  platform: string,
  data: Record<string, string>,
) {
  const message: Record<string, unknown> = { token, data };

  if (platform === 'android') {
    // Data-only: Android must not display this before GardeFlow verifies
    // recipientId in its background isolate.
    message.android = { priority: 'HIGH' };
  } else if (platform === 'ios') {
    message.apns = {
      headers: {
        'apns-priority': '5',
        'apns-push-type': 'background',
      },
      payload: { aps: { 'content-available': 1 } },
    };
  } else {
    message.webpush = {
      headers: { Urgency: 'high' },
      notification: {
        title: data.title,
        body: data.body,
        tag: `${data.kind}:${data.resourceId}`,
      },
    };
  }

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${access}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message }),
    },
  );
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}


Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:corsHeaders});
  if(req.method!=='POST')return Response.json({error:'method_not_allowed'},{status:405,headers:corsHeaders});
  const supabaseUrl=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!supabaseUrl||!key)return Response.json({error:'configuration_unavailable'},{status:503,headers:corsHeaders});
  const admin=createClient(supabaseUrl,key,{auth:{persistSession:false,autoRefreshToken:false}});
  // verify_jwt=false because pg_cron authenticates via Vault-issued bearer-equivalent
  // token, never via a client JWT. Only service_role can invoke validation RPC.
  const token=req.headers.get('X-Practice-Cron-Token')??'';
  if(token.length!==64)return Response.json({error:'forbidden'},{status:403,headers:corsHeaders});
  const check=await admin.rpc('practice_daily_validate_cron',{p_token:token});
  if(check.error||check.data!==true)return Response.json({error:'forbidden'},{status:403,headers:corsHeaders});
  const dateParts=new Intl.DateTimeFormat('en-GB',{
    timeZone:'Africa/Casablanca',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',hourCycle:'h23'
  }).formatToParts(new Date());
  const p=Object.fromEntries(dateParts.map(x=>[x.type,x.value]));
  const day=p.year+'-'+p.month+'-'+p.day;
  if(p.hour!=='08')return Response.json({ok:true,skipped:'outside_local_08h',day},{headers:corsHeaders});
  const rawSa=Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
  if(!rawSa)return Response.json({error:'fcm_configuration_missing'},{status:503,headers:corsHeaders});
  let serviceAccount:any;
  try{serviceAccount=JSON.parse(rawSa);}catch{return Response.json({error:'fcm_configuration_invalid'},{status:503,headers:corsHeaders});}
  let access:string;
  try{access=await googleAccessToken(serviceAccount);}catch{return Response.json({error:'fcm_oauth_failed'},{status:503,headers:corsHeaders});}
  const {data:candidates,error:listError}=await admin.rpc('practice_daily_push_candidates',{p_day:day});
  if(listError||!Array.isArray(candidates))return Response.json({error:'candidate_query_failed'},{status:503,headers:corsHeaders});
  const people=candidates.map((x:{user_id?:string})=>String(x.user_id??'')).filter(Boolean);
  if(!people.length)return Response.json({ok:true,day,users:0,sent:0,failed:0},{headers:corsHeaders});
  let sent=0,failed=0,claimed=0;
  const title='Défi quotidien · GardeFlow Practice';
  const body='Vos 10 QCM du jour sont prêts : cours ou cas clinique. Quel sera votre score ?';
  // Use batches to bound database and FCM concurrency within Edge limits.
  for(let offset=0;offset<people.length;offset+=40){
    const ids=people.slice(offset,offset+40);
    const {data:tokens,error:tokenError}=await admin.from('push_tokens')
      .select('token,owner_id,platform').in('owner_id',ids).limit(1000);
    if(tokenError){failed+=ids.length;continue;}
    const tokenMap=new Map<string,{token:string;platform:string}[]>();
    for(const row of tokens??[]){
      const owner=String(row.owner_id??'');
      if(!tokenMap.has(owner))tokenMap.set(owner,[]);
      tokenMap.get(owner)!.push({token:String(row.token),platform:String(row.platform)});
    }
    for(let i=0;i<ids.length;i+=6){
      await Promise.all(ids.slice(i,i+6).map(async(id)=>{
        const devices=tokenMap.get(id)??[];
        if(!devices.length)return;
        const claim=await admin.rpc('practice_daily_claim_push',{p_user_id:id,p_day:day});
        if(claim.error||claim.data!==true)return;
        claimed++;
        for(const device of devices){
          try{
            const delivery=await sendFcm(serviceAccount,access,device.token,device.platform,{
              title,body,kind:'practice_daily_challenge',resourceId:day,recipientId:id
            });
            if(delivery.ok)sent++;else{
              failed++;
              if(delivery.text.includes('UNREGISTERED')||delivery.text.includes('registration-token-not-registered')){
                await admin.from('push_tokens').delete().eq('token',device.token);
              }
            }
          }catch{failed++;}
        }
      }));
    }
  }
  return Response.json({ok:true,day,eligible:people.length,users_claimed:claimed,sent,failed},{headers:corsHeaders});
});
