import {radiologyArticleIndex,radiologyFigures,radiologyAsset,radiologyAssistantContext} from './radiology_assistant.ts';
import {resolveMedicalPreviews,radiologyFigureMatches,legacyImageRequest} from './medical_image_previews.ts';
function assert(x:unknown,msg:string){if(!x)throw Error(msg);}
const root='https://radiologyassistant.nl';
const page=root+'/abdomen/rectum/rectal-cancer-mr-staging-1-1';
const home='<a href="/abdomen/rectum/rectal-cancer-mr-staging-1-1">Rectal Cancer MRI staging</a><a href="/abdomen/liver/masses">Liver masses</a><a href="https://evil.test/abdomen/rectum">Rectal MRI</a>';
const article='<h1>Rectal cancer MR staging</h1><p>Rectal cancer staging uses MRI to evaluate mesorectal spread. Reference images are educational, distinct from the patient.</p>'+[1,2].map(i=>'<section class="bblok flex-row"><div class="images"><a data-src="/assets/rectal-'+i+'.jpg"><img src="/assets/rectal-'+i+'.jpg" alt="Axial T2 MRI rectal tumor"></a></div><div class="dblok"><p>Axial T2 MRI shows the rectal tumor and mesorectal invasion.</p></div></section>').join('');
Deno.test('French legacy requests discover the correct source, never another host',()=>{
 const result=radiologyArticleIndex(home,'Cancer du rectum IRM stadification');
 assert(result[0]?.source===page,'rectal article first');
 assert(result.every(a=>a.source.startsWith(root+'/')),'same origin');
 assert(radiologyArticleIndex(home,'psychiatrie anxiete').length===0,'no unrelated article');
});
Deno.test('only narrow image paths and locally captioned figures are accepted',()=>{
 assert(radiologyAsset(root+'/assets/rectal-1.jpg'),'real asset');
 for(const url of ['http://radiologyassistant.nl/assets/a.jpg',root+'/search?q=a.jpg',root+'/assets/a.jpg?download=1','https://radiologyassistant.nl.evil.test/assets/a.jpg'])assert(!radiologyAsset(url),'reject '+url);
 assert(radiologyFigures(article,page).length===2,'two local figures');
 const request=legacyImageRequest({query:'rectal T2 axial MRI',modality:'MRI T2',image_type:'radiology_scan',anatomy:'rectum',plane:'axial'});
 const image={thumbnail:root+'/assets/a.jpg',full:root+'/assets/a.jpg',source:page,title:'MRI',creator:'',license:'Droits réservés',provider:'The Radiology Assistant',description:'Axial T2 MRI rectal tumor'};
 assert(radiologyFigureMatches(image,request),'exact T2 axial figure');
 assert(!radiologyFigureMatches(image,{...request,modality:'MRI DWI',query:'rectal diffusion MRI'}),'T2 is not diffusion');
 assert(!radiologyFigureMatches({...image,description:'Rectal anatomy diagram'},request),'diagram is not MRI');
});
Deno.test('live lookup prioritizes Radiology Assistant for old JSON requests without paid search',async()=>{
 const old=globalThis.fetch,calls:string[]=[];
 globalThis.fetch=(async(input:RequestInfo|URL)=>{
  const url=String(input);calls.push(url);
  if(url===root+'/')return new Response(home,{headers:{'content-type':'text/html'}});
  if(url===page)return new Response(article,{headers:{'content-type':'text/html'}});
  throw Error('fallback should not be needed: '+url);
 }) as typeof fetch;
 try{
  const input={query:'rectal cancer T2 axial MRI',modality:'MRI T2',purpose:'rectal tumor',image_type:'radiology_scan',anatomy:'rectum',plane:'axial',required_features:['rectal tumor'],excluded_features:[]};
  const snapshot=JSON.stringify(input);
  const result=await resolveMedicalPreviews(input);
  assert(result.images.length===2,'two primary images');
  assert(result.images.every(x=>x.provider==='The Radiology Assistant'),'primary provider');
  assert(result.article_previews[0]?.source===page,'article retained');
  assert(result.image_request.preferred_sources?.[0]==='Radiology Assistant','legacy preferences aligned');
  assert(result.medical_searches[0].title==='The Radiology Assistant','first search link');
  assert(JSON.stringify(input)===snapshot,'stored input unchanged');
  const context=await radiologyAssistantContext('rectal cancer MRI');
  assert(context.includes(page)&&context.includes('mesorectal'),'retrieved interpretation context');
  assert(calls.every(x=>x.startsWith(root+'/')),'no PubMed or paid fallback when primary sufficient');
 }finally{globalThis.fetch=old;}
});
