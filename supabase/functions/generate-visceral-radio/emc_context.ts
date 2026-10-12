
export type EmcDocument = {id:string;title:string;category:string;url:string;content?:string};
const normalize=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const ignored=new Set(['aigue','aigu','cancer','chirurgical','chirurgie','technique','traitement','pour','avec','dans','digestive','digestif','colorectale','traumatisme','traumatismes']);
export function emcTerms(topic:string):string[] {
  const terms=normalize(topic).split(/[^a-z0-9]+/).filter(t=>t.length>3&&!ignored.has(t));
  const families=[['pancreas','pancreat'],['cholecyst','vesicul'],['hepati','hepat','foie'],['splen','rate'],['achalas','heller','megaoesoph'],['eventration','eventrat'],['inguinal','aine'],['rectocol','ulcero','colectom'],['cholang','biliaire'],['appendic','appendicect'],['diverticul','sigmoid'],['sleeve','obesit','bypass'],['fuite','anastomo'],['rgo','reflux','fundoplic']];
  for(const family of families)if(family.some(t=>terms.some(w=>w.startsWith(t))))terms.push(...family);
  return [...new Set(terms)];
}
// Anatomical/procedure scope disambiguates homonymous operations before ranking.
// Generic words (trauma, digestive, cancer) must not select another organ.
export function rankEmc(topic:string,docs:EmcDocument[]):EmcDocument[] {
  const t=normalize(topic),terms=emcTerms(topic);
  const scopes:[RegExp,RegExp,RegExp?][]=[
    [/splen/, /\brates?\b|splen/],
    [/pancreatite aigue|necrose pancreatique/, /pancreatite aigue|necrose pancreatique/],
    [/tete du pancreas/, /duodenopancreatectomie cephalique|pancreatectomies cephaliques/],
    [/pancrea|wirsung/, /pancrea/],
    [/colon droit/, /colon droit|colectomie droite/],
    [/rectum/, /rectum/],
    [/diverticul/, /diverticul/, /oesoph|duodenum/],
    [/appendic/, /appendic/],
    [/cholecyst/, /cholecystectomie/],
    [/lithiase.*principale|angiochol/, /lithiase.*principale|biliodigestives.*lithiase/],
    [/cholangiocarc|cholang/, /cancers.*biliaire/],
    [/fuite anastomotique|fistule digestive|abces intra.abdominal|peritonite.*perforation/, /reinterventions.*infectieuses/],
    [/ulcere.*perfore/, /gastrectomies.*benignes|resections duodenales/],
    [/hernie inguinale|tapp|hernie etranglee/, /inguinal|aine/],
    [/hernie hiatale|para.oesophag/, /hernie.*hiatal|rgo|reflux/],
    [/eventration|reconstruction parietale/, /eventration/, /diaphrag/],
    [/hydatique/, /hydatique/],
    [/metastases hepatiques/, /metastases.*hepat/],
    [/hepat|foie/, /foie|hepat/],
    [/crohn/, /crohn/],
    [/rectocolite/, /recto.colite|ileoanal|ileoan/],
    [/hemorro/, /hemorro/],
    [/fissure|fistule.*anal/, /fissure|suppurations.*anal/],
    [/achalas/, /heller|megaoesoph/],
    [/reflux|fundoplic/, /rgo|reflux/],
    [/gastrique|estomac/, /gastrectom|estomac/],
    [/occlusion.*grele|ischemie mesenter/, /occlusions.*grele/],
    [/occlusion colique/, /colon.*occlusion/],
    [/traumatisme abdominal/, /traumatisme.*abdomin/],
    [/compartiment abdominal/, /laparotomie ecourtee/],
  ];
  const scope=scopes.find(([pattern])=>pattern.test(t));
  return docs.map(doc=>{
    const title=normalize(doc.title),category=normalize(doc.category);
    if(scope&&(!scope[1].test(title)||scope[2]?.test(title)))return {doc,score:0};
    let score=terms.reduce((n,w)=>n+(title.includes(w)?4:category.includes(w)?1:0),0);
    if(scope)score+=10;
    if(/tete du pancreas/.test(t)&&/duodenopancreatectomie cephalique/.test(title))score+=8;
    if(!/complication|fuite|fistule/.test(t)&&/complication/.test(title))score-=3;
    return {doc,score};
  }).filter(x=>x.score>=4).sort((a,b)=>b.score-a.score).slice(0,2).map(x=>x.doc);
}
export function emcExcerpt(topic:string,content:string,max=3200):string {
  const terms=emcTerms(topic);
  // Keep the article header/date and the relevant consecutive surgical passages.
  const cleaned=content.replace(/\u0002/g,'').replace(/^.*Document téléchargé.*$/gm,'');
  const blocks:{i:number;text:string}[]=[];
  let start=0;
  while(start<cleaned.length){
    let end=Math.min(start+1000,cleaned.length);
    if(end<cleaned.length){const newline=cleaned.lastIndexOf('\n',end);if(newline>start+500)end=newline+1;}
    blocks.push({i:blocks.length,text:cleaned.slice(start,end).trim()});start=end;
  }
  const best=blocks.map(b=>({...b,score:terms.reduce((n,t)=>n+(normalize(b.text).includes(t)?1:0),0)+(/installation|trocart|dissection|anastomose|temps op[eé]ratoire/i.test(b.text)?2:0)}))
    .sort((a,b)=>b.score-a.score).slice(0,Math.max(1,Math.floor((max-400)/1050))).sort((a,b)=>a.i-b.i);
  return (cleaned.slice(0,400)+'\n\n'+best.map(b=>'[Passage '+(b.i+1)+']\n'+b.text).join('\n\n')).slice(0,max);
}
export async function retrieveEmc(db:any,owner:string,topic:string):Promise<EmcDocument[]> {
  const {data,error}=await db.from('practice_emc_documents').select('id,title,category,url').eq('owner_id',owner);
  if(error)throw new Error('emc_library_unavailable');
  const ranked=rankEmc(topic,data||[]);
  if(!ranked.length)return [];
  const {data:full,error:readError}=await db.from('practice_emc_documents').select('id,title,category,url,content').eq('owner_id',owner).in('id',ranked.map(d=>d.id));
  if(readError)throw new Error('emc_document_unavailable');
  return ranked.map(d=>full.find((x:EmcDocument)=>x.id===d.id)).filter(Boolean);
}