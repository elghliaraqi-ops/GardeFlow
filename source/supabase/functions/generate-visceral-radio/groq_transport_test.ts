import {generationContract} from './generation_contract.ts';
import {generateJson,groqBudget,normalizeResponse,validateStructure,parseJSON} from './groq_transport.ts';

function assert(ok:unknown,message:string){if(!ok)throw Error(message);}
function fixture(mode:'fiche'|'course_qcms'|'case'){
 if(mode==='fiche')return {
   title:'Péritonite postopératoire',summary:'Cours de chirurgie digestive et radiologie',
   sections:Array.from({length:10},(_,i)=>({
     key:'s'+i,title:'Chapitre '+(i+1),
     content:('Rapports anatomiques, critères discriminants, imagerie et prise en charge selon la stabilité. ').repeat(9),
     key_points:Array.from({length:4},(_,j)=>'Critère '+j+' : indication selon gravité et terrain'),
     image_requests:[],
   })),
   operative_techniques:[{name:'Laparoscopie diagnostique',indications:'Selon stabilité du patient',
     steps:['Accès et exploration','Identifier la cause','Traiter la lésion','Contrôler l’hémostase']}],
   study_core:Array.from({length:10},(_,i)=>'Fait clinique enseigné numéro '+i),
   references:[],
 };
 if(mode==='case')return {
   title:'Cas digestif',patient:'Adulte stable',difficulty:'complexe',recommended_qcms:10,
   stages:Array.from({length:4},(_,i)=>({
     phase:i+1,title:'Phase '+i,narrative:'Évolution progressive du cas',
     clinical_findings:'Évaluation clinique',imaging_findings:'TDM à discuter',
     decisions:'Décision selon stabilité',image_requests:[],
   })),
   final_diagnosis:'Diagnostic du cas',learning_points:['Point du cours'],references:[],
 };
 return {questions:Array.from({length:10},(_,i)=>({
   phase:1,category:'chirurgie',statement:'Quel critère dans la situation '+i+' ?',
   course_section_key:'s'+(i%10),teaching_point:'Indication opératoire à adapter au contexte clinique',
   options:Array.from('ABCDE').map((key,j)=>({key,text:'Proposition '+j,
     correct:j===0,explanation:'Justification clinique selon le terrain'})),
   global_explanation:'La prise en charge dépend de la stabilité du patient.',
   reference:'',image_requests:[],
 }))};
}
function answer(body:any,status=200,headers?:Record<string,string>){
 return new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json',...headers}});
}
Deno.test('one chat-completions JSON request for valid 10-section residency course',async()=>{
 const contract=generationContract('fiche');
 const sample=fixture('fiche');
 const calls:any[]=[];
 const fetcher=(async (_url:unknown,options:any)=>{
   calls.push(JSON.parse(String(options.body)));
   return answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]});
 }) as typeof fetch;
 const got=await generateJson(contract,'SUJET CENTRAL: péritonite',{apiKey:'test',fetcher});
 assert(got.sections.length===10,'ten chapters');
 assert(got.sections.every((s:any)=>s.content.length>=650),'chapters retain residency depth');
 assert(calls.length===1,'one request normally');
 assert(calls[0].response_format?.type==='json_object','first transport uses JSON-object decoder');
 assert(!('schema' in (calls[0].response_format||{})),'no oversized decoder schema');
});
Deno.test('JSON HTTP400 uses one plain-chat recovery while preserving all chapters',async()=>{
 const c=generationContract('fiche'),requests:any[]=[];
 const fetcher=(async (_url:unknown,opts:any)=>{
   requests.push(JSON.parse(String(opts.body)));
   return requests.length===1
     ?answer({error:{code:'json_validate_failed',message:'Failed to generate JSON'}},400)
     :answer({choices:[{message:{content:JSON.stringify(fixture('fiche'))},finish_reason:'stop'}]});
 }) as typeof fetch;
 const data=await generateJson(c,'SUJET CENTRAL: péritonite',{apiKey:'test',fetcher});
 assert(data.sections.length===10,'all chapters recovered');
 assert(requests.length===2,'only one technical retry');
 assert(!requests[1].response_format,'fallback must bypass JSON mode entirely');
});
Deno.test('10 QCM and 50 explained options stay aligned after JSON transport',async()=>{
 const c=generationContract('course_qcms',{count:10,courseKeys:Array.from({length:10},(_,i)=>'s'+i)});
 const fetcher=(async()=>answer({choices:[{message:{content:JSON.stringify(fixture('course_qcms'))},finish_reason:'stop'}]})) as typeof fetch;
 const data=await generateJson(c,'cours enseigné',{apiKey:'test',fetcher});
 assert(data.questions.length===10,'ten QCM required');
 assert(data.questions.every((q:any)=>q.options.length===5&&q.options.every((o:any)=>o.explanation)),'all options explained');
});
Deno.test('failed medical depth cannot be saved even after retry',async()=>{
 const c=generationContract('fiche'),short=fixture('fiche') as any;
 short.sections[0].content='Résumé superficiel';
 let calls=0;
 const fetcher=(async()=>{calls++;return answer({choices:[{message:{content:JSON.stringify(short)},finish_reason:'stop'}]});}) as typeof fetch;
 let error='';
 try{await generateJson(c,'fiche de résidanat',{apiKey:'test',fetcher});}
 catch(e){error=String((e as Error).message);}
 assert(error==='groq_invalid_structured_output','superficial course rejected');
 assert(calls===2,'exactly one repair retry');
});
Deno.test('429 quota must not be retried and exposes retry-after',async()=>{
 const c=generationContract('fiche');let calls=0;
 const fetcher=(async()=>{calls++;return answer({error:{code:'rate_limit_exceeded'}},429,{'Retry-After':'37'});}) as typeof fetch;
 let err:any;
 try{await generateJson(c,'cours',{apiKey:'test',fetcher});}catch(e){err=e;}
 assert(err?.message==='groq_rate_limited','quota preserved');
 assert(err?.retryAfterSeconds===37,'retry delay honored');
 assert(calls===1,'no needless extra rate-limited request');
});
Deno.test('compact image data is normalized but clinical facts are not created',()=>{
 const c=generationContract('case');
 const obj=fixture('case') as any;
 obj.stages[0].image_requests=[{query:'axial CT biliary dilation',modality:'CT',
   purpose:'dilation',image_type:'radiology_scan',plane:'axial',
   required_features:['dilated bile ducts'],untrusted_url:'https://invalid'}];
 normalizeResponse(c,obj);
 validateStructure(c.schema,obj);
 assert(!('untrusted_url' in obj.stages[0].image_requests[0]),'untrusted URLs stripped');
 assert(parseJSON('some text {"answer":42}').answer===42,'plain text fallback extracts JSON');
 assert(groqBudget(c,'small prompt')>1800,'sufficient budget');
});
Deno.test('optional image plane aliases normalize without discarding QCM clinical content',()=>{
 const c=generationContract('course_qcms');
 const data=fixture('course_qcms') as any;
 const intent={query:'biliary CT',modality:'CT',purpose:'bile ducts',image_type:'radiology_scan',plane:'transverse',required_features:['dilation']};
 data.questions[0].image_requests=[{...intent}];
 data.questions[1].image_requests=[{...intent,plane:'unknown-plane'}];
 normalizeResponse(c,data);validateStructure(c.schema,data);
 assert(data.questions[0].image_requests[0].plane==='axial','known plane mapped');
 assert(data.questions[1].image_requests.length===0,'unknown optional intent omitted');
 assert(data.questions.length===10&&data.questions[1].options.length===5,'medical corrections retained');
});
Deno.test('truncated 10 QCM recover as two complete five-question halves',async()=>{
 const c=generationContract('course_qcms');let calls=0;
 const fetcher=(async(_url:unknown,opts:any)=>{
   calls++; const request=JSON.parse(String(opts.body));
   if(calls===1)return answer({choices:[{message:{content:'{"questions":['},finish_reason:'length'}]});
   assert(request.messages[1].content.includes('EXACTEMENT 5 questions'),'half contract sent');
   const data=fixture('course_qcms') as any;
   data.questions=data.questions.slice(calls===2?0:5,calls===2?5:10);
   return answer({choices:[{message:{content:JSON.stringify(data)},finish_reason:'stop'}]});
 }) as typeof fetch;
 const data=await generateJson(c,'cours',{apiKey:'test',fetcher});
 assert(calls===3&&data.questions.length===10,'complete ten-question recovery');
 assert(new Set(data.questions.map((q:any)=>q.statement)).size===10,'distinct halves');
});

