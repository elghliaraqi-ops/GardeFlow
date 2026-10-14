import { allowedAsset, imageIsTopical, imageSearchTerms, imageSearchVariants, legacyImageRequest,
  rasterImageUrls, articleFigureSnippets, openGraphImageFromHtml, probeMedicalFigure, resolveMedicalPreviews, type ImagePreview } from './medical_image_previews.ts';

function assert(value: unknown, reason: string) {
  if (!value) throw new Error(reason);
}
const good:ImagePreview={
  thumbnail:'https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Rectum_anatomy.jpg',
  full:'https://upload.wikimedia.org/wikipedia/commons/1/11/Rectum_anatomy.jpg',
  source:'https://commons.wikimedia.org/wiki/File:Rectum_anatomy.jpg',
  title:'Rectum mesorectum sphincter labeled sagittal anatomy illustration',
  description:'Sagittal anatomy diagram of rectum and mesorectum',
  creator:'Open educational author',license:'CC BY-SA 4.0',provider:'Wikimedia Commons',
};

Deno.test('legacy rectal-anatomy description becomes strict anatomical diagram request',()=>{
  const r=legacyImageRequest({query:"Illustrer l'orientation anatomique du rectum, mésorectum et sphincters",modality:'schéma'});
  assert(r.image_type==='anatomical_diagram','must not select cancer MRI for normal anatomy');
  assert(imageSearchTerms(r).includes('anatomy'),'anatomical search must be used');
  assert(imageIsTopical(good,r),'sagittal mesorectal diagram should be eligible');
});

Deno.test('reject cover pages even if the title contains rectum, cancer, anatomy',()=>{
  const r=legacyImageRequest({query:"Anatomie du rectum et du mésorectum"});
  const cover={...good,title:'Rectum anatomy book cover - National Cancer Institute report',
    description:'medical book cover'};
  assert(!imageIsTopical(cover,r),'book covers must never appear as medical anatomy');
});

Deno.test('reject wrong organ, modality or image type',()=>{
  const r=legacyImageRequest({query:'Signal T2 du mésorectum et délimitation tumorale T3 vs T4',modality:'IRM T2'});
  assert(r.image_type==='radiology_scan','T2 request must be MRI');
  assert(!imageIsTopical(good,r),'normal anatomy diagram is not an MRI tumor');
  assert(!imageIsTopical({...good,title:'Prostate screening journal cover MRI',
    description:'MRI of prostate'},r),'prostate image must not appear in rectal MRI');
  assert(imageIsTopical({...good,title:'Rectal cancer T2 pelvic MRI extramural invasion',
    description:'Axial T2 MR image of rectal tumor'},r),'real T2 MRI metadata must be eligible');
});

Deno.test('image proxy refuses SSRF and does not allow arbitrary external hosts',()=>{
  assert(allowedAsset(good.thumbnail),'Wikimedia Commons original is allowed');
  assert(allowedAsset('https://live.staticflickr.com/75/20212345_a8b9c0d.jpg'),
    'Openverse/Flickr CC previews allowed');
  for(const bad of [
    'http://upload.wikimedia.org/a.png','https://evil.example/a.jpg',
    'https://127.0.0.1/test.jpg','https://upload.wikimedia.org.evil.com/img.png',
    'https://upload.wikimedia.org/../../secret.jpg',
    'https://upload.wikimedia.org/video.svg',
  ])assert(!allowedAsset(bad),'Must reject '+bad);
});


Deno.test('expanded medical sources retain safe image hosts and non-commercial licences',()=>{
  const thumb='https://api.openverse.org/v1/images/4bc43a04-ef46-4544-a0c1-63c63f56e276/thumb/';
  assert(allowedAsset(thumb),'Openverse thumbnail proxy should be allowed');
  assert(allowedAsset('https://cdn.ncbi.nlm.nih.gov/pmc/blobs/1234/figure1.jpg'),
    'Open-access medical publisher CDN allowed');
  assert(allowedAsset('https://images.squarespace-cdn.com/content/v1/surgical_figure.png'),
    'Openverse supported photo CDN allowed');
  const req=legacyImageRequest({query:"Rectum sphincters anatomy",image_type:"anatomical_diagram",
    anatomy:"rectum",modality:"drawing",required_features:["rectum"]});
  assert(imageIsTopical({...good,thumbnail:thumb,full:thumb,license:'by-nc-sa'},req),
    'Openverse CC BY-NC-SA is appropriate for attributed personal study');
  assert(!allowedAsset('https://api.openverse.org/v1/users/secret/'),
    'Openverse proxy cannot fetch arbitrary API endpoints');
  assert(!allowedAsset('https://cdn.ncbi.nlm.nih.gov.evil.example/medical.jpg'),
    'Subdomain spoofing rejected');
});

