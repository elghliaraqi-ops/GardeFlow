/**
 * Public live smoke test for a representative existing Viscéral × Radio fiche.
 * Only searches open-access third-party images; no user data, images, or
 * provider credentials are stored.
 */
import {resolveMedicalPreviews,proxyMedicalImage,pmcFigureAssets,pmcAssetForFigure,articleFigureSnippets,articleFigureRelevant,legacyImageRequest,probeMedicalFigure} from '../supabase/functions/generate-visceral-radio/medical_image_previews.ts';

// End-to-end live check with resolver HTTP-stage diagnostics enabled.
const pmcid='PMC7471246';
const [xmlResp,htmlResp]=await Promise.all([
  fetch('https://www.ebi.ac.uk/europepmc/webservices/rest/'+pmcid+'/fullTextXML'),
  fetch('https://pmc.ncbi.nlm.nih.gov/articles/'+pmcid+'/'),
]);
const xml=await xmlResp.text(),html=await htmlResp.text();
const found=articleFigureSnippets(xml);
const assets=pmcFigureAssets(html);
const requestForProbe=legacyImageRequest({
  query:'rectal cancer T2 MRI T3 vs T4',purpose:'T3 vs T4 rectal cancer',
  anatomy:'rectum',modality:'IRM T2',image_type:'radiology_scan'});
const matching=found.filter(f=>articleFigureRelevant(f.caption,requestForProbe));
const selected=matching.flatMap(f=>assets.filter(x=>pmcAssetForFigure(f.href,x))).slice(0,3);
console.log('DIAGNOSTIC_PMC',JSON.stringify({
  xml:xmlResp.status,html:htmlResp.status,figureTotal:found.length,
  relevant:matching.length,assetCount:assets.length,selectedCount:selected.length,
  sampleAsset:assets[0],sampleFigure:matching[0]?.href,sampleMatched:selected[0]}));
for(const url of [assets[0],selected[0],
 'https://media.springernature.com/lw685/springer-static/image/art%3A10.1186%2Fs13244-020-00890-7/MediaObjects/13244_2020_890_Fig11_HTML.png']){
 if(!url)continue;
 const response=await fetch(url,{method:'HEAD',redirect:'manual',signal:AbortSignal.timeout(5500)});
 console.log('DIAGNOSTIC_HEAD',JSON.stringify({url,status:response.status,mime:response.headers.get('content-type'),
  valid:await probeMedicalFigure(url)}));
}

const request={
  query:'rectal cancer T2 MRI T3 vs T4',
  purpose:'Illustrer le signal T2 du mésorectum et la délimitation tumorale (T3 vs T4)',
  anatomy:'rectum',modality:'IRM T2',image_type:'radiology_scan',
  plane:'axial',required_features:['mesorectum','T3'],excluded_features:[],
};
const result=await resolveMedicalPreviews(request);
console.log('LIVE_FIGURES',JSON.stringify({
  count:result.images.length,articleCount:result.article_previews.length,
  titles:result.images.map(x=>x.title.slice(0,90)),
  assetUrls:result.images.map(x=>x.thumbnail),
  articleSources:result.article_previews.map(x=>x.source),
  searches:result.image_sources_searched,
}));
const figure=result.images.find(x=>x.provider==='PubMed Central'&&
  x.thumbnail.startsWith('https://cdn.ncbi.nlm.nih.gov/pmc/blobs/'));
if(!figure)throw Error('No renderable external PubMed Central figure discovered');
if(!result.article_previews.some(x=>x.figure_page?.includes('/figure/')&&
  result.images.some(image=>image.source===x.figure_page)))
  throw Error('Matching scientific article/figure link was dropped');
const proxy=await proxyMedicalImage(figure.thumbnail);
const type=proxy.headers.get('content-type')||'';
console.log('LIVE_PROXY',JSON.stringify({status:proxy.status,type,source:figure.source}));
if(proxy.status!==200||!type.startsWith('image/'))
  throw Error('Medical image was found but was not renderable through the proxy');
await proxy.body?.cancel();


const nodal=await resolveMedicalPreviews({
  query:'Montrer la restriction diffusionnelle des ganglions iliaques internes',
  purpose:'Restricted diffusion of internal iliac lymph nodes on pelvic MRI',
  anatomy:'rectum',modality:'IRM diffusion DWI ADC',
  image_type:'radiology_scan',plane:'axial',
  required_features:['pelvic lymph node','DWI'],excluded_features:[]
});
console.log('LIVE_NODAL_FALLBACK',JSON.stringify({
  count:nodal.images.length,
  articleCount:nodal.article_previews.length,
  titles:nodal.images.map(x=>x.title.slice(0,160)),
  articleSources:nodal.article_previews.map(x=>x.source),
  searches:nodal.image_sources_searched,
}));
// No fixed medical figure is guaranteed for any specific topic. The source
// links stay available if no suitably illustrated open-access paper exists.
if(nodal.images.some(x=>!x.source.startsWith('https://')))
  throw Error('Nodal fallback lost medical source attribution');
