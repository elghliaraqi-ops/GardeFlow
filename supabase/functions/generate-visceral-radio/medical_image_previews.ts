// Public medical images are resolved on demand, never persisted.
// The lookup provides visual examples, not patient data or medical verification.
export type Preview = {
  thumbnail: string;
  full: string;
  source: string;
  title: string;
  creator: string;
  license: string;
  provider: string;
};

const sources=(query:string)=>[
  {title:'Radiopaedia',source:'https://radiopaedia.org/search?'+new URLSearchParams({q:query})},
  {title:'The Radiology Assistant',source:'https://radiologyassistant.nl/search?'+new URLSearchParams({q:query})},
  {title:'Eurorad',source:'https://www.eurorad.org/search?'+new URLSearchParams({keys:query})},
];
function https(value:unknown){
  const u=String(value??'').trim();
  return u.startsWith('https://')&&u.length<1800?u:'';
}
function snippet(value:unknown,max=160){
  return String(value??'').replace(/<[^>]*>/g,' ').trim().slice(0,max);
}

export function medicalSearchTerms(request:string, modality=''):string {
  const raw=(request+' '+modality).normalize('NFD')
    .replace(/[\u0300-\u036f]/g,'').toLowerCase().slice(0,550);
  if(/rectum|mesorect|perirect|sphincter/.test(raw)) {
    if(/anatomi|orient|sphincter|mesorect/.test(raw))return 'rectum mesorectum MRI anatomy';
    return 'rectal cancer pelvic MRI';
  }
  if(/appendic/.test(raw))return 'acute appendicitis ultrasound CT';
  if(/pancrea/.test(raw))return 'pancreatitis abdominal CT';
  if(/cholecyst|vesicul|biliaire/.test(raw))return 'gallbladder cholecystitis ultrasound';
  if(/hepati|foie|liver/.test(raw))return 'liver hepatic MRI CT';
  if(/hernia|hernie|inguinal/.test(raw))return 'inguinal hernia anatomy illustration';
  if(/occlus|intestin|ileus|grele/.test(raw))return 'small bowel obstruction abdominal CT';
  if(/diverticul/.test(raw))return 'acute diverticulitis CT abdomen';
  if(/digestiv|colon|colorect/.test(raw))return 'colorectal abdominal CT MRI';
  const words=raw.replace(/[^a-z0-9 ]+/g,' ').split(/\s+/)
    .filter(x=>x.length>3 && ![
      'pour','dans','avec','sans','illustrer','rechercher','montrer','image',
      'images','medicale','medical','signe','signes','coupe','axiale','haute',
      'resolution','anatomique','description','exemple','traitement',
      'radiologie','chirurgie','aspect','structure','structures',
    ].includes(x)).slice(0,7);
  return words.length?words.join(' '):'abdominal radiology anatomy';
}

function relevance(title:string,keywords:string){
  const terms=keywords.toLowerCase().split(/\s+/).filter(x=>x.length>=4);
  const hay=title.toLowerCase();
  return terms.reduce((n,t)=>n+(hay.includes(t)?1:0),0);
}
async function fromCommons(search:string):Promise<Preview[]> {
  const params=new URLSearchParams({
    action:'query',generator:'search',gsrnamespace:'6',
    gsrsearch:search,gsrlimit:'16',prop:'imageinfo',
    iiprop:'url|extmetadata',iiurlwidth:'750',
    format:'json',formatversion:'2',
  });
  const response=await fetch('https://commons.wikimedia.org/w/api.php?'+params.toString(),{
    headers:{Accept:'application/json'},signal:AbortSignal.timeout(8500)});
  if(!response.ok)return[];
  const json=await response.json();
  const result:Preview[]=[];
  for(const file of json?.query?.pages??[]) {
    const info=file?.imageinfo?.[0];
    if(!info)continue;
    const mime=String(info.mime??'');
    const thumbnail=https(info.thumburl||info.url);
    const full=https(info.url||info.thumburl);
    const source=https(info.descriptionurl||'');
    if(!thumbnail||!full||!source)continue;
    if(mime&&!(mime.startsWith('image/')||mime==='application/pdf'))continue;
    if(/\.(svg|pdf)(\?|$)/i.test(thumbnail))continue;
    const license=snippet(info.extmetadata?.LicenseShortName?.value,65);
    if(!/CC BY|CC0|Public domain|PDM|PD-|CC-BY|Attribution/i.test(license))continue;
    const title=snippet(String(file.title??'').replace(/^File:/i,'').replace(/\.[^.]+$/,''),180);
    if(relevance(title,search)===0)continue;
    result.push({
      thumbnail,full,source,title,
      creator:snippet(info.extmetadata?.Artist?.value,90),
      license,provider:'Wikimedia Commons',
    });
  }
  result.sort((a,b)=>relevance(b.title,search)-relevance(a.title,search));
  return result.slice(0,8);
}
async function fromOpenverse(search:string):Promise<Preview[]>{
  const params=new URLSearchParams({
    q:search,page_size:'16',license:'by,by-sa,cc0,pdm',
  });
  const response=await fetch('https://api.openverse.org/v1/images/?'+params.toString(),{
    headers:{Accept:'application/json'},signal:AbortSignal.timeout(8500)});
  if(!response.ok)return[];
  const json=await response.json();
  const results:Preview[]=[];
  for(const value of json?.results??[]){
    if(value.mature===true)continue;
    const thumbnail=https(value.thumbnail);
    const full=https(value.url)||thumbnail;
    const source=https(value.foreign_landing_url);
    const license=snippet(value.license,45);
    const title=snippet(value.title,180);
    if(!thumbnail||!source||!title)continue;
    if(!['by','by-sa','cc0','pdm'].includes(license.toLowerCase()))continue;
    if(relevance(title,search)===0)continue;
    results.push({
      thumbnail,full,source,title,license,
      creator:snippet(value.creator,100),provider:'Openverse',
    });
  }
  results.sort((a,b)=>relevance(b.title,search)-relevance(a.title,search));
  return results.slice(0,8);
}
export async function resolveMedicalPreviews(query:string,modality='') {
  const normalized=medicalSearchTerms(query,modality);
  // Two independently hosted sources; one failure does not hide the other.
  const [commons,openverse]=await Promise.allSettled([
    fromCommons(normalized),fromOpenverse(normalized),
  ]);
  const candidates=[
    ...(commons.status==='fulfilled'?commons.value:[]),
    ...(openverse.status==='fulfilled'?openverse.value:[]),
  ];
  const used=new Set<string>();
  const images=candidates.filter(image=>{
    const key=image.full||image.thumbnail;
    if(used.has(key))return false;
    used.add(key);return true;
  }).slice(0,8);
  return {images,medical_searches:sources(normalized),query_used:normalized};
}