Deno.test('search broadens a specific request while keeping the right modality',()=>{
  const anatomy=legacyImageRequest({query:"Illustrer l'orientation anatomique du rectum, mésorectum et sphincters",
    modality:"schéma"});
  const variants=imageSearchVariants(anatomy);
  assert(variants.some(q=>q==='rectum anatomy'),
    'Old rectal anatomy fiche needs a shorter query fallback');
  assert(variants.some(q=>q.includes('mesorectum')),
    'At least one query still targets mesorectum');
  const imaging=legacyImageRequest({query:"Signal T2 du mésorectum et délimitation tumorale T3 vs T4",
    modality:"IRM T2"});
  assert(imageSearchVariants(imaging).some(q=>q==='rectal cancer MRI'),
    'Existing T2 MRI course gets an MRI-focused fallback');
  assert(!imageIsTopical({...good,
    title:'Rectum annual report book cover',
    description:'rectal cancer anatomy imaging'},anatomy),
    'Broad search does not reintroduce irrelevant book covers');
});

Deno.test('Wikimedia SVG rectum diagram uses generated PNG for BOTH preview and zoom',()=>{
  const svg='https://upload.wikimedia.org/wikipedia/commons/a/ab/Rectum_anatomy_en.svg';
  const png='https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Rectum_anatomy_en.svg/750px-Rectum_anatomy_en.svg.png';
  const images=rasterImageUrls({url:svg,thumburl:png});
  assert(images!==null,'a real SVG with raster PNG must not be silently discarded');
  assert(images!.thumbnail===png&&images!.full===png,'viewer must never request raw SVG');
  const req=legacyImageRequest({query:"Illustrer l'orientation anatomique du rectum, mésorectum et sphincters",modality:'schéma'});
  assert(imageIsTopical({...good,thumbnail:images!.thumbnail,full:images!.full,
    title:'Rectum anatomy en.svg',description:'English diagram of human rectum'},req),'valid CC rectum diagram should pass the medical filter');
});
Deno.test('non-renderable SVG and unrelated publication covers never become previews',()=>{
  assert(rasterImageUrls({url:'https://upload.wikimedia.org/wikipedia/commons/a/ab/test.svg'})===null,
    'SVG without PNG must be refused');
  const req=legacyImageRequest({query:'Rectum anatomy'});
  const png='https://upload.wikimedia.org/wikipedia/commons/a/ab/Rectum.jpg';
  assert(!imageIsTopical({...good,thumbnail:png,full:png,title:'Rectum anatomy annual report book cover',
    description:'Annual report'},req),'irrelevant covers must still be excluded');
});

Deno.test('Europe PMC XML figure captions can be linked to an open article',()=>{
 const xml='<article><fig id="fig2"><caption><p>Axial T2 pelvic MRI demonstrating rectal tumor</p></caption><graphic xlink:href="MRI-rectal-fig2.jpg"/></fig></article>';
 const figures=articleFigureSnippets(xml);
 assert(figures.length===1,'one medical source figure must be found');
 assert(figures[0].id==='fig2'&&figures[0].href==='MRI-rectal-fig2.jpg','figure metadata preserved');
 assert(figures[0].caption.includes('MRI'),'caption is readable');
 assert(allowedAsset('https://pmc.ncbi.nlm.nih.gov/articles/PMC1234567/bin/MRI-rectal-fig2.jpg'),
  'public article image is eligible for secure proxy');
});
Deno.test('malformed article XML does not supply an unsafe figure',()=>{
 const xml='<fig id="bad"><graphic xlink:href="../../evil.jpg"/></fig>';
 assert(articleFigureSnippets(xml).length===0,'traversal figure names must be rejected');
});

