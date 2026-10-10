import { allowedAsset, imageIsTopical, imageSearchTerms, imageSearchVariants, legacyImageRequest,
  rasterImageUrls, articleSearchVariants, articleFigureSnippets, articleFigureRelevant, pmcFigureAssets, pmcAssetForFigure, openGraphImageFromHtml, probeMedicalFigure, parseGoogleImageResults, googleMedicalCacheKey, resolveMedicalPreviews, type ImagePreview } from './medical_image_previews.ts';

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


Deno.test('PMC figure probe falls back to bounded GET if publisher blocks HEAD',async()=>{
  const source='https://pmc.ncbi.nlm.nih.gov/articles/PMC1234567/bin/rectal-t2.jpg';
  const methods:string[]=[];
  const mock=((input:RequestInfo|URL, init?:RequestInit)=>{
    if(String(input)!==source)throw Error('unexpected source');
    methods.push(init?.method||'');
    if(init?.method==='HEAD')return Promise.resolve(new Response(null,{status:405}));
    if(init?.method==='GET'){
      if((init.headers as Record<string,string>)?.Range!=='bytes=0-63')
        throw Error('unbounded GET prohibited');
      return Promise.resolve(new Response(new Uint8Array([0xff,0xd8,0xff]),
        {status:206,headers:{'content-type':'image/jpeg'}}));
    }
    throw Error('unexpected method');
  }) as typeof fetch;
  assert(await probeMedicalFigure(source,mock),'real image available via GET should pass');
  assert(methods.join(',')==='HEAD,GET','GET should only follow rejected HEAD');
});


Deno.test('rectal MRI figure captions do not need to repeat the article title',()=>{
  const r=legacyImageRequest({query:'Signal T2 du mésorectum et délimitation tumorale T3 vs T4',
    modality:'IRM T2',image_type:'radiology_scan',anatomy:'rectum',
    purpose:'T3 vs T4 on axial T2 imaging'});
  assert(articleFigureRelevant('Axial T2-weighted image of a T3 tumour invading the mesorectal fat',r),
    'caption inherits rectal MRI context from known article');
  assert(!articleFigureRelevant('Survival curve for rectal carcinoma',r),
    'survival plots must not be rendered as medical scan');
  assert(!articleFigureRelevant('Effect after re-evaluation of study cases using updated staging criteria on classification',r),
    'non-imaging staging diagrams must not be shown as MRI');
  assert(allowedAsset('https://europepmc.org/articles/PMC7471246/bin/rectal_fig3.jpg'),
    'public PMC article images served by Europe PMC should be allowed');
  assert(!allowedAsset('https://europepmc.org/articles/PMC7471246/../private.jpg'),
    'untrusted image path must remain blocked');
});

Deno.test('PMC rendered article provides real CDN figure URL, not fabricated /bin URL',()=>{
  const url='https://cdn.ncbi.nlm.nih.gov/pmc/blobs/9884/7471246/123abc/rectal_fig3.jpg';
  const html='<figure id="Fig3"><img src="'+url+'" alt="Figure 3"></figure>'+
    '<img src="https://evil.example/private.jpg">';
  const found=pmcFigureAssets(html);
  assert(found.length===1 && found[0]===url,'real figure must be extracted');
  assert(pmcAssetForFigure('rectal_fig3.jpg',url),'matching JATS filename is linked');
  assert(!pmcAssetForFigure('rectal_fig4.jpg',url),'wrong figure must not be shown');
});