Deno.test('bibliographic metadata formats cannot reject an otherwise complete QCM batch',async()=>{
 const c=generationContract('course_qcms');const sample=fixture('course_qcms') as any;
 sample.questions[0].reference={title:'Guideline',year:2025,url:'https://example.org/guideline'};
 sample.questions[1].reference=['Source A',{citation:'Source B'}];
 sample.questions[2].reference=null;
 delete sample.questions[3].reference;
 let calls=0;
 const fetcher=(async()=>{calls++;return answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]});}) as typeof fetch;
 const data=await generateJson(c,'cours',{apiKey:'test',fetcher});
 assert(calls===1,'no quota-consuming retry for citation formatting');
 assert(data.questions[0].reference==='Guideline — 2025 — https://example.org/guideline','source metadata retained');
 assert(data.questions[1].reference==='Source A ; Source B','citation list retained');
 assert(data.questions[2].reference===''&&data.questions[3].reference==='','no invented sources');
 assert(data.questions.every((q:any)=>q.options.length===5),'all clinical corrections retained');
});

Deno.test('surplus QCM keep the requested prefix with one provider request',async()=>{
 for(const count of [5,10]){
   const c=generationContract('course_qcms',{count});const sample=fixture('course_qcms') as any;
   sample.questions.push({...sample.questions[0],statement:'Surplus question'});
   let calls=0;
   const fetcher=(async()=>{calls++;return answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]});}) as typeof fetch;
   const data=await generateJson(c,'cours',{apiKey:'test',fetcher});
   assert(calls===1,'surplus must not trigger a quota-consuming retry');
   assert(data.questions.length===count,'exact requested count');
   assert(data.questions[count-1].statement===sample.questions[count-1].statement,'original order preserved');
   assert(data.questions.every((q:any)=>q.options.length===5),'all retained corrections present');
 }
});