Deno.test('Article page OpenGraph preview only accepts explicitly permitted medical image assets',()=>{
 const article='<meta property="og:image" content="https://cdn.ncbi.nlm.nih.gov/pmc/blobs/10/rectum-figure.jpg">';
 const image=openGraphImageFromHtml(article);
 assert(image==='https://cdn.ncbi.nlm.nih.gov/pmc/blobs/10/rectum-figure.jpg','verified article OG image is found');
 assert(openGraphImageFromHtml('<meta property="og:image" content="http://evil.invalid/banner.png">')===null,'unsafe http OG blocked');
 assert(openGraphImageFromHtml('<meta property="og:image" content="https://cdn.ncbi.nlm.nih.gov/logo.png">')===null,'publisher logo blocked');
});

Deno.test('PMC figure probe follows only allowed CDN redirects and checks image content',async()=>{
  const source='https://pmc.ncbi.nlm.nih.gov/articles/PMC1234567/bin/rectal-fig1.jpg';
  const cdn='https://cdn.ncbi.nlm.nih.gov/pmc/blobs/abc/rectal-fig1.jpg';
  const requests:string[]=[];
  const mock=((input:RequestInfo|URL)=>{
    const url=String(input);requests.push(url);
    if(url===source)return Promise.resolve(new Response(null,{status:302,headers:{location:cdn}}));
    if(url===cdn)return Promise.resolve(new Response(null,{status:200,headers:{'content-type':'image/jpeg'}}));
    throw Error('unexpected network request');
  }) as typeof fetch;
  if(!await probeMedicalFigure(source,mock))throw Error('valid medical figure redirect should load');
  if(JSON.stringify(requests)!==JSON.stringify([source,cdn]))throw Error('redirect source mix-up');
  const unsafe=((_:RequestInfo|URL)=>Promise.resolve(
    new Response(null,{status:302,headers:{location:'http://localhost:8080/secret.jpg'}}))) as typeof fetch;
  if(await probeMedicalFigure(source,unsafe))throw Error('SSRF redirect must be denied');
  const html=((_:RequestInfo|URL)=>Promise.resolve(
    new Response('<html>Whole article</html>',{status:200,headers:{'content-type':'text/html'}}))) as typeof fetch;
  if(await probeMedicalFigure(source,html))throw Error('article page must not be a medical figure');
});


Deno.test('paid image search thumbnails are refused',()=>{
 assert(!allowedAsset('https://serpapi.com/searches/1234567890/images/abcde12345.jpg'), 'paid search images should be blocked');
 assert(!allowedAsset('https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRjK08_example123'), 'generic Google thumbnails should be blocked');
});

