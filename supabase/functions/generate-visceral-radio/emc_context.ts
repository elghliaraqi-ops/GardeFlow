import type { GenerationContract } from './generation_contract.ts';

export type EmcDocument = {id:string;title:string;category:string;url:string;content?:string};
const normalize=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const ignored=new Set(['aigue','aigu','cancer','chirurgical','chirurgie','technique','traitement','pour','avec','dans','droit','gauche']);
export function emcTerms(topic:string):string[] {
  const terms=normalize(topic).split(/[^a-z0-9]+/).filter(t=>t.length>3&&!ignored.has(t));
  const families=[['pancreas','pancreat'],['cholecyst','vesicul'],['hepati','hepat','foie'],['splen','rate'],['achalas','heller','megaoesoph'],['eventration','eventrat'],['inguinal','aine'],['rectocol','ulcero','colectom'],['cholang','biliaire'],['appendic','appendicect'],['diverticul','sigmoid'],['sleeve','obesit','bypass'],['fuite','anastomo'],['rgo','reflux','fundoplic']];
  for(const family of families)if(family.some(t=>terms.some(w=>w.startsWith(t))))terms.push(...family);
  return [...new Set(terms)];
}
export function rankEmc(topic:string,docs:EmcDocument[]):EmcDocument[] {
  const terms=emcTerms(topic);
  return docs.map(doc=>{
    const title=normalize(doc.title),category=normalize(doc.category);
    const score=terms.reduce((n,t)=>n+(title.includes(t)?4:category.includes(t)?1:0),0);
    return {doc,score};
  }).filter(x=>x.score>=4).sort((a,b)=>b.score-a.score).slice(0,2).map(x=>x.doc);
}
export function emcExcerpt(topic:string,content:string,max=3200):string {
  const terms=emcTerms(topic);
  // Keep the article header/date and the relevant consecutive surgical passages.
  const blocks=Array.from({length:Math.ceil(content.length/900)},(_,i)=>({i,text:content.slice(i*900,(i+1)*900)}));
  const best=blocks.map(b=>({...b,score:terms.reduce((n,t)=>n+(normalize(b.text).includes(t)?1:0),0)+(/installation|trocart|dissection|anastomose|temps op[eé]ratoire/i.test(b.text)?2:0)}))
    .sort((a,b)=>b.score-a.score).slice(0,3).sort((a,b)=>a.i-b.i);
  return (content.slice(0,400)+'\n'+best.map(b=>'[Passage '+(b.i+1)+'] '+b.text).join('\n')).slice(0,max);
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
export function emcContract():GenerationContract {
  const section={type:'object',additionalProperties:false,required:['title','content','key_points'],properties:{title:{type:'string'},content:{type:'string'},key_points:{type:'array',items:{type:'string'}}}};
  return {mode:'case',name:'emc_surgical_supplement',requestedCount:null,
    schema:{type:'object',additionalProperties:false,required:['sections'],properties:{sections:{type:'array',minItems:6,maxItems:6,items:section}}},
    outputInstructions:'Complément EMC uniquement : six rubriques dans cet ordre : indications et limites, anatomie et structures à protéger, installation et voies d abord, temps opératoires, variantes et difficultés, complications et surveillance. Chaque rubrique explique les faits présents dans les passages fournis. Reformulation synthétique, aucune copie longue, aucun détail absent inventé. Signale si un détail est absent. Pas de QCM ni image. Les documents EMC anciens ne constituent pas les dernières recommandations.'};
}
