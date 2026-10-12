import {rankEmc,emcExcerpt} from './emc_context.ts';
const docs=[
{id:'a',title:'Appendicectomie laparoscopique',category:'Appendice',url:'https://drive.google.com/a'},
{id:'b',title:'Chirurgie des rates pathologiques',category:'Rate',url:'https://drive.google.com/b'},
{id:'c',title:'Duodénopancréatectomie céphalique',category:'Pancréas',url:'https://drive.google.com/c'},
];
Deno.test('EMC retrieval matches surgical synonyms and rejects unsupported organs',()=>{
 for(const [topic,id] of [['Appendicite aiguë','a'],['Traumatisme splénique','b'],['Cancer de la tête du pancréas','c']]) {
  if(rankEmc(topic,docs)[0]?.id!==id)throw Error(topic+' wrong article');
 }
 if(rankEmc('Goitre et thyroïdectomie',docs).length)throw Error('unrelated EMC attribution');
});
Deno.test('EMC excerpts retain header/date and bounded operative context',()=>{
 const content='EMC 2006 — Article appendicectomie\n'+('installation trocart appendice dissection '.repeat(500));
 const result=emcExcerpt('appendicite',content);
 if(!result.includes('2006')||!result.includes('trocart')||result.length>3200)throw Error('lost provenance/budget');
});
