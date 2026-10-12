/** Public Radiology Assistant pages; transient excerpts/links only, never pixels in DB. */
export const radiologyPriorityPolicy='IMAGERIE ET INTERPRÉTATION : rechercher en priorité The Radiology Assistant (https://radiologyassistant.nl/) pour sémiologie, protocoles, critères, classifications et illustrations. Utiliser seulement les pages effectivement retrouvées ; ne jamais inventer URL, légende, signe ou date. Cette priorité ne remplace pas les recommandations officielles thérapeutiques. Si aucune page adaptée n’est disponible, utiliser PubMed Central/Europe PMC puis les autres sources médicales. Dans image_request/image_requests, preferred_sources commence par Radiology Assistant ; conserver exactement les champs du JSON Schema. Les images restent des illustrations externes, jamais celles du patient fictif.';
const ROOT='https://radiologyassistant.nl';
export type RadiologyArticle={title:string;source:string;provider:string;summary:string;html:string};
const plain=(s:string)=>s.replace(/<script\b[\s\S]*?<\/script>|<style\b[\s\S]*?<\/style>/gi,' ').replace(/<[^>]*>/g,' ').replace(/&(?:nbsp|amp|quot|lt|gt);/g,' ').replace(/&#\d+;/g,' ').replace(/\s+/g,' ').trim();
const norm=(s:string)=>plain(s).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const aliases:Record<string,string>={irm:'MRI',tdm:'CT',scanner:'CT',echographie:'ultrasound',radiographie:'X-ray',rectum:'rectal',mesorectum:'rectal',foie:'liver',hepatique:'liver',rein:'renal kidney',renal:'renal kidney',pancreas:'pancreatic',pulmonaire:'lung',poumon:'lung',thorax:'chest',thoracique:'chest',rocher:'temporal bone',rochers:'temporal bone',oreille:'temporal bone',tympan:'temporal bone',mastoidien:'temporal bone',cerebral:'brain',cerveau:'brain',prostate:'prostate',vessie:'bladder',pelvienne:'pelvic',appendicite:'appendicitis',cholecystite:'cholecystitis gallbladder',vesicule:'gallbladder',biliaire:'biliary',occlusion:'obstruction',diverticulite:'diverticulitis',ischemie:'ischemia',mesenterique:'mesenteric',pancreatite:'pancreatitis',adenopathie:'lymph node',adenopathies:'lymph node',embolie:'embolism',fibrose:'fibrosis',traumatisme:'trauma',fracture:'fracture',genou:'knee',epaule:'shoulder',cheville:'ankle',rachis:'spine',osseuse:'bone',os:'bone',surrenale:'adrenal',uterus:'uterine',ovaire:'ovarian',thyroide:'thyroid',sein:'breast',sinus:'sinus',anatomie:'anatomy',stadification:'staging'};
export function radiologySearchWords(query:string):string[]{
 const raw=norm(query).split(/[^a-z0-9]+/).filter(Boolean);
 const expanded=raw.flatMap(w=>(aliases[w]||w).toLowerCase().split(' '));
 const stop=new Set(['with','from','this','that','case','clinical','patient','medical','imaging','radiology','interpretation','image','images','scan','mri','irm','tdm','ultrasound','axial','coronal','sagittal','normal','cancer','tumor','tumour','lesion','findings','query','purpose','anatomy','modality','radio','visceral','chirurgie','qcm','symptomes','diagnostic','prise','charge','pour','dans','avec','sans','les','des','une','and','the','not','t2','t1']);
 return [...new Set(expanded.filter(w=>w.length>=3&&!stop.has(w)))].slice(0,80);
}
export function radiologyArticleIndex(html:string,query:string):{title:string;source:string}[]{
 const words=radiologySearchWords(query);if(!words.length)return [];
 const found=new Map<string,{title:string;source:string;score:number}>();
 for(const m of html.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)){
  let u:URL;try{u=new URL(m[1],ROOT);}catch{continue;}
  if(u.origin!==ROOT||!/^\/(abdomen|chest|breast|cardiovascular|head-neck|head\/neck|musculoskeletal|neuroradiology|pediatrics)\//.test(u.pathname))continue;
  const title=plain(m[2]);if(!title||title.length>200)continue;
  const hay=norm(title+' '+u.pathname.replace(/[-/]/g,' '));
  const score=words.filter(w=>new RegExp('\\b'+w+'[a-z]*\\b').test(hay)).length;
  if(score<1)continue;
  u.hash='';u.search='';const source=u.toString();
  if(!found.has(source)||found.get(source)!.score<score)found.set(source,{title,source,score});
 }
 const highest=Math.max(0,...[...found.values()].map(x=>x.score));
 return [...found.values()].filter(x=>highest<2||x.score>=2).sort((a,b)=>b.score-a.score).slice(0,2).map(({title,source})=>({title,source}));
}
export function radiologyAsset(raw:string):boolean{
 try{const u=new URL(raw);return u.origin===ROOT&&!u.username&&!u.password&&!u.search&&!u.hash&&/^\/(assets|img\/containers\/main)\//.test(u.pathname)&&/\.(jpg|jpeg|png|webp)$/i.test(u.pathname)&&!/%2e|%2f|%5c/i.test(raw);}catch{return false;}
}
function attr(tag:string,key:string):string{return tag.match(new RegExp('\\b'+key+'=["\\\']([^"\\\']*)["\\\']','i'))?.[1]||'';}
export function radiologyFigures(html:string,source:string):{thumbnail:string;full:string;caption:string}[]{
 const out:{thumbnail:string;full:string;caption:string}[]=[];
 // Each bblok is a single illustrated teaching point. Local captions and prose
 // are used instead of attributing the whole article to every unrelated figure.
 for(const m of html.matchAll(/<section\b[^>]*class=["'][^"']*\bbblok\b[^"']*["'][^>]*>([\s\S]*?)<\/section>/gi)){
  const block=m[1],tags=[...block.matchAll(/<img\b[^>]*>/gi)];
  for(const t of tags){
   let thumbnail:string,full:string;try{thumbnail=new URL(attr(t[0],'src'),ROOT).toString();const before=block.slice(Math.max(0,t.index!-300),t.index);full=new URL(attr(before,'data-src')||thumbnail,ROOT).toString();}catch{continue;}
   if(!radiologyAsset(thumbnail)||!radiologyAsset(full))continue;
   const local=plain(block.replace(/<div\b[^>]*class=["'][^"']*images[^"']*["'][\s\S]*?<\/div>/i,''));
   const caption=plain(attr(t[0],'alt')+' '+local).slice(0,1100);
   if(caption.length<25||/banner|advertis|logo/i.test(caption))continue;
   out.push({thumbnail,full,caption});
  }
 }
 return [...new Map(out.map(x=>[x.full,x])).values()];
}
export function radiologyExcerpt(html:string,query:string):string{
 const words=radiologySearchWords(query);
 const paragraphs=[...html.matchAll(/<(?:p|li)\b[^>]*>([\s\S]*?)<\/(?:p|li)>/gi)].map(m=>plain(m[1])).filter(p=>p.length>60);
 const scored=paragraphs.map((p,i)=>({p,i,score:words.filter(w=>norm(p).includes(w)).length})).sort((a,b)=>b.score-a.score||a.i-b.i);
 return scored.slice(0,2).sort((a,b)=>a.i-b.i).map(x=>x.p).join(' ').slice(0,650);
}
export function radiologyCaptionFitsQuery(caption:string,query:string):boolean{
 const c=norm(caption),q=norm(query);
 if(/\b(mri|irm|ct|tdm|scanner)\b|ultrasound|echograph|radiograph/.test(q)){
  if(/diagram|schematic|drawing|anatomical illustration|axial illustration/.test(c.slice(0,300)))return false;
  if(/\b(mri|irm)\b/.test(q)&&!/(\bmri\b|magnetic resonance|\bmr image)/.test(c))return false;
  if(/\b(ct|tdm|scanner)\b/.test(q)&&!/(\bct\b|computed tomography|computed tomographic)/.test(c))return false;
  if(/ultrasound|echograph/.test(q)&&!/ultrasound|sonograph|echograph/.test(c))return false;
  if(/\bt2\b/.test(q)&&!/t2[ -]?(weighted|w|wi|mri|sequence)|t2.{0,15}image/.test(c))return false;
  if(/dwi|adc|diffusion/.test(q)&&!/dwi|adc|diffusion/.test(c))return false;
 }
 return true;
}
async function publicHtml(url:string):Promise<string>{
 try{const r=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(4500),headers:{Accept:'text/html'}});if(!r.ok||!r.headers.get('content-type')?.includes('text/html'))return '';const body=await r.text();return body.length<=2500000?body:'';}catch{return '';}
}
let indexMemo:{until:number;value:Promise<string>}|undefined;
export async function findRadiologyArticles(query:string):Promise<RadiologyArticle[]>{
 if(!radiologySearchWords(query).length)return [];
 if(!indexMemo||indexMemo.until<Date.now())indexMemo={until:Date.now()+3600000,value:publicHtml(ROOT+'/')};
 const index=await indexMemo.value;if(!index)indexMemo.until=0;
 const matches=radiologyArticleIndex(index,query);
 return (await Promise.all(matches.map(async x=>{
  const html=await publicHtml(x.source);if(!html)return null;
  const body=html.slice(html.search(/<h1\b/i)).replace(/<nav\b[\s\S]*?<\/nav>/gi,' ');
  return {...x,provider:'The Radiology Assistant',summary:radiologyExcerpt(body,query),html};
 }))).filter((x):x is RadiologyArticle=>x!==null);
}
export async function radiologyAssistantContext(query:string):Promise<string>{
 const articles=await findRadiologyArticles(query);
 const a=articles[0];return a?'\nSOURCE D’IMAGERIE RETROUVÉE — The Radiology Assistant : '+a.title+' | '+a.source+'\nExtrait documentaire (pas une donnée du patient) : '+a.summary+'\nNe citer cette source que pour les faits soutenus par cet extrait.\n':'';
}
