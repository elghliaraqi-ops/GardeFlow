/**
 * Evidence and licensed external educational media for Practice generators.
 * No image bytes, local files or Base64 ever enter Supabase.
 */
export type PreviewLink={
 title:string;preview_url:string;source_url:string;license:string;creator:string;provider:string
};
function clean(value:unknown,max=250):string{
 return String(value??'').replace(/<[^>]+>/g,' ').replace(/[\x00-\x1f]/g,' ')
  .replace(/\s+/g,' ').trim().slice(0,max);
}
export const medicalEvidencePolicy=[
 'PRIORITÉ CLINIQUE OBLIGATOIRE — date actuelle : '+new Date().toISOString().slice(0,10)+'.',
 'Le cas fictif, chaque question, TOUTES les corrections, les examens complémentaires, indications,',
 'contre-indications, seuils, doses, conduites à tenir, décisions chirurgicales ou médicales,',
 'surveillance, suivi et orientation doivent être compatibles avec les RECOMMANDATIONS',
 'LES PLUS RÉCENTES VÉRIFIABLES parmi les sources réellement retrouvées.',
 'Prioriser les recommandations officielles et consensus de sociétés savantes et leur année,',
 'puis les revues systématiques pertinentes; tenir compte du patient, du contexte et du pays.',
 'NE PAS présenter comme « dernière recommandation » un texte ancien ou non vérifié.',
 'Si aucune recommandation fiable ne peut être vérifiée, expliquer les incertitudes et ne pas',
 'inventer de recommandations datées, scores, posologies, seuils ou certitudes.',
 'Chaque question/correction cite les références vérifiées du catalogue fourni, sans inventer',
 'de source, de date, de citation, de fait du dossier clinique ou de résultat d’imagerie.',
 'ILLUSTRATIONS : proposer image_search_query EN ANGLAIS uniquement si une image externe',
 'cliniquement adaptée (ECG, imagerie, anatomie) enrichit le dossier; sinon laisser vide.',
 'Images uniquement sous forme de miniatures/liens HTTPS avec licence/attribution vérifiées.',
 'Aucun stockage de fichier, image, miniature ou Base64 en base ou dans Supabase Storage.',
 'Ne jamais montrer une image contredisant les constatations du dossier; toute image extérieure',
 'doit être étiquetée « illustration pédagogique, non issue du patient ».'
].join('\n');
export async function recentGuidelineCatalog(specialty:string):Promise<string>{
 const query=clean(specialty,85);
 if(!query)return '';
 const abort=new AbortController();
 const timeout=setTimeout(()=>abort.abort(),8000);
 try{
  const qs=new URLSearchParams({
   query:query+' AND (guideline OR consensus OR practice guideline OR recommendations)',
   format:'json',resultType:'core',pageSize:'25'
  });
  const response=await fetch('https://www.ebi.ac.uk/europepmc/webservices/rest/search?'+qs,{
   signal:abort.signal,headers:{Accept:'application/json'}
  });
  if(!response.ok)return '';
  const payload=await response.json() as {resultList?:{result?:Record<string,unknown>[]}};
  const now=new Date().getUTCFullYear();
  const entries=(payload.resultList?.result??[]).flatMap(item=>{
   const title=clean(item.title,260);
   const year=Number(item.pubYear??0),doi=String(item.doi??'');
   const pmid=String(item.pmid??'');
   const url=/^10\.\d{4,9}\//.test(doi)?'https://doi.org/'+doi:
    /^\d+$/.test(pmid)?'https://europepmc.org/article/MED/'+pmid:'';
   if(!title||!url||year<2000||year>now)return [];
   return [{title,year,url,rank:/(guideline|recommendation|consensus|position statement)/i.test(title)?1:0}];
  }).sort((a,b)=>b.rank-a.rank||b.year-a.year);
  const latest=entries.filter(e=>e.year>=now-6);
  const unique=[...new Map((latest.length?latest:entries).map(e=>[e.url,e])).values()]
   .slice(0,7);
  return unique.map(e=>e.year+' | '+e.title+' | '+e.url).join('\n');
 }catch{return '';}finally{clearTimeout(timeout);}
}
export function supportedMedicalImageLink(preview:unknown,source:unknown):boolean{
 try{
  const a=new URL(String(preview)),b=new URL(String(source));
  if(a.protocol!=='https:'||b.protocol!=='https:')return false;
  if(a.hostname==='upload.wikimedia.org'&&b.hostname==='commons.wikimedia.org')
   return true;
  if(a.hostname==='api.openverse.org'&&b.hostname==='openverse.org'){
   const match=a.pathname.match(/^\/v1\/images\/([a-f0-9-]{36})\/thumb\/$/);
   return Boolean(match&&b.pathname==='/image/'+match[1]&&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(match[1]));
  }
 }catch{/* Malformed URLs fail closed. */}
 return false;
}
export function vettedOpenverseImage(item:Record<string,unknown>,query:string,guard?:RegExp):
 PreviewLink|null{
 const id=String(item.id??'').toLowerCase();
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id))
  return null;
 const license=String(item.license??'').toLowerCase();
 if(!['by','by-sa','cc0','pdm'].includes(license)||item.mature===true)
  return null;
 const title=clean(item.title,220),creator=clean(item.creator,110);
 if(title.length<5)return null;
 if(guard&&!guard.test(title))return null;
 const terms=String(query).toLowerCase().split(/[^a-z0-9]+/).filter(x=>
  x.length>=4&&!['medical','image','illustration','diagram','example','labeled',
    'scan','normal','patient','disease','anatomy','clinical'].includes(x));
 if(terms.length&&terms.every(term=>!title.toLowerCase().includes(term)))return null;
 const result={
  title,creator,license:license.toUpperCase(),provider:'Openverse',
  preview_url:'https://api.openverse.org/v1/images/'+id+'/thumb/',
  source_url:'https://openverse.org/image/'+id
 };
 return supportedMedicalImageLink(result.preview_url,result.source_url)?result:null;
}
export async function findOpenverseMedicalPreview(query:string,guard?:RegExp):
 Promise<PreviewLink|null>{
 const cleaned=clean(query,125);
 if(!cleaned)return null;
 const abort=new AbortController();
 const timeout=setTimeout(()=>abort.abort(),5500);
 try{
  const qs=new URLSearchParams({q:cleaned,page_size:'8',
   license:'by,by-sa,cc0,pdm',filter_dead:'true'});
  const response=await fetch('https://api.openverse.org/v1/images/?'+qs,{
   signal:abort.signal,headers:{Accept:'application/json'}
  });
  if(!response.ok)return null;
  const payload=await response.json() as {results?:Record<string,unknown>[]};
  for(const raw of payload.results??[]){
   const result=vettedOpenverseImage(raw,cleaned,guard);
   if(result)return result;
  }
 }catch{/* Optional external API never blocks core generations. */}
 finally{clearTimeout(timeout);}
 return null;
}