Deno.test('free resolver returns inline figure and retains article link when catalog images fail',async()=>{
  const native=globalThis.fetch;
  globalThis.fetch=((input:RequestInfo|URL,init?:RequestInit)=>{
    const url=String(input);
    if(url.includes('/w/api.php?'))return Promise.resolve(new Response(
      JSON.stringify({query:{pages:[]}}),{status:200,headers:{'content-type':'application/json'}}));
    if(url.includes('/v1/images/?'))return Promise.resolve(new Response(
      JSON.stringify({results:[]}),{status:200,headers:{'content-type':'application/json'}}));
    if(url.includes('/rest/search?'))return Promise.resolve(new Response(
      JSON.stringify({resultList:{result:[]}}),{status:200,headers:{'content-type':'application/json'}}));
    if(url.includes('/PMC7471246/fullTextXML')){
      // Reproduce the actual Europe PMC 406 response if JSON is requested.
      const accept=new Headers(init?.headers).get('Accept')||'';
      if(!accept.includes('application/xml'))return Promise.resolve(
        new Response('Not Acceptable',{status:406}));
      return Promise.resolve(new Response(
        '<article><fig id="Fig3"><caption>Axial T2-weighted MRI of a T3 tumour invading the mesorectal fat.</caption><graphic xlink:href="rectal_fig3.jpg"/></fig></article>',
        {status:200,headers:{'content-type':'application/xml'}}));
    }
    if(url.includes('/fullTextXML'))return Promise.resolve(new Response('<article></article>',{status:200}));
    if(url==='https://pmc.ncbi.nlm.nih.gov/articles/PMC7471246/')return Promise.resolve(new Response(
      '<figure id="Fig3"><img src="https://cdn.ncbi.nlm.nih.gov/pmc/blobs/9884/7471246/123abc/rectal_fig3.jpg" alt="Fig. 3"></figure>',
      {status:200,headers:{'content-type':'text/html'}}));
    if(url==='https://cdn.ncbi.nlm.nih.gov/pmc/blobs/9884/7471246/123abc/rectal_fig3.jpg' &&
       init?.method==='HEAD')return Promise.resolve(new Response(null,{status:200,headers:{'content-type':'image/jpeg'}}));
    return Promise.resolve(new Response(null,{status:404}));
  }) as typeof fetch;
  try{
    const response=await resolveMedicalPreviews({query:'Rectal cancer T2 MRI T3 vs T4',
      modality:'IRM T2',purpose:'Axial T2 pelvic MRI showing rectal T3 tumour',
      anatomy:'rectum',image_type:'radiology_scan',plane:'axial',
      required_features:['T3','mesorectum'],excluded_features:[]});
    assert(response.images.some((v)=>v.thumbnail==='https://cdn.ncbi.nlm.nih.gov/pmc/blobs/9884/7471246/123abc/rectal_fig3.jpg'),
      'resolved real article image should be in gallery');
    assert(response.article_previews.some((v)=>v.source.includes('PMC7471246')&&
      v.figure_page?.includes('Fig3')),
      'article source link must still be present and point at the figure');
  }finally{globalThis.fetch=native;}
});


Deno.test('specific pelvic DWI request gets staged organ-preserving article searches',()=>{
  const r=legacyImageRequest({
    query:'Montrer la restriction diffusionnelle des ganglions iliaques internes',
    modality:'IRM diffusion',anatomy:'rectum',image_type:'radiology_scan',
    purpose:'DWI restriction in internal iliac lymph nodes'
  });
  const q=articleSearchVariants(r);
  assert(q[0].includes('pelvic lymph node diffusion'),'first search must retain DWI lymph nodes');
  assert(q[1].includes('rectal cancer lymph node'),'second search must retain the target organ and nodes');
  assert(!articleFigureRelevant('Axial T2 MRI shows extramural rectal tumour spread',r),
    'T2 rectal tumour must not be substituted for pelvic nodal DWI');
  assert(articleFigureRelevant('Axial diffusion-weighted MRI demonstrates restricted diffusion in an internal iliac lymph node',r),
    'real node DWI figure is appropriate');
  assert(!articleFigureRelevant('Axial T2 MRI shows enlarged internal iliac lymph nodes',r),
    'a T2 node image must not pretend to demonstrate diffusion restriction');
  assert(articleFigureRelevant('Axial T2 MRI shows enlarged internal iliac lymph nodes',r,true),
    'a contextual second-stage node MRI can be shown if explicitly labeled');
  assert(imageIsTopical({
    ...good,title:'Pelvic lymph node DWI MRI with rectal cancer nodal staging',
    description:'MRI DWI internal iliac lymph node restricted diffusion',
  },r),'clinical image metadata without rectal written twice is not silently rejected');
});
Deno.test('nodal DWI search finds article figure on second free query and preserves article link',async()=>{
  const native=globalThis.fetch;
  const searches:string[]=[];
  globalThis.fetch=((input:RequestInfo|URL,init?:RequestInit)=>{
    const url=String(input);
    if(url.includes('/w/api.php?'))return Promise.resolve(new Response(
      JSON.stringify({query:{pages:[]}}),{status:200}));
    if(url.includes('/v1/images/?'))return Promise.resolve(new Response(
      JSON.stringify({results:[]}),{status:200}));
    if(url.includes('/rest/search?')){
      const query=new URL(url).searchParams.get('query')||'';
      searches.push(query);
      const pmcid=query.includes('pelvic lymph node diffusion')?'PMC9000001':'PMC9000002';
      const entry={pmcid,title:'Rectal cancer pelvic lymph node MRI imaging',
        abstractText:'MRI pelvic lymph node rectal cancer',authorString:'Research radiology'};
      return Promise.resolve(new Response(JSON.stringify({resultList:{result:[entry]}}),{status:200}));
    }
    if(url.includes('PMC9000001/fullTextXML')||url.includes('PMC9000002/fullTextXML')){
      const first=url.includes('PMC9000001');
      const caption=first?'Axial T2 MRI shows extramural rectal tumour invasion':
        'Axial DWI MRI shows restricted diffusion of an internal iliac lymph node';
      const filename=first?'tumour.jpg':'iliac-node-dwi.jpg';
      return Promise.resolve(new Response(
        '<article><fig id="fig3"><caption>'+caption+'</caption><graphic xlink:href="'+filename+'"/></fig></article>',
        {status:200,headers:{'content-type':'application/xml'}}));
    }
    if(url==='https://pmc.ncbi.nlm.nih.gov/articles/PMC9000001/' ||
       url==='https://pmc.ncbi.nlm.nih.gov/articles/PMC9000002/'){
      const good=url.includes('PMC9000002');
      const file=good?'iliac-node-dwi.jpg':'tumour.jpg';
      return Promise.resolve(new Response(
        '<figure><img src="https://cdn.ncbi.nlm.nih.gov/pmc/blobs/a1/9000002/abcd/'+file+'"/></figure>',
        {status:200,headers:{'content-type':'text/html'}}));
    }
    if(url.includes('cdn.ncbi.nlm.nih.gov/pmc/blobs')&&init?.method==='HEAD')
      return Promise.resolve(new Response(null,{status:200,
        headers:{'content-type':'image/jpeg'}}));
    return Promise.resolve(new Response(null,{status:404}));
  }) as typeof fetch;
  try{
    const result=await resolveMedicalPreviews({
      query:'Montrer la restriction diffusionnelle des ganglions iliaques internes',
      purpose:'DWI restriction in internal iliac lymph nodes',modality:'IRM diffusion',
      anatomy:'rectum',image_type:'radiology_scan',plane:'axial',
      required_features:['iliac lymph node','DWI'],excluded_features:[],
    });
    assert(searches.length===2,'fallback article search runs exactly once if no figure found initially');
    assert(result.images.some(v=>v.full.endsWith('/iliac-node-dwi.jpg')),
      'second stage returns the actual nodal DWI figure');
    assert(result.article_previews.some(v=>v.source.includes('PMC9000002')&&
      v.figure_page?.includes('/figure/fig3/')),
      'matching publication and figure link must be visible beside the image');
    assert(!result.images.some(v=>v.full.endsWith('/tumour.jpg')),
      'generic tumour picture must not be shown for iliac DWI');
  }finally{globalThis.fetch=native;}
});

