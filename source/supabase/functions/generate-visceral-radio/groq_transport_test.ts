import {generationContract} from './generation_contract.ts';
import {generateJson,groqBudget,normalizeResponse,validateStructure,parseJSON,formatInstructions,quotaInfo} from './groq_transport.ts';

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
Deno.test('empty course content cannot be saved even after retry',async()=>{
 const c=generationContract('fiche'),short=fixture('fiche') as any;
 short.sections[0].content='';
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

Deno.test('malformed ten-case-QCM JSON recovers as five-question halves without losing planned phases',async()=>{
 const phases=[1,1,2,2,2,3,3,4,4,4];
 const c=generationContract('case_qcms',{count:10,phases,courseKeys:Array.from({length:10},(_,i)=>'s'+i)});
 let calls=0;
 const fetcher=(async(_url:unknown,opts:any)=>{
   calls++;
   const req=JSON.parse(String(opts.body));
   if(calls===1)return answer({choices:[{message:{content:'{"questions":[{"statement":"incomplete"'},finish_reason:'stop'}]});
   assert(req.messages[1].content.includes('EXACTEMENT 5 questions'),'bounded recovery used');
   const result=fixture('course_qcms') as any;
   result.questions=result.questions.slice(calls===2?0:5,calls===2?5:10);
   return answer({choices:[{message:{content:JSON.stringify(result)},finish_reason:'stop'}]});
 }) as typeof fetch;
 const got=await generateJson(c,'DOSSIER clinique fictif',{apiKey:'test',fetcher});
 assert(calls===3,'one failed large request and two bounded halves');
 assert(got.questions.length===10,'ten questions recovered');
 assert(got.questions.map((q:any)=>q.phase).join(',')===phases.join(','),'original chronological phases kept');
 assert(new Set(got.questions.map((q:any)=>q.statement)).size===10,'unique questions retained');
 assert(got.questions.every((q:any)=>q.options.length===5&&q.options.every((o:any)=>o.explanation)),'all clinical explanations kept');
});
Deno.test('Groq HTTP413 token quota is classified as rate-limited, not invalid payload',async()=>{
 const c=generationContract('case_qcms',{count:10});
 let calls=0;
 const fetcher=(async()=>{
   calls++;
   return answer({error:{code:'rate_limit_exceeded',type:'tokens',message:'Tokens per minute (TPM) exceeded'}},413,{'Retry-After':'45'});
 }) as typeof fetch;
 let err:any;
 try{await generateJson(c,'QCM de cas',{apiKey:'test',fetcher});}catch(e){err=e;}
 assert(err?.message==='groq_rate_limited','HTTP 413 must preserve token quota diagnostic');
 assert(err?.retryAfterSeconds===45,'provider retry delay honored');
 assert(calls===1,'no blind retry on quota');
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

Deno.test('case patient object retains all supplied clinical facts without regenerating',async()=>{
 const c=generationContract('case');const sample=fixture('case') as any;
 sample.patient={age:62,sex:'femme',history:['HTA','diabète'],presentation:{pain:'48 h',fever:false},weight:'67 kg'};
 let calls=0;
 const fetcher=(async(_url:unknown,opts:any)=>{
   calls++;const sent=JSON.parse(String(opts.body)).messages[1].content;
   assert(sent.includes('patient:string'),'patient type actually sent');
   assert(sent.includes('clinical_findings:string'),'stage field types actually sent');
   return answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]});
 }) as typeof fetch;
 const got=await generateJson(c,'cas clinique',{apiKey:'test',fetcher});
 assert(calls===1,'no technical regeneration');
 for(const fact of ['age: 62','femme','HTA','diabète','48 h','fever: false','67 kg'])
   assert(got.patient.includes(fact),'patient fact retained: '+fact);
 assert(got.stages.length===4,'four original stages');
});
Deno.test('all five modes send field types derived from their validation schemas',()=>{
 for(const mode of ['fiche','case','course_qcms','case_qcms','surgical_techniques'] as const){
   const c=generationContract(mode);const guide=formatInstructions(c);
   assert(guide.includes('string'),'explicit text type');
   for(const field of Object.keys((c.schema as any).properties))assert(guide.includes(field+':'),'typed root '+field);
   if(mode==='case')assert(guide.includes('"simple"|"intermediaire"|"complexe"'),'difficulty enum');
   if(mode.includes('qcms'))assert(guide.includes('reference:string'),'reference type');
 }
});

Deno.test('editorial character targets never discard a complete course or trigger retries',async()=>{
 const c=generationContract('fiche');const sample=fixture('fiche') as any;
 sample.sections[3].content='La gravité se juge sur la stabilité hémodynamique, la défaillance d’organe et le contrôle de la source.';
 let calls=0;const fetcher=(async()=>{calls++;return answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]});}) as typeof fetch;
 const got=await generateJson(c,'cours',{apiKey:'test',fetcher});
 assert(calls===1,'no retry for character target');
 assert(got.sections[3].content===sample.sections[3].content,'no padding, truncation or invention');
 assert(c.outputInstructions.includes('650 à 1800'),'residency depth target retained in prompt');
});
Deno.test('category labels and structured stage prose are normalized without regeneration',async()=>{
 const c=generationContract('case_qcms',{count:5,phases:[1,1,2,2,3]});const sample=fixture('course_qcms') as any;
 sample.questions=sample.questions.slice(0,5);
 sample.questions.forEach((q:any,i:number)=>{q.category=['Imagerie médicale','Technique opératoire','prise en charge','Chirurgie viscérale','diagnostic'][i];q.phase=4;});
 const fetcher=(async()=>answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]})) as typeof fetch;
 const got=await generateJson(c,'cas',{apiKey:'test',fetcher});
 assert(got.questions[0].category==='radiologie','image label');
 assert(got.questions[1].category==='technique_operatoire','operative label');
 assert(got.questions[2].category==='prise en charge','unknown label preserved');
 assert(got.questions.map((q:any)=>q.phase).join(',')==='1,1,2,2,3','planned phase sequence used');
 const data=fixture('case') as any;
 data.stages[0].clinical_findings={temperature:'38 °C',abdomen:['défense','douleur']};
 data.references={title:'Reference',url:'https://example.org'};data.extra='decorative';
 const normalized=normalizeResponse(generationContract('case'),data);
 validateStructure(generationContract('case').schema,normalized);
 assert(normalized.stages[0].clinical_findings.includes('38 °C'),'stage facts retained');
 assert(!('extra' in normalized),'extra transport key removed');
});
Deno.test('quota diagnostics preserve known delays and never invent a reset time',()=>{
 const info=quotaInfo({error:{message:'Rate limit reached on tokens per minute (TPM). Please try again in 1m2.5s.'}},new Headers());
 assert(info.retryAfterSeconds===63&&info.quotaScope==='tokens_per_minute','provider delay parsed');
 const daily=quotaInfo({error:{message:'tokens per day (TPD) limit'}},new Headers());
 assert(daily.retryAfterSeconds===null&&daily.quotaScope==='tokens_per_day','unknown reset stays unknown');
});
Deno.test('incorrect boolean options are still rejected rather than guessed',async()=>{
 const c=generationContract('course_qcms');const sample=fixture('course_qcms') as any;
 sample.questions[0].options[0].correct='true';
 const fetcher=(async()=>answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]})) as typeof fetch;
 let rejected=false;try{await generateJson(c,'cours',{apiKey:'test',fetcher});}catch(_){rejected=true;}
 assert(rejected,'medical answer values must not be inferred');
});

Deno.test('phase one can omit imaging not yet performed without inventing future findings',async()=>{
 const c=generationContract('case');const sample=fixture('case') as any;
 sample.stages[0].imaging_findings='';sample.stages[0].decisions='';
 let calls=0;const fetcher=(async()=>{calls++;return answer({choices:[{message:{content:JSON.stringify(sample)},finish_reason:'stop'}]});}) as typeof fetch;
 const data=await generateJson(c,'cas progressif',{apiKey:'test',fetcher});
 assert(calls===1&&data.stages[0].imaging_findings==='','no unnecessary retry or invented exam');
});