Deno.test('medical image resolver does not call paid search providers',()=>{
 const source=resolveMedicalPreviews.toString();
 if(/googleImagesProvider\s*\(/.test(source))
   throw Error('paid search was used in the automatic resolver');
});


Deno.test('PubMed Central is first for all specialties, without running image catalogues if enough figures found',async()=>{
  const old=globalThis.fetch, seen:string[]=[];
  globalThis.fetch=((input:RequestInfo|URL,init?:RequestInit)=>{
    const uri=String(input);
    seen.push(uri);
    if(uri.includes('/rest/search?')){
      const records=[1,2].map(n=>({pmcid:'PMC900000'+n,
        title:'Ultrasound of kidney hydronephrosis imaging review',
        authorString:'Open access radiology',
        abstractText:'Kidney renal ultrasound imaging review'}));
      return Promise.resolve(new Response(JSON.stringify({resultList:{result:records}}),{status:200}));
    }
    const xml=uri.match(/\/PMC900000([12])\/fullTextXML/);
    if(xml)return Promise.resolve(new Response(
      '<article><fig id="f'+xml[1]+'"><caption>Ultrasound of kidney shows renal hydronephrosis on sonographic image.</caption>'+
      '<graphic xlink:href="renal-ultrasound-'+xml[1]+'.jpg"/></fig></article>',
      {status:200,headers:{'content-type':'application/xml'}}));
    const page=uri.match(/articles\/PMC900000([12])\/$/);
    if(page)return Promise.resolve(new Response(
      '<figure><img src="https://cdn.ncbi.nlm.nih.gov/pmc/blobs/9/900000'+page[1]+'/ab/renal-ultrasound-'+page[1]+'.jpg"></figure>',
      {status:200,headers:{'content-type':'text/html'}}));
    if(uri.includes('cdn.ncbi.nlm.nih.gov/pmc/blobs/')&&init?.method==='HEAD')
      return Promise.resolve(new Response(null,{status:200,headers:{'content-type':'image/jpeg'}}));
    if(uri.includes('commons.wikimedia.org/w/api.php')||
       uri.includes('api.openverse.org/v1/images/'))
      throw Error('Image catalogues must not be contacted when PMC already supplied two figures');
    throw Error('Unexpected request: '+uri);
  }) as typeof fetch;
  try{
    const result=await resolveMedicalPreviews({
      query:'renal hydronephrosis ultrasound imaging',modality:'ultrasound',
      anatomy:'kidney',purpose:'sonographic hydronephrosis',
      image_type:'radiology_scan',plane:'not_applicable',
      required_features:['hydronephrosis'],excluded_features:[]});
    assert(result.images.length===2,'two real kidney ultrasound source figures expected');
    assert(result.images.every(x=>x.provider==='PubMed Central'),'all found images should be PMC');
    assert(result.article_previews.some(x=>x.figure_page?.includes('/figure/f1/')),
      'links to individual figures must be preserved');
    assert(!seen.some(x=>x.includes('serpapi.com')||x.includes('api.openverse.org')||
      x.includes('commons.wikimedia.org')),'PMC priority must prevent catalogue calls');
  }finally{globalThis.fetch=old;}
});

Deno.test('all-specialty fallback uses free catalogues only after PubMed yields no image',async()=>{
  const old=globalThis.fetch, calls:string[]=[];
  globalThis.fetch=((input:RequestInfo|URL)=>{
    const uri=String(input);calls.push(uri);
    if(uri.includes('/rest/search?')){
      return Promise.resolve(new Response(JSON.stringify({resultList:{result:[]}}),{status:200}));
    }
    if(uri.includes('commons.wikimedia.org/w/api.php'))
      return Promise.resolve(new Response(JSON.stringify({query:{pages:[]}}),{status:200}));
    if(uri.includes('api.openverse.org/v1/images/'))
      return Promise.resolve(new Response(JSON.stringify({results:[]}),{status:200}));
    return Promise.resolve(new Response(null,{status:404}));
  }) as typeof fetch;
  try{
    const r=await resolveMedicalPreviews({
      query:'liver MRI focal lesion',modality:'MRI',anatomy:'liver',
      image_type:'radiology_scan',purpose:'liver MRI lesion',
      plane:'axial',required_features:[],excluded_features:[]});
    assert(r.images.length===0,'no fabricated liver figures');
    const firstCatalog=calls.findIndex(x=>x.includes('commons.wikimedia.org')||x.includes('api.openverse.org'));
    assert(firstCatalog>0,'catalogue search happens only after PubMed lookup');
    assert(calls.slice(0,firstCatalog).some(x=>x.includes('/rest/search?')),
      'PubMed search must run first');
    assert(!calls.some(x=>x.includes('serpapi.com')),'paid search must never execute');
  }finally{globalThis.fetch=old;}
});

Deno.test('biliary CT images match the requested organ and exclude unrelated scans',()=>{
 const request=legacyImageRequest({
  query:'Common bile duct dilation on abdominal CT',
  anatomy:'biliary',modality:'CT',purpose:'show bile duct dilatation',
  image_type:'radiology_scan',required_features:['bile duct'],
 });
 const source='https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Rectum_anatomy.jpg';
 const item:ImagePreview={
  thumbnail:source,full:source,
  source:'https://commons.wikimedia.org/wiki/File:Rectum_anatomy.jpg',
  title:'Dilated common bile duct on axial CT scan',
  description:'CT scan with dilated CBD and intrahepatic bile duct',
  provider:'Wikimedia Commons',creator:'',license:'CC BY 4.0',
 };
 assert(imageIsTopical(item,request),'relevant biliary CT should be accepted');
 assert(!imageIsTopical({...item,title:'Spine fracture',description:'Axial CT scan of lumbar spine'},request),
  'unrelated CT image should be rejected');
});