Deno.test('Google Images thumbnails are accepted only from narrow known hosts',()=>{
  const google='https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRjK08_example123';
  if(!allowedAsset(google))throw Error('gstatic thumbnail blocked');
  if(!allowedAsset('https://serpapi.com/searches/1234567890/images/abcde12345.jpg'))
    throw Error('SerpApi image thumbnail blocked');
  if(allowedAsset('https://encrypted-tbn0.gstatic.com/unsafe/path?q=tbn:ANd9GcRjK08_example123'))
    throw Error('arbitrary gstatic path accepted');
  if(allowedAsset('https://serpapi.com/search.json?api_key=private'))
    throw Error('backend API endpoint accepted as asset');
});
Deno.test('Google search images preserve source and do not silently grant a copyright license',()=>{
  const valid='https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRjK08_example123';
  const items=parseGoogleImageResults({images_results:[
    {title:'Rectal cancer T2 MRI',thumbnail:valid,
      original:'https://example.invalid/unsafe.jpg',link:'https://radiopaedia.org/articles/rectal-cancer',source:'Radiopaedia'},
    {title:'Fake image',thumbnail:'http://localhost/internal.png',link:'http://localhost/'}
  ]});
  if(items.length!==1||items[0].full!==valid)throw Error('invalid Google image mapping');
  if(items[0].provider!=='Google Images'||!items[0].license.includes('Droits à vérifier'))
    throw Error('Google Images must not imply a reuse license');
  const request=legacyImageRequest({query:'Rectal cancer T2 MRI',image_type:'radiology_scan',
    anatomy:'rectum',modality:'MRI',purpose:'Rectal cancer T2 MRI'});
  if(!imageIsTopical(items[0],request))throw Error('appropriate medical Google thumbnail rejected');
  if(imageIsTopical({...items[0],title:'Book cover annual report',description:'Annual report'},request))
    throw Error('Google results must still reject unrelated reports');
});

Deno.test('SerpApi paid search key is canonical across equivalent medical prompts',()=>{
 const first=googleMedicalCacheKey({query:'Rectal cancer T2 MRI',modality:'IRM T2',
   image_type:'radiology_scan',anatomy:'rectum',purpose:'Illustrate the tumor'});
 const second=googleMedicalCacheKey({query:'Rectal cancer T2 MRI',modality:'IRM T2',
   image_type:'radiology_scan',anatomy:'rectum',purpose:'Describe the tumor'});
 if(!first || first!==second)throw Error('Identical medical search must share cached Google results');
});
Deno.test('free medical image endpoint must not trigger SerpApi calls',()=>{
 const source=resolveMedicalPreviews.toString();
 // The only paid call belongs to the explicit resolveGoogleMedicalImages handler.
 if(/googleImagesProvider\s*\(/.test(source))
   throw Error('SerpApi invoked by automatic/free image endpoint');
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
    assert(!calls.some(x=>x.includes('serpapi.com')),'paid search must remain manual');
  }finally{globalThis.fetch=old;}
});
