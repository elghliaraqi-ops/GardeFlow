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
  fallback_queries?:string[];
  preferred_sources?:string[];
  allow_article_figures?:boolean;
  allow_source_illustrations?:boolean;
  allow_open_graph_preview?:boolean;
  allow_page_preview?:boolean;
};
export type MedicalArticlePreview={ title:string;source:string;provider:string;summary:string;figure_page?:string;thumbnail?:string;figure_caption?:string;license?:string; }; 
export type ImagePreview = {
  thumbnail:string; full:string; source:string;
  title:string; creator:string; license:string; provider:string;
  description:string;
};

const SEARCH_LIMIT=24;
const ARTICLE_LIMIT=3;
// Wikimedia Commons commonly hosts anatomical drawings as SVG originals.
// These must be displayed through the PNG thumb supplied by imageinfo.
export function rasterImageUrls(info:any):{thumbnail:string,full:string}|null{
  const original=String(info?.url||'');
  const thumbnail=String(info?.thumburl||'');
  const svg=/\.svg(?:\?.*)?$/i.test(original);
  if(svg){
    if(!thumbnail||!allowedAsset(thumbnail))return null;
    return {thumbnail,full:thumbnail};
  }
  const preview=thumbnail||original;
  const full=original||preview;
  return allowedAsset(preview)&&allowedAsset(full)?{thumbnail:preview,full}:null;
}
const REQUEST_HEADERS={Accept:'application/json','Api-User-Agent':'GardeFlowPractice/1.1 (https://github.com/elghliaraqi-ops/GardeFlow)', 'User-Agent':'GardeFlowPractice/1.1 (https://github.com/elghliaraqi-ops/GardeFlow)'};
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
 'pmc.ncbi.nlm.nih.gov',
 'encrypted-tbn0.gstatic.com','encrypted-tbn1.gstatic.com',
 'encrypted-tbn2.gstatic.com','encrypted-tbn3.gstatic.com',
 'encrypted-tbn4.gstatic.com',
 'serpapi.com','europepmc.org',
]);
const openversePreviewPath=/^\/v1\/images\/[a-f\d-]{36}\/thumb\/?$/i;
export function allowedAsset(raw: string) {
  try {
    const uri=new URL(raw);
    if(uri.protocol!=='https:'||uri.username||uri.password||uri.port)return false;
    if(!clinicalHosts.has(uri.hostname.toLowerCase()))return false;
    if(uri.pathname.length>1100 || /%2e|%2f|%5c/i.test(raw))return false;
    if(uri.searchParams.has('download'))return false;
    // SerpApi results may use its thumbnail CDN instead of gstatic.
    if(uri.hostname==='serpapi.com'){
      return /^\/searches\/[A-Za-z0-9_-]{5,120}\/images\/[A-Za-z0-9_.-]{5,250}$/.test(uri.pathname) &&
        uri.search==='';
    }
    // Google thumbnails are served from a very narrow image-only endpoint.
    // Never proxy arbitrary Google, search or user-controlled URL hosts.
    if(/^encrypted-tbn[0-4]\.gstatic\.com$/.test(uri.hostname)){
      return uri.pathname==='/images' &&
        [...uri.searchParams.keys()].every(k=>k==='q') &&
        /^tbn:[A-Za-z0-9_-]{8,300}$/.test(uri.searchParams.get('q')||'');
    }
    if(uri.hostname==='api.openverse.org'){
      // Only the documented image-thumbnail endpoint, never arbitrary API paths.
      return openversePreviewPath.test(uri.pathname) &&
        [...uri.searchParams.keys()].every(k=>k==='full_size');
    }
    if(uri.hostname==='upload.wikimedia.org' &&
       !uri.pathname.startsWith('/wikipedia/commons/'))return false;
    if(uri.hostname==='europepmc.org'){
      // Limit proxying to image files in public full-text PMC articles.
      return /^\/articles\/PMC\d{3,11}\/bin\/[a-zA-Z0-9._-]+\.(?:jpg|jpeg|png|webp)$/i.test(uri.pathname)
        && !uri.search && !uri.hash;
    }
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
  const alternatives=Array.isArray(input?.fallback_queries)
    ?input.fallback_queries.map((v:unknown)=>clean(v,90)).filter(Boolean).slice(0,4):[];
  const preferred=Array.isArray(input?.preferred_sources)
    ?input.preferred_sources.map((v:unknown)=>clean(v,60)).filter(Boolean).slice(0,7):[];
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
    fallback_queries:alternatives,
    preferred_sources:preferred,
    allow_article_figures:input?.allow_article_figures!==false,
    allow_source_illustrations:input?.allow_source_illustrations!==false,
    allow_open_graph_preview:input?.allow_open_graph_preview!==false,
    allow_page_preview:input?.allow_page_preview!==false,
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
  if(image.provider!=='Google Images' &&
     !/(Open access|CC\s?BY|CC0|CC-BY|PUBLIC DOMAIN|PDM|PD-|BY-SA|GFDL)/i.test(image.license)
     && !['by','by-sa','by-nc','by-nc-sa','by-nd','by-nc-nd','cc0','pdm']
       .includes(image.license.toLowerCase()))return false;
  const hay=ascii(image.title+' '+image.description);
  if(banned.test(hay))return false;
  const raw=ascii(request.anatomy+' '+request.purpose+' '+request.query);
  const rectal=/rect|mesorect|sphinct|levator/.test(raw);
  const nodal=/ganglion|iliac|lymph|nodal|adenopath|node|dwi/.test(raw)
    && /ganglion|iliac|lymph|nodal|adenopath|node/.test(raw);
  // A pelvic lymph-node MRI may be relevant to rectal cancer without
  // repeating "rectal" in its own image caption.
  if(nodal && !/(lymph|nodal|node|adenopath|ganglion|iliac)/.test(hay))
    return false;
  if(rectal && !/(rectum|rectal|mesorect|sphincter|levator|anal canal|pelvic floor)/.test(hay)
    && !(nodal && /(pelvic|iliac|lymph|nodal|adenopath)/.test(hay)))
    return false;
  const isDiagram=request.image_type==='anatomical_diagram';
  const isScan=request.image_type==='radiology_scan';
  if(isDiagram){
    if(!/(anatom|diagram|illustrat|medical illustrat|labeled|pelvic floor|mesorect|sphincter|sagittal|schematic)/.test(hay))return false;
    if(/(?:prostate\s+cancer|cervical\s+cancer|colonoscopy|endoscopy|surgery\s+photo)/.test(hay))return false;
  }else if(isScan){
    if(!/(mri|magnetic resonance|t2|diffusion|dwi|computed tomography|ct scan|ultrasound|sonograph|radiograph|scan image)/.test(hay))return false;
    if(rectal && !/(rectal cancer|rectum cancer|rectal carcinoma|mesorect|rectal tumor|rectal mri|rectum mri)/.test(hay)
      && !(nodal&&/(pelvic|iliac|lymph|nodal|adenopath)/.test(hay)))return false;
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
    {title:'Google Images',source:'https://www.google.com/search?'+new URLSearchParams({tbm:'isch',q:query})},
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
    const urls=rasterImageUrls(info);
    if(!urls)continue;
    const image:ImagePreview={
      thumbnail:urls.thumbnail,full:urls.full,
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
  const titles=['File:Rectum anatomy en.svg',
    'File:Anatomy of human rectum and anus-2.png',
    'File:Rectum anatomy de 01.svg',
    'File:Pelvis diagram.png',
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
      const urls=rasterImageUrls(info);
      if(!urls)continue;
      const item:ImagePreview={
        thumbnail:urls.thumbnail,
        full:urls.full,
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
    const rawThumb=String(v.thumbnail||'');
    const thumbnail=allowedAsset(rawThumb)?rawThumb:/^[a-f\d-]{36}$/i.test(id)
      ? 'https://api.openverse.org/v1/images/'+id+'/thumb/'
      : rawThumb;
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
    if(/ganglion|lymph|node|nodal|adenopath|iliac/.test(target)&&request.image_type==='radiology_scan')
      return [...new Set([
        'pelvic lymph node diffusion weighted MRI',
        'rectal cancer nodal staging DWI MRI',
        'internal iliac lymph node pelvic MRI',
        base,...(request.fallback_queries||[]),
        'pelvic lymph node MRI',
      ])].slice(0,7);
    if(request.image_type==='anatomical_diagram')
      return [...new Set([base,...(request.fallback_queries||[]),'rectum anatomy','anal canal sphincter anatomy','mesorectum anatomy'])].slice(0,7);
    if(/diffus|dwi|adc|ganglion|lymph/.test(target))
      return [...new Set([base,...(request.fallback_queries||[]),'rectal MRI diffusion','rectal cancer MRI lymph node','pelvic MRI'])].slice(0,7);
    return [...new Set([base,...(request.fallback_queries||[]),'rectal cancer MRI','rectum MRI','pelvic magnetic resonance'])].slice(0,7);
  }
  const extras=(request.fallback_queries||[]).filter(q=>q.length>3);
  const words=base.split(/\s+/).filter(Boolean);
  const compact=words.slice(0,3).join(' ');
  const anatomy=ascii(request.anatomy).split(/\s+/).filter(Boolean).slice(0,2).join(' ');
  return [...new Set([base,...extras,compact,anatomy].filter(q=>q.length>=5))].slice(0,6);
}
/**
 * Progressive free search: first the requested finding, then the same organ
 * and imaging modality with less specific wording, finally closely related
 * contextual images. These are search terms, not hard-coded image URLs.
 */
export function articleSearchVariants(request:MedicalImageRequest):string[]{
  const topic=ascii(request.anatomy+' '+request.query+' '+request.purpose);
  const nodal=/ganglion|lymph|node|nodal|adenopath|iliac/.test(topic);
  const diffusion=/diffus|dwi|adc|restrict/.test(topic);
  const rectal=/rect|mesorect|sphinct|levator/.test(topic);
  if(request.image_type==='radiology_scan'&&nodal){
    return [...new Set([
      diffusion?'pelvic lymph node diffusion weighted MRI':'pelvic lymph node MRI',
      'rectal cancer lymph node MRI',
      'pelvic nodal staging magnetic resonance imaging',
      ...(request.fallback_queries||[]).filter(q=>
        /mri|irm|lymph|ganglion|node|nodal|iliac|pelvic/i.test(q)),
    ])].slice(0,4);
  }
  if(rectal && request.image_type==='anatomical_diagram')
    return ['rectum mesorectum sphincter anatomy','pelvic floor anatomy MRI'];
  if(rectal && request.image_type==='radiology_scan')
    return ['rectal cancer MRI','rectum MRI staging'];
  if(request.image_type==='radiology_scan'){
    const organ=ascii(request.anatomy).slice(0,90);
    const base=imageSearchTerms(request);
    return [...new Set([base,organ+' MRI imaging',...(request.fallback_queries||[])]
      .filter(q=>q.length>6))].slice(0,3);
  }
  return imageSearchVariants(request).slice(0,3);
}
/**
 * Article and figure discovery is intentionally restricted to publicly accessible
 * Europe PMC open-access articles. Other medical sites are linked as external
 * sources, without copying copyrighted figures or bypassing access controls.
 * No article body, image or URL is persisted.
 */
function xmlText(value:string):string {
  return clean(value.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1').replace(/<[^>]+>/g,' '),520);
}
export function articleFigureSnippets(xml:string):Array<{id:string;href:string;caption:string}>{
  const figs:Array<{id:string;href:string;caption:string}>=[];
  const blocks=xml.match(/<fig\b[\s\S]*?<\/fig>/gi)||[];
  for(const block of blocks.slice(0,60)){
    const id=block.match(/<fig\b[^>]*\bid=["']([^"']{1,65})["']/i)?.[1]||'';
    const href=block.match(/<(?:graphic|inline-graphic)\b[^>]*\b(?:xlink:)?href=["']([^"']{1,165})["']/i)?.[1]||'';
    const caption=xmlText(block.match(/<caption\b[^>]*>([\s\S]*?)<\/caption>/i)?.[1]||'');
    if(!/^[a-z0-9._-]{2,145}$/i.test(href))continue;
    figs.push({id,href,caption});
  }
  return figs;
}

/** Figure captions often omit "rectum MRI" because the article already
 * establishes that context. Keep modality/anatomical clues without requiring
 * them to be repeated verbatim in every caption. */
export function articleFigureRelevant(caption:string,request:MedicalImageRequest,allowContext=false):boolean{
  const label=ascii(caption);
  const subject=ascii(request.anatomy+' '+request.query+' '+request.purpose);
  if(label.length<9||banned.test(label))return false;
  // The depicted finding matters more than its article title. Do not
  // substitute an unrelated rectal T2 tumour for a DWI lymph-node request.
  const nodal=/ganglion|lymph|nodal|adenopath|iliac|node/.test(subject);
  if(nodal&&!/(lymph|nodal|node|ganglion|adenopath|iliac)/.test(label))return false;
  // Stage 1 must document the requested diffusion sign. Stage 2 may show
  // a *clearly labeled* anatomical/modality neighbor, never claim it is DWI.
  if(nodal&&/restrict|diffus|dwi|adc/.test(subject) &&
     !/restrict|diffus|dwi|adc/.test(label) && !allowContext)return false;
  if(/internal iliac|iliaqu\w* interne/.test(subject) &&
     !/internal iliac|iliaqu\w* interne/.test(label) && !allowContext)return false;
  if(/rect|mesorect|sphinct|levator/.test(subject) &&
     !/(rect|mesorect|sphinct|levator|pelvic|anal|fascia|muscularis|tumor|tumour|carcinoma|lymph|node|nodal|iliac|t[1-4]\b|mr\s?stage)/.test(label))return false;
  if(request.image_type==='radiology_scan'){
    if(/photograph|histolog|gross specimen|resection specimen|survival curve|kaplan|flowchart|flow chart|forest plot/.test(label))return false;
    // Only actual scan/image-caption terminology can qualify as radiological media.
    // A staging histogram mentioning T3/T4 is not an MRI illustration.
    return /mri|magnetic resonance|mr image|mr imaging|t2|t1|dwi|adc|diffus|weighted|axial|sagittal|coronal|ct scan|computed tomography|scan image/.test(label);
  }
  if(request.image_type==='anatomical_diagram')
    return /anatom|rect|mesorect|sphinct|levator|pelvic floor|anal canal|fascia|muscularis|diagram|schemat|sagittal/.test(label);
  return /operat|surger|laparoscop|surgical|anatom|resect|technique|procedure|clinical/.test(label);
}
function figurePriority(caption:string,request:MedicalImageRequest):number{
  const label=ascii(caption), subject=ascii(request.query+' '+request.purpose);
  let score=0;
  if(/\b(?:t2|mri|mr image|magnetic resonance|axial|sagittal)\b/.test(label))score+=2;
  if(/\b(?:rectum|rectal|mesorect|sphincter|levator|fascia)\b/.test(label))score+=2;
  if(/t3/.test(subject)&&/\bt3\b/.test(label))score+=4;
  if(/t4/.test(subject)&&/\bt4\b/.test(label))score+=4;
  if(request.image_type==='anatomical_diagram'&&/anatom|schemat|diagram/.test(label))score+=4;
  return score;
}

function articleTopical(text:string,request:MedicalImageRequest):boolean{
  const hay=ascii(text);
  if(banned.test(hay))return false;
  const subject=ascii(request.anatomy+' '+request.query+' '+request.purpose);
  if(/rect|mesorect|sphinct|levator/.test(subject) && !/rect|mesorect|sphinct|pelvic floor/.test(hay)
    && !(/ganglion|lymph|nodal|adenopath|iliac|node/.test(subject)
      && /pelvic|iliac|lymph|nodal|adenopath|node/.test(hay)))
    return false;
  if(/ganglion|lymph|nodal|adenopath|iliac|node/.test(subject)
    && !/lymph|nodal|node|ganglion|adenopath|iliac/.test(hay))return false;
  if(request.image_type==='radiology_scan')
    return /mri|magnetic resonance|diffusion|dwi|ct scan|computed tomography|ultrasound|radiolog|imaging|t2/.test(hay);
  if(request.image_type==='anatomical_diagram')
    return /anatom|diagram|sphinct|mesorect|pelvic floor|schematic|illustrat/.test(hay);
  return true;
}
export function openGraphImageFromHtml(html:string):string|null{
  const tags=html.match(/<meta\b[^>]*>/gi)||[];
  for(const tag of tags){
    if(!/(?:property|name)\s*=\s*["']og:image["']/i.test(tag))continue;
    const raw=tag.match(/\bcontent\s*=\s*["']([^"']+)["']/i)?.[1]||'';
    const value=raw.replace(/&amp;/g,'&');
    if(!allowedAsset(value))continue;
    if(/logo|banner|default|social|favicon|journal.cover|site.icon|generic/i.test(value))continue;
    return value;
  }
  return null;
}
async function articleOpenGraphPreview(pmcid:string):Promise<string|null>{
  try {
    // Only fetch a known public PMC article host, never user-provided pages.
    const res=await fetch('https://pmc.ncbi.nlm.nih.gov/articles/'+pmcid+'/',{
      signal:AbortSignal.timeout(4200),headers:REQUEST_HEADERS});
    if(!res.ok)return null;
    const content=await res.text();
    if(content.length>1100000)return null;
    const img=openGraphImageFromHtml(content);
    if(!img)return null;
    const head=await fetch(img,{method:'HEAD',redirect:'manual',
      signal:AbortSignal.timeout(3000)});
    if(head.ok && /^image\/(?:jpeg|png|webp)/i.test(head.headers.get('content-type')||''))return img;
  } catch (_) { /* A link-only preview is still useful. */ }
  return null;
}

/**
 * Verify the article's actual image bytes endpoint (not its OpenGraph page).
 * PMC article figure URLs frequently 302 to a safe CDN, so a HEAD request
 * returning 302 must not cause a valid, medically relevant figure to be lost.
 */
export async function probeMedicalFigure(asset:string,fetcher:typeof fetch=fetch):Promise<boolean>{
  if(!allowedAsset(asset))return false;
  let target=asset;
  try{
    for(let hop=0;hop<3;hop++){
      let response=await fetcher(target,{
        method:'HEAD',redirect:'manual',signal:AbortSignal.timeout(3500),
        headers:{Accept:'image/jpeg,image/png,image/webp'}
      });
      // Some PMC/publisher image CDNs reject HEAD despite serving the image.
      // A bounded range GET checks the MIME type without storing the image.
      if([403,405,501].includes(response.status)){
        response=await fetcher(target,{
          method:'GET',redirect:'manual',signal:AbortSignal.timeout(3500),
          headers:{Accept:'image/jpeg,image/png,image/webp',Range:'bytes=0-63'}
        });
        // No downloaded image body is retained during source discovery.
        if(response.body)await response.body.cancel().catch(()=>{});
      }
      if(response.status>=300&&response.status<400){
        const location=response.headers.get('location');
        if(!location||hop===2)return false;
        const next=new URL(location,target).toString();
        if(!allowedAsset(next))return false;
        target=next;
        continue;
      }
      return response.ok && /^image\/(?:jpeg|png|webp)(?:;|$)/i.test(
        response.headers.get('content-type')||'');
    }
  }catch(_){/* Missing external source -> source link only. */}
  return false;
}

/**
 * PubMed Central serves figures from content-addressed CDN paths.
 * JATS <graphic href> is only a FILENAME, not a working /articles/PMC/bin URL.
 * Derive the actual image endpoint from the public rendered PMC article.
 */
export function pmcFigureAssets(html:string):string[]{
  const assets:string[]=[];
  const seen=new Set<string>();
  const images=html.match(/<img\b[^>]*>/gi)||[];
  for(const tag of images){
    const url=tag.match(/\bsrc\s*=\s*["'](https:\/\/cdn\.ncbi\.nlm\.nih\.gov\/pmc\/blobs\/[^"'<>]+)["']/i)?.[1]
      ?.replace(/&amp;/g,'&')||'';
    if(url&&allowedAsset(url)&&!seen.has(url)){
      seen.add(url);assets.push(url);
    }
  }
  return assets.slice(0,90);
}
export function pmcAssetForFigure(filename:string,asset:string):boolean{
  if(!allowedAsset(asset))return false;
  const reference=filename.split('/').pop()?.toLowerCase()||'';
  const actual=new URL(asset).pathname.split('/').pop()?.toLowerCase()||'';
  const stem=(v:string)=>v.replace(/\.(?:png|jpe?g|webp)$/,'');
  return reference.length>4&&(reference===actual||stem(reference)===stem(actual));
}

async function articleSourcePreviews(request:MedicalImageRequest,query:string,allowContext=false):
  Promise<{articles:MedicalArticlePreview[];figures:ImagePreview[]}>{
  const articles:MedicalArticlePreview[]=[];
  const figures:ImagePreview[]=[];
  const url='https://www.ebi.ac.uk/europepmc/webservices/rest/search?'+new URLSearchParams({
    query:query+' AND OPEN_ACCESS:y',
    pageSize:'12',format:'json',resultType:'core'
  });
  let items:any[]=[];
  try{
    const res=await fetch(url,{headers:REQUEST_HEADERS,signal:AbortSignal.timeout(7500)});
    if(res.ok){
      const json=await res.json();
      items=Array.isArray(json?.resultList?.result)?json.resultList.result:[];
    }
  }catch(_){/* Continue with known open-access reviews if catalog is down. */}
  // The first Europe PMC results are sometimes methodology papers without
  // MRI figures. Prioritize established open-access pictorial radiology
  // reviews, whose image URLs are still discovered dynamically from XML.
  const rectal=/rect|mesorect|sphinct|levator/.test(ascii(
    request.anatomy+' '+request.query+' '+request.purpose));
  const nodal=/ganglion|lymph|nodal|adenopath|iliac|node|diffus|dwi|adc/.test(ascii(
    request.anatomy+' '+request.query+' '+request.purpose));
  // The generic rectal staging reference library is unsuitable for a
  // specific nodal/DWI request. For such topics, use real search results.
  // Curated, legitimate PMC *articles* (never fixed image URLs) improve
  // specificity when general catalog searches prefer review statistics.
  const preferred=rectal&&nodal&&request.image_type==='radiology_scan'?[
    {pmcid:'PMC4840772',
      title:'Diagnosis of lateral pelvic lymph node metastasis of lower rectal cancer using diffusion-weighted MRI',
      authorString:'Open-access case report'},
    {pmcid:'PMC4851242',
      title:'Initial staging of rectal cancer and regional lymph nodes: diffusion-weighted MRI',
      authorString:'Open-access radiology study'},
    {pmcid:'PMC7365137',
      title:'Rectal MRI and lateral pelvic sidewall lymph nodes',
      authorString:'Open-access radiology review'},
  ]:rectal&&!nodal?[
    {pmcid:'PMC7471246',title:'MRI of rectal cancer—relevant anatomy and staging key points',
      authorString:'Insights into Imaging'},
    {pmcid:'PMC4463328',title:'MRI in local staging of rectal cancer: an update',
      authorString:'Radiological review'},
    {pmcid:'PMC3463019',title:'Imaging paradigms in assessment of rectal carcinoma: staging',
      authorString:'Radiological review'},
  ]:[];
  const seenIds=new Set<string>();
  const prioritized=[...preferred,...items].filter((entry:any)=>{
    const id=String(entry.pmcid||'');
    return /^PMC\d{3,11}$/i.test(id)&&!seenIds.has(id)&&Boolean(seenIds.add(id));
  });
  const figureDeadline=Date.now()+16500;
  for(const entry of prioritized.slice(0,5)){
    if(Date.now()>figureDeadline)break;
    const pmcid=String(entry.pmcid||'');
    if(!/^PMC\d{3,11}$/i.test(pmcid))continue;
    const title=clean(entry.title,220);
    const summary=clean(entry.authorString||entry.journalTitle||'',140);
    const source='https://europepmc.org/articles/'+pmcid;
    if(!articleTopical(title+' '+clean(entry.abstractText,500),request))continue;
    const card:MedicalArticlePreview={title,source,provider:'Europe PMC',summary,
      figure_page:source+'#figures'};
    if(articles.length<ARTICLE_LIMIT)articles.push(card);
    // A journal/article OG image could be a cover or a logo. Only a
    // caption-matched <fig> with an accessible image becomes an illustration.
    if(request.allow_article_figures===false||figures.length>=3)continue;
    try{
      const [rr,pageRes]=await Promise.all([
        fetch('https://www.ebi.ac.uk/europepmc/webservices/rest/'+pmcid+'/fullTextXML',{
          // XML endpoints return HTTP 406 if requested as application/json.
          headers:{...REQUEST_HEADERS,Accept:'application/xml, text/xml;q=0.9'},
          signal:AbortSignal.timeout(5500)}),
        fetch('https://pmc.ncbi.nlm.nih.gov/articles/'+pmcid+'/',{
          // Plain browser-like request: explicit API/Accept headers can yield
          // a stripped-down PMC page with no figure <img> tags.
          signal:AbortSignal.timeout(5500)})
      ]);
      console.info('pmc_article_http',JSON.stringify({pmcid,xml:rr.status,html:pageRes.status}));
      if(!rr.ok)continue;
      const xml=await rr.text();
      if(xml.length>2200000)continue;
      const html=pageRes.ok?await pageRes.text():'';
      const publishedAssets=html.length<=1600000?pmcFigureAssets(html):[];
      const candidates=articleFigureSnippets(xml)
        .filter(f=>articleFigureRelevant(f.caption,request,allowContext))
        .sort((a,b)=>figurePriority(b.caption,request)-figurePriority(a.caption,request))
        .slice(0,4);
      console.info('pmc_article_assets',JSON.stringify({pmcid,assets:publishedAssets.length,
        figures:candidates.length,matched:candidates.filter(f=>
          publishedAssets.some(u=>pmcAssetForFigure(f.href,u))).length}));
      for(const fig of candidates){
        // Use the real PMC CDN src, matched to the exact JATS figure
        // filename. Never synthesize /articles/PMC.../bin links (403/404).
        const figureUrls=publishedAssets
          .filter(u=>pmcAssetForFigure(fig.href,u)).slice(0,3);
        const probes=await Promise.all(figureUrls.map(async raw=>
          ({raw,valid:await probeMedicalFigure(raw)})));
        const hit=probes.find(v=>v.valid);
        if(!hit)continue;
        const page=fig.id
          ?'https://pmc.ncbi.nlm.nih.gov/articles/'+pmcid+'/figure/'+encodeURIComponent(fig.id)+'/'
          :source+'#figures';
        const subject=ascii(request.query+' '+request.purpose);
        const captionText=ascii(fig.caption);
        const missingDwi=/restrict|diffus|dwi|adc/.test(subject)
          && !/restrict|diffus|dwi|adc/.test(captionText);
        const missingInternalIliac=/internal iliac|iliaqu\w* interne/.test(subject)
          && !/internal iliac|iliaqu\w* interne/.test(captionText);
        const qualifiers=[
          missingDwi?'restriction en diffusion non démontrée':'',
          missingInternalIliac?'topographie iliaque interne non confirmée':'',
        ].filter(Boolean);
        const figureTitle=allowContext && qualifiers.length>0
          ?'Illustration de contexte ('+qualifiers.join(' ; ')+') : '+fig.caption
          :fig.caption;
        const image:ImagePreview={thumbnail:hit.raw,full:hit.raw,source:page,
          title:figureTitle||title,description:title+' '+fig.caption,
          license:'Open access (vérifier la licence de la figure)',creator:summary,
          provider:'PubMed Central'};
        figures.push(image);
        card.thumbnail=hit.raw;card.figure_caption=figureTitle;card.figure_page=page;
        if(!articles.some(a=>a.source===card.source)){
          const replace=articles.findIndex(a=>!a.thumbnail);
          if(replace>=0)articles[replace]=card;
          else if(articles.length<ARTICLE_LIMIT)articles.push(card);
        }
        break;
      }
    }catch(e){console.info('pmc_article_error',JSON.stringify({pmcid,error:String(e).slice(0,130)}));}
    if(figures.length>=3)break;
  }
  return {articles,figures};
}

/**
 * Google Images is accessed via an authorized SERP API when configured, never
 * by scraping Google HTML. SERPAPI_KEY remains a backend-only Supabase secret.
 * Without a key, the Google Images search link still works in the UI.
 *
 * A Google result is a link to a third-party work, NOT permission to reuse it.
 * The app does not persist the image, and displays source and rights notice.
 */
export function parseGoogleImageResults(data:any):ImagePreview[]{
  const out:ImagePreview[]=[];
  for(const value of (Array.isArray(data?.images_results)?data.images_results:[]).slice(0,12)){
    const thumb=String(value?.thumbnail||'');
    const original=String(value?.original||'');
    const page=String(value?.link||'');
    const title=clean(value?.title,180);
    if(!allowedAsset(thumb)||!title)continue;
    try{
      const u=new URL(page);
      if(u.protocol!=='https:'||u.username||u.password||u.port||!u.hostname.includes('.'))continue;
      if(/^localhost$|\.local$|^127\.|^10\.|^192\.168\./.test(u.hostname))continue;
    }catch(_){continue;}
    out.push({
      thumbnail:thumb,full:allowedAsset(original)?original:thumb,
      source:page,title,description:clean(value?.title+' '+(value?.source||''),300),
      license:'Droits à vérifier sur le site source',creator:'',provider:'Google Images',
    });
  }
  return out;
}
async function googleImagesProvider(query:string):Promise<ImagePreview[]>{
  const key=Deno.env.get('SERPAPI_KEY');
  if(!key)return[];
  try{
    const url='https://serpapi.com/search.json?'+new URLSearchParams({
      engine:'google_images',q:query,api_key:key,
    });
    const response=await fetch(url,{
      headers:{Accept:'application/json'},signal:AbortSignal.timeout(9000)
    });
    if(!response.ok)return[];
    return parseGoogleImageResults(await response.json());
  }catch(_){return[];}
}

/**
 * SerpApi has a paid quota. Google is NEVER called in resolveMedicalPreviews;
 * explicit google_images user action is mandatory. The Flutter client keeps
 * a persistent per-device metadata cache, and this warm-instance memo also
 * deduplicates near-simultaneous requests without storing image bytes.
 */
export function googleMedicalCacheKey(input:any):string{
  const request=legacyImageRequest(input);
  return (request.image_type+'|'+imageSearchTerms(request)).toLowerCase()
    .replace(/\s+/g,' ').trim().slice(0,240);
}
const paidGoogleMemo=new Map<string,{until:number;value:Promise<ImagePreview[]>}>();
export async function resolveGoogleMedicalImages(input:any){
  const request=legacyImageRequest(input);
  const key=googleMedicalCacheKey(input);
  if(!Deno.env.get('SERPAPI_KEY'))return {
    images:[],google_cache_key:key,google_enabled:false,search_executed:false
  };
  const now=Date.now();
  let cached=paidGoogleMemo.get(key);
  if(!cached||cached.until<=now){
    const promise=googleImagesProvider(imageSearchTerms(request))
      .then(data=>data.filter(image=>imageIsTopical(image,request)).slice(0,8));
    // Empty responses are cached for 2 hours; successful responses for 7 days.
    cached={until:now+2*60*60*1000,value:promise};
    paidGoogleMemo.set(key,cached);
    void promise.then(images=>{
      const current=paidGoogleMemo.get(key);
      if(current?.value===promise)
        current.until=Date.now()+(images.length?7*24*60*60*1000:2*60*60*1000);
    }).catch(()=>{if(paidGoogleMemo.get(key)?.value===promise)paidGoogleMemo.delete(key);});
    if(paidGoogleMemo.size>150){
      const first=paidGoogleMemo.keys().next().value;
      if(first)paidGoogleMemo.delete(first);
    }
  }
  const images=await cached.value;
  return {
    images,
    google_cache_key:key,
    google_enabled:Boolean(Deno.env.get('SERPAPI_KEY')),
    search_executed:true,
  };
}

export async function resolveMedicalPreviews(input:any){
  const request=legacyImageRequest(input);
  const queries=imageSearchVariants(request);
  const articleQueries=articleSearchVariants(request);
  const articleResults:Awaited<ReturnType<typeof articleSourcePreviews>>[]=[];
  // FIRST: open-access PubMed Central articles and their real, caption-
  // matched CDN figures. Do not spend Google/SerpApi credits automatically.
  if(request.allow_page_preview!==false&&articleQueries.length){
    const first=await articleSourcePreviews(request,articleQueries[0]);
    articleResults.push(first);
    if(first.figures.length===0&&articleQueries.length>1)
      articleResults.push(await articleSourcePreviews(request,articleQueries[1],true));
  }
  const articles:MedicalArticlePreview[]=[];
  const articleFigures:ImagePreview[]=[];
  const seenArticles=new Set<string>();
  for(const result of articleResults){
    articleFigures.push(...result.figures);
    for(const article of result.articles){
      if(seenArticles.has(article.source))continue;
      seenArticles.add(article.source);
      articles.push(article);
    }
  }
  articles.sort((a,b)=>Number(Boolean(b.thumbnail))-Number(Boolean(a.thumbnail)));
  let images=[...articleFigures];
  let catalogCandidates=0;
  // SECOND: try other freely usable catalogues only when PMC didn't supply
  // enough useful figures. The original medical image request is unchanged.
  if(images.length<2&&request.allow_source_illustrations!==false){
    const curated=request.image_type==='anatomical_diagram' &&
      /rect|mesorect|sphinct/.test(ascii(request.anatomy+' '+request.query))
      ?await rectalAnatomyFiles():[];
    const run=async(q:string)=>{
      const matches=await Promise.allSettled([commons(q),openverse(q)]);
      return [
        ...(matches[0].status==='fulfilled'?matches[0].value:[]),
        ...(matches[1].status==='fulfilled'?matches[1].value:[]),
      ];
    };
    const primary=queries.length?await run(queries[0]):[];
    let candidates=[...curated,...primary];
    catalogCandidates=candidates.length;
    let found=candidates.filter(x=>imageIsTopical(x,request));
    if(images.length+found.length<2&&queries.length>1){
      const secondary=await Promise.all(queries.slice(1).map(run));
      candidates.push(...secondary.flat());
      catalogCandidates=candidates.length;
      found=candidates.filter(x=>imageIsTopical(x,request));
    }
    images.push(...found);
  }
  const seen=new Set<string>();
  images=images.filter(x=>{
    const url=x.full||x.thumbnail;
    if(!url||seen.has(url))return false;
    seen.add(url);
    return true;
  }).slice(0,8);
  console.info('medical_image_result',JSON.stringify({
    type:request.image_type,primary:'pubmed_central',
    articleQueries:articleResults.length,queries:queries.length,
    candidates:catalogCandidates,accepted:images.length
  }));
  return {
    images,article_previews:articles.slice(0,ARTICLE_LIMIT),
    medical_searches:pages(articleQueries[0]||queries[0]||request.query),
    image_request:request,google_images_available:Boolean(Deno.env.get('SERPAPI_KEY')),
    google_cache_key:googleMedicalCacheKey(input),
    image_sources_searched:[...articleQueries.slice(0,articleResults.length),...queries],
    unavailable_reason:images.length===0&&articles.length===0?'no_matching_accessible_images':null,
  };
}

export async function proxyMedicalImage(asset:string):Promise<Response>{
  const common={'Access-Control-Allow-Origin':'*',
    'Cache-Control':'private, no-store, max-age=0','Vary':'Origin'};
  if(!allowedAsset(asset))return new Response(null,{status:400,headers:common});
  try {
    // Publisher figure endpoints sometimes redirect to their trusted CDN.
    // Follow no more than two redirects, checking each target against the
    // explicit image-host allowlist (never arbitrary destinations).
    let target=asset;
    let response:Response|null=null;
    for(let hop=0;hop<3;hop++){
      response=await fetch(target,{redirect:'manual',
        signal:AbortSignal.timeout(9000),headers:{Accept:'image/jpeg,image/png,image/webp'}});
      if(response.status>=300&&response.status<400){
        const location=response.headers.get('location');
        if(!location||hop===2)return new Response(null,{status:404,headers:common});
        const next=new URL(location,target).toString();
        if(!allowedAsset(next))return new Response(null,{status:403,headers:common});
        target=next;continue;
      }
      break;
    }
    if(!response)return new Response(null,{status:502,headers:common});
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
