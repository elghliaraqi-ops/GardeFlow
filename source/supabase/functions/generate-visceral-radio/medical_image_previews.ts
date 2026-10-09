/**
 * Viscéral × Radio: visual search constrained by the SAME image_request
 * defined by Groq's JSON schema/prompt. Medical content is not re-reviewed
 * by a second model. False-positive image matches are suppressed.
 * Links and pixels are never saved in Supabase tables or Storage.
 */
export type MedicalImageRequest = {
  query: string;
  modality: string;
  purpose: string;
  image_type: 'anatomical_diagram'|'radiology_scan'|'operative_diagram'|'clinical_photo';
  anatomy: string;
  plane: 'axial'|'sagittal'|'coronal'|'multiplanar'|'not_applicable';
  required_features: string[];
  excluded_features: string[];
};
export type ImagePreview = {
  thumbnail:string; full:string; source:string;
  title:string; creator:string; license:string; provider:string;
  description:string;
};

const SEARCH_LIMIT=24;
const REQUEST_HEADERS={Accept:'application/json','User-Agent':'GardeFlowPractice/1.1 (https://github.com/elghliaraqi-ops/GardeFlow; medical-learning previews)'};
const MAX_BYTES=12*1024*1024;
const banned=/(?:book\s*cover|cover\s*of|annual\s*report|costs?\s+and\s+effectiveness|screening\s+report|congress|advertis|financial|conference\s*proceedings|poster\s*session|booklet|textbook\s*cover|national\s+cancer\s+institute\s+report|pdf\s+page|magazine|statistical\s+graph|brochure|front\s+page|journal\s+cover)/i;
// Additional trusted image CDNs used by open-license medical publishers and Openverse.
const clinicalHosts=new Set([
 'upload.wikimedia.org','live.staticflickr.com','commons.wikimedia.org',
 'api.openverse.org','images.openverse.org',
 'cdn.ncbi.nlm.nih.gov','pmc.ncbi.nlm.nih.gov',
 'images.squarespace-cdn.com','static1.squarespace.com',
 'i0.wp.com','i1.wp.com','i2.wp.com','i3.wp.com',
 'images.pexels.com','images.unsplash.com',
]);
const openversePreviewPath=/^\/v1\/images\/[a-f\d-]{36}\/thumb\/?$/i;
export function allowedAsset(raw: string) {
  try {
    const uri=new URL(raw);
    if(uri.protocol!=='https:'||uri.username||uri.password||uri.port)return false;
    if(!clinicalHosts.has(uri.hostname.toLowerCase()))return false;
    if(uri.pathname.length>1100 || /%2e|%2f|%5c/i.test(raw))return false;
    if(uri.searchParams.has('download'))return false;
    if(uri.hostname==='api.openverse.org'){
      // Only the documented image-thumbnail endpoint, never arbitrary API paths.
      return openversePreviewPath.test(uri.pathname) &&
        [...uri.searchParams.keys()].every(k=>k==='full_size');
    }
    if(uri.hostname==='upload.wikimedia.org' &&
       !uri.pathname.startsWith('/wikipedia/commons/'))return false;
    return /\.(?:jpg|jpeg|png|webp)(?:$)/i.test(uri.pathname);
  }catch(_){return false;}
}
const clean=(value:unknown,length=220)=>String(value??'').replace(/<[^>]*>/g,' ')
  .replace(/&[^;\s]+;/g,' ').replace(/\s+/g,' ').trim().slice(0,length);
const ascii=(value:unknown)=>clean(value,700).normalize('NFD')
  .replace(/[\u0300-\u036f]/g,'').toLowerCase();
