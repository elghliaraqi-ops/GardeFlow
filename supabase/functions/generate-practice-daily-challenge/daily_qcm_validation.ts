/** Validation pure des QCM IA. Aucune requête, aucune écriture ou image. */
export type DailyRef={title:string;url:string;year:string;organization:string;kind:string};
export type DailyCandidate={
 question:string;options:string[];correct_index:number;correction:string;topic:string;
 references:DailyRef[];illustration_query:string;image_request:Record<string,unknown>;
};
export type Rejection={position:number;reason:string};
const topics=['motif','symptome','examen','imagerie','synthese','prise_en_charge','orientation','avis_specialise'];
function plain(v:unknown,max=2500):string{
 return String(v??'').replace(/<[^>]+>/g,' ')
  .replace(/[\x00-\x1f]/g,' ').replace(/\s+/g,' ').trim().slice(0,max);
}
function canon(v:unknown):string{
 try{const u=new URL(String(v??''));
  return u.protocol==='https:'?u.origin+u.pathname.replace(/\/+$/,''):'';
 }catch{return '';}
}
export function dailyQcmFingerprint(value:unknown):string{
 return String(value??'').toLowerCase().replace(/\s+/g,' ').trim();
}
export function validateDailyBatch(raw:unknown, refs:DailyRef[],seen:Set<string>):{
 accepted:DailyCandidate[];rejected:Rejection[]
}{
 const input=raw&&typeof raw==='object'?raw as Record<string,unknown>:null;
 if(!Array.isArray(input?.qcms))
  return {accepted:[],rejected:[{position:0,reason:'qcms_not_array'}]};
 const accepted:DailyCandidate[]=[],rejected:Rejection[]=[];
 const refMap=new Map(refs.map(r=>[canon(r.url),r]));
 for(const [index,entry] of input.qcms.slice(0,8).entries()){
  const position=index+1;
  if(!entry||typeof entry!=='object'||Array.isArray(entry)){
   rejected.push({position,reason:'invalid_object'});continue;
  }
  const q=entry as Record<string,unknown>;
  const question=plain(q.question,1400),options=Array.isArray(q.options)
   ?q.options.map(x=>plain(x,450)):[];
  const correct=Number(q.correct_index),correction=plain(q.correction,6500);
  const topic=String(q.topic??'synthese'),fingerprint=dailyQcmFingerprint(question);
  const refsByUrl=Array.isArray(q.references)?q.references:[];
  const refsById=Array.isArray(q.source_ids)?q.source_ids:[];
  const permitted:DailyRef[]=[];
  for(const source of refsByUrl){
   const u=source&&typeof source==='object'?
    (source as Record<string,unknown>).url:undefined;
   const known=refMap.get(canon(u));
   if(known)permitted.push(known);
  }
  for(const sourceId of refsById){
   const n=Number(sourceId);
   if(Number.isInteger(n)&&n>=1&&n<=Math.min(8,refs.length))
    permitted.push(refs[n-1]);
  }
  const references=[...new Map(permitted.map(r=>[canon(r.url),r])).values()].slice(0,3);
  const failure=question.length<12?'question_too_short':
   options.length!==4?'option_count':
   options.some(x=>x.length<1)?'empty_option':
   new Set(options.map(dailyQcmFingerprint)).size!==4?'duplicate_options':
   correction.length<25?'correction_too_short':
   !Number.isInteger(correct)||correct<0||correct>3?'invalid_answer_index':
   !references.length?'unverified_source':
   !topics.includes(topic)?'invalid_topic':
   seen.has(fingerprint)?'duplicate_question':'';
  if(failure){rejected.push({position,reason:failure});continue;}
  seen.add(fingerprint);
  accepted.push({
   question,options,correct_index:correct,correction,topic,references,
   illustration_query:plain(q.image_search_query,140),
   image_request:q.image_request&&typeof q.image_request==='object'&&!Array.isArray(q.image_request)
     ?q.image_request as Record<string,unknown>:{}
  });
 }
 if(input.qcms.length>8)rejected.push({position:9,reason:'too_many_questions'});
 return {accepted,rejected};
}
export function validCachedDailyQuestion(raw:unknown):raw is Record<string,unknown>{
 if(!raw||typeof raw!=='object'||Array.isArray(raw))return false;
 const q=raw as Record<string,unknown>;
 return typeof q.question==='string'&&q.question.length>=12&&
  Array.isArray(q.options)&&q.options.length===4&&
  q.options.every(x=>typeof x==='string'&&x.trim().length>0)&&
  new Set(q.options.map(dailyQcmFingerprint)).size===4&&
  Number.isInteger(q.correct_index)&&Number(q.correct_index)>=0&&
  Number(q.correct_index)<=3&&typeof q.correction==='string'&&
  q.correction.length>=25&&topics.includes(String(q.topic))&&
  q.correction.includes('§SOURCES§');
}
