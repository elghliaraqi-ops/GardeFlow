/**
 * Public live smoke test for a representative existing Viscéral × Radio fiche.
 * Only searches open-access third-party images; no user data, images, or
 * provider credentials are stored.
 */
import {resolveMedicalPreviews,proxyMedicalImage} from '../supabase/functions/generate-visceral-radio/medical_image_previews.ts';

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
if(!result.article_previews.some(x=>x.source.includes('PMC7471246')&&
  x.figure_page?.includes('/figure/')))
  throw Error('Figure publication link was dropped');
const proxy=await proxyMedicalImage(figure.thumbnail);
const type=proxy.headers.get('content-type')||'';
console.log('LIVE_PROXY',JSON.stringify({status:proxy.status,type,source:figure.source}));
if(proxy.status!==200||!type.startsWith('image/'))
  throw Error('Medical image was found but was not renderable through the proxy');
await proxy.body?.cancel();
