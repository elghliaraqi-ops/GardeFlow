import {generationContract} from './generation_contract.ts';
import {operativeTechniquesSchema,addSurgicalTechniques,hasSurgicalTechniques} from './surgical_techniques.ts';
Deno.test('initial fiche and historic chapter use exactly the same technique JSON and prompt fields',()=>{
 const fresh=generationContract('fiche'),historic=generationContract('surgical_techniques');
 const root=(fresh.schema as any).properties;
 const old=(historic.schema as any).properties.operative_techniques;
 if(JSON.stringify(root.operative_techniques)!==JSON.stringify(operativeTechniquesSchema))throw Error('fresh schema drift');
 if(JSON.stringify(old.items)!==JSON.stringify(operativeTechniquesSchema.items))throw Error('historic schema drift');
 for(const c of [fresh,historic])for(const key of ['operative_techniques','name','indications','steps'])if(!c.outputInstructions.includes(key))throw Error('prompt missing '+key);
 if(old.items.properties.steps.minItems!==4||old.items.properties.steps.maxItems!==6)throw Error('step count drift');
 if(historic.outputInstructions.includes('4 objets stages')||historic.outputInstructions.includes('image_requests'))throw Error('unrelated schema instructions');
});
Deno.test('historic enrichment adds chapter cards and preserves all existing data',()=>{
 const fiche={title:'Ancien cours',emc:{status:'ready'},sections:Array.from({length:10},(_,i)=>({key:'k'+i,content:'Texte initial '+i,key_points:['fait'],image_requests:[]}))};
 const before=JSON.stringify(fiche),techniques=[{name:'Technique',indications:'Selon le terrain',steps:['a','b','c','d']}];
 const enriched=addSurgicalTechniques(fiche,techniques);
 if(JSON.stringify(fiche)!==before||enriched.sections[7].content!==fiche.sections[7].content||!hasSurgicalTechniques(enriched))throw Error('historic course overwritten');
 for(const i of [0,1,2,3,4,5,6,8,9])if(JSON.stringify(enriched.sections[i])!==JSON.stringify(fiche.sections[i]))throw Error('unrelated chapter edited');
});