const hasAny=(value:string,terms:string[])=>terms.some(x=>value.includes(x));
function terms(request:string){
  return ascii(request).split(/[^a-z0-9]+/).filter(x=>x.length>=4 &&
    !['with','show','illustrer','image','medical','medicale','example','orientation','showing',
      'imaging','high','resolution','signal','delimitation','features','required','type'].includes(x)).slice(0,8);
}
export function legacyImageRequest(input:any):MedicalImageRequest {
  const query=clean(input?.query,300);
  const purpose=clean(input?.purpose||query,280);
  const modality=clean(input?.modality,80);
  const raw=ascii(query+' '+purpose+' '+modality);
  const rectal=/(rect|mesorect|sphinct|levator|perirect|iliac)/.test(raw);
  const anatomy=/(anatom|orient|sphinct|levator|mesorect)/.test(raw) &&
    !/(tumor|tumeur|cancer|t2|t3|t4|diffus|dwi|adc)/.test(raw);
  const radiology=/(t[1234]\b|mri|irm|tdm|ct\b|scan|echograph|ultrason|dwi|diffus|adc)/.test(raw);
  const image_type:MedicalImageRequest['image_type']=anatomy?'anatomical_diagram':
    radiology?'radiology_scan':'operative_diagram';
  const target=rectal?'rectum':ascii(query).split(/\s+/).find(x=>x.length>5)||'abdomen';
  const findings=rectal?
    (anatomy?['rectum','mesorectum','sphincter']:
      /(diffus|dwi|adc|ganglion)/.test(raw)?['rectal','MRI','pelvic']:
      ['rectal','MRI','tumor']):[target];
  const specifiedType=['anatomical_diagram','radiology_scan','operative_diagram','clinical_photo']
    .includes(input?.image_type)?input.image_type:image_type;
  const specifiedPlane=['axial','sagittal','coronal','multiplanar','not_applicable']
    .includes(input?.plane)?input.plane:(anatomy?'sagittal':'not_applicable');
  const selectedFeatures=Array.isArray(input?.required_features)?
    input.required_features.map((x:unknown)=>clean(x,70)).filter(Boolean).slice(0,5):findings;
  const exclusions=Array.isArray(input?.excluded_features)?
    input.excluded_features.map((x:unknown)=>clean(x,70)).filter(Boolean).slice(0,6):[];
  const adapted=rectal
    ?anatomy?'rectum mesorectum sphincter labeled anatomy'
      :/(diffus|dwi|adc|ganglion)/.test(raw)?'rectal cancer MRI lymph node'
      :'rectal cancer T2 MRI'
    :clean(query+' '+modality,200);
  return {
    query:clean(input?.image_type?query:adapted,260),
    modality, purpose, image_type:specifiedType,
    anatomy:clean(input?.anatomy||target,130),plane:specifiedPlane,
    required_features:selectedFeatures,
    excluded_features:exclusions,
  };
}
export function imageSearchTerms(request:MedicalImageRequest):string{
  const anatomy=ascii(request.anatomy);
  if(anatomy.includes('rect')||anatomy.includes('mesorect')||anatomy.includes('sphinct')){
    if(request.image_type==='anatomical_diagram')
      return 'rectum mesorectum anatomy illustration';
    if(/dwi|adc|diffus|ganglion/i.test(request.purpose+' '+request.query))
      return 'rectal cancer diffusion MRI';
    return 'rectal cancer T2 MRI';
  }
  return request.query.slice(0,180).trim()||'abdominal anatomy medical illustration';
}
export function imageIsTopical(image:ImagePreview,request:MedicalImageRequest){
  if(!allowedAsset(image.thumbnail)||!allowedAsset(image.full))return false;
  if(!/^https:\/\//i.test(image.source))return false;
  // Openverse only indexes openly licensed media, including attribution,
  // share-alike and non-commercial licenses. Keep creator/source attribution.
  if(!/(CC\s?BY|CC0|CC-BY|PUBLIC DOMAIN|PDM|PD-|BY-SA|GFDL)/i.test(image.license)
     && !['by','by-sa','by-nc','by-nc-sa','by-nd','by-nc-nd','cc0','pdm']
       .includes(image.license.toLowerCase()))return false;
  const hay=ascii(image.title+' '+image.description);
  if(banned.test(hay))return false;
  const raw=ascii(request.anatomy+' '+request.purpose+' '+request.query);
  const rectal=/rect|mesorect|sphinct|levator/.test(raw);
  // Named body part is indispensable: "cancer" or "MRI" alone is NOT enough.
  if(rectal && !/(rectum|rectal|mesorect|sphincter|levator|anal canal|pelvic floor)/.test(hay))
    return false;
  const isDiagram=request.image_type==='anatomical_diagram';
  const isScan=request.image_type==='radiology_scan';
  if(isDiagram){
    if(!/(anatom|diagram|illustrat|medical illustrat|labeled|pelvic floor|mesorect|sphincter|sagittal|schematic)/.test(hay))return false;
    if(/(?:prostate\s+cancer|cervical\s+cancer|colonoscopy|endoscopy|surgery\s+photo)/.test(hay))return false;
  }else if(isScan){
    if(!/(mri|magnetic resonance|t2|diffusion|dwi|computed tomography|ct scan|ultrasound|sonograph|radiograph|scan image)/.test(hay))return false;
    if(rectal && !/(rectal cancer|rectum cancer|rectal carcinoma|mesorect|rectal tumor|rectal mri|rectum mri)/.test(hay))return false;
  }else if(request.image_type==='operative_diagram'){
    if(!/(surger|operative|procedure|anatom|laparoscop|resection|technique|diagram|illustrat)/.test(hay))return false;
  }
  // Require a second signal when looking for specific imaging sequence/findings.
  if(isScan && /(?:\bt2\b|dwi|diffus|adc)/.test(raw)
       && !/(t2|dwi|diffus|adc|mri|magnetic resonance)/.test(hay))return false;
  const features=Array.isArray(request.required_features)?request.required_features:[];
  if(!rectal && features.length){
    const key=ascii(request.anatomy);
    const salient=terms(key);
    if(salient.length && !salient.some(term=>hay.includes(term)))return false;
  }
  for(const exclusion of request.excluded_features||[]){
    const term=ascii(exclusion);
    if(term.length>=6 && hay.includes(term))return false;
  }
  return true;
}
function pages(query:string){
  return [
    {title:'Radiopaedia',source:'https://radiopaedia.org/search?'+new URLSearchParams({q:query})},
    {title:'The Radiology Assistant',source:'https://radiologyassistant.nl/search?'+new URLSearchParams({q:query})},
    {title:'Eurorad',source:'https://www.eurorad.org/search?'+new URLSearchParams({keys:query})},
    {title:'Europe PMC',source:'https://europepmc.org/search?'+new URLSearchParams({query:query+' AND OPEN_ACCESS:y'})},
    {title:'PubMed Central',source:'https://pmc.ncbi.nlm.nih.gov/?'+new URLSearchParams({term:query})},
  ];
}
async function commons(search:string):Promise<ImagePreview[]>{
  const params=new URLSearchParams({action:'query',generator:'search',
    gsrnamespace:'6',gsrsearch:search,gsrlimit:String(SEARCH_LIMIT),
    prop:'imageinfo',iiprop:'url|mime|extmetadata',iiurlwidth:'750',
    format:'json',formatversion:'2'});
  const r=await fetch('https://commons.wikimedia.org/w/api.php?'+params,{
    signal:AbortSignal.timeout(9000),headers:REQUEST_HEADERS});
  if(!r.ok)return[];
  const data=await r.json();
  const out:ImagePreview[]=[];
  for(const page of data?.query?.pages??[]){
    const info=page?.imageinfo?.[0];if(!info)continue;
    const image:ImagePreview={
      thumbnail:String(info.thumburl||''),full:String(info.url||''),
      source:String(info.descriptionurl||''),
      title:clean(String(page.title||'').replace(/^File:/i,''),190),
      description:clean(info.extmetadata?.ImageDescription?.value,400),
      license:clean(info.extmetadata?.LicenseShortName?.value,60),
      creator:clean(info.extmetadata?.Artist?.value,140),
      provider:'Wikimedia Commons',
    };
    if(allowedAsset(image.thumbnail)&&allowedAsset(image.full))out.push(image);
  }
  return out;
}
// Known, openly licensed anatomy sources are queried by FILE TITLE, not by
// hardcoded image URLs. Wikimedia returns current media URLs and attribution.
async function rectalAnatomyFiles():Promise<ImagePreview[]> {
  const titles=['File:Rectal_anatomy.jpg',
    'File:Anatomy_of_human_rectum_and_anus-2.png',
    'File:Gray1079.png'];
  const params=new URLSearchParams({action:'query',titles:titles.join('|'),
    prop:'imageinfo',iiprop:'url|mime|extmetadata',iiurlwidth:'750',
    format:'json',formatversion:'2'});
  try {
    const r=await fetch('https://commons.wikimedia.org/w/api.php?'+params,{
      signal:AbortSignal.timeout(8500),headers:REQUEST_HEADERS});
    if(!r.ok)return[];
    const data=await r.json();const out:ImagePreview[]=[];
    for(const page of data?.query?.pages??[]){
      const info=page?.imageinfo?.[0];if(!info)continue;
      const item:ImagePreview={
        thumbnail:String(info.thumburl||info.url||''),
        full:String(info.url||''),
        source:String(info.descriptionurl||''),
        title:clean(String(page.title||'').replace(/^File:/i,''),180),
        description:clean(info.extmetadata?.ImageDescription?.value,440),
        creator:clean(info.extmetadata?.Artist?.value,130),
        license:clean(info.extmetadata?.LicenseShortName?.value,60),
        provider:'Wikimedia Commons',
      };
      if(allowedAsset(item.thumbnail)&&allowedAsset(item.full))out.push(item);
    }
    return out;
  }catch(_){return[];}
}

async function openverse(search:string):Promise<ImagePreview[]>{
  const r=await fetch('https://api.openverse.org/v1/images/?'+new URLSearchParams({
    q:search,page_size:String(SEARCH_LIMIT)}),{
    signal:AbortSignal.timeout(9000),headers:REQUEST_HEADERS});
  if(!r.ok)return[];
  const data=await r.json();const out:ImagePreview[]=[];
  for(const v of data?.results??[]){
    if(v.mature===true)continue;
    const id=String(v.id||'');
    // Openverse offers its own thumbnail proxy across multiple providers,
    // so we are no longer limited to just Wikimedia Commons and Flickr.
    const thumbnail=/^[a-f\d-]{36}$/i.test(id)
      ? 'https://api.openverse.org/v1/images/'+id+'/thumb/'
      : String(v.thumbnail||'');
    const source=String(v.foreign_landing_url||'');
    const original=String(v.url||'');
    const full=allowedAsset(original)?original:thumbnail;
    const item:ImagePreview={
      thumbnail,full,source,title:clean(v.title,180),
      description:clean(v.description,360),license:clean(v.license,45),
      creator:clean(v.creator,130),
      provider:clean(v.source||v.provider||'Openverse',65),
    };
    if(allowedAsset(item.thumbnail)&&allowedAsset(item.full))out.push(item);
  }
  return out;
}

export function imageSearchVariants(request:MedicalImageRequest):string[]{
  const base=imageSearchTerms(request);
  const target=ascii(request.anatomy+' '+request.query+' '+request.purpose);
  if(/rect|mesorect|sphinct|levator/.test(target)){
    if(request.image_type==='anatomical_diagram')
      return [base,'rectum anatomy','anal canal sphincter anatomy','mesorectum anatomy'];
    if(/diffus|dwi|adc|ganglion|lymph/.test(target))
      return [base,'rectal MRI diffusion','rectal cancer MRI lymph node','pelvic MRI'];
    return [base,'rectal cancer MRI','rectum MRI','pelvic magnetic resonance'];
  }
  const words=base.split(/\s+/).filter(Boolean);
  const compact=words.slice(0,3).join(' ');
  const anatomy=ascii(request.anatomy).split(/\s+/).filter(Boolean).slice(0,2).join(' ');
  return [...new Set([base,compact,anatomy].filter(q=>q.length>=5))];
}
export async function resolveMedicalPreviews(input:any){
  const request=legacyImageRequest(input);
  const queries=imageSearchVariants(request);
  const curated=request.image_type==='anatomical_diagram' &&
    /rect|mesorect|sphinct/.test(ascii(request.anatomy+' '+request.query))
    ? await rectalAnatomyFiles() : [];
  const run=async(q:string)=>{
    const matches=await Promise.allSettled([commons(q),openverse(q)]);
    return [
      ...(matches[0].status==='fulfilled'?matches[0].value:[]),
      ...(matches[1].status==='fulfilled'?matches[1].value:[]),
    ];
  };
  // Start with medically specific results. Broader terms are used ONLY
  // if no sufficiently relevant image is returned by the first query.
  let candidates=[...curated,...await run(queries[0])];
  let images=candidates.filter(x=>imageIsTopical(x,request));
  if(images.length===0){
    const secondary=await Promise.all(queries.slice(1).map(run));
    candidates.push(...secondary.flat());
    images=candidates.filter(x=>imageIsTopical(x,request));
  }
  const seen=new Set<string>();
  images=images.filter(x=>{
    const key=x.full||x.thumbnail;
    if(seen.has(key))return false;
    seen.add(key);return true;
  }).slice(0,8);
  return {
    images,medical_searches:pages(queries[0]),image_request:request,
    image_sources_searched:queries,
    unavailable_reason:images.length===0?'no_matching_accessible_images':null,
  };
}

export async function proxyMedicalImage(asset:string):Promise<Response>{
  const common={'Access-Control-Allow-Origin':'*',
    'Cache-Control':'private, no-store, max-age=0','Vary':'Origin'};
  if(!allowedAsset(asset))return new Response(null,{status:400,headers:common});
  try {
    const response=await fetch(asset,{redirect:'error',
      signal:AbortSignal.timeout(10000),headers:{Accept:'image/jpeg,image/png,image/webp'}});
    if(!response.ok||!response.body)return new Response(null,{status:404,headers:common});
    const type=(response.headers.get('content-type')||'').toLowerCase().split(';')[0];
    if(!['image/jpeg','image/png','image/webp'].includes(type))
      return new Response(null,{status:415,headers:common});
    const size=Number(response.headers.get('content-length')||0);
    if(size>MAX_BYTES)return new Response(null,{status:413,headers:common});
    const reader=response.body.getReader();let bytes=0;const chunks:Uint8Array[]=[];
    while(true){
      const {done,value}=await reader.read();if(done)break;
      bytes+=value.byteLength;
      if(bytes>MAX_BYTES){await reader.cancel();return new Response(null,{status:413,headers:common});}
      chunks.push(value);
    }
    const joined=new Uint8Array(bytes);let offset=0;
    for(const chunk of chunks){joined.set(chunk,offset);offset+=chunk.byteLength;}
    return new Response(joined,{status:200,headers:{...common,
      'Content-Type':type,'X-Content-Type-Options':'nosniff'}});
  }catch(_){return new Response(null,{status:502,headers:common});}
}
