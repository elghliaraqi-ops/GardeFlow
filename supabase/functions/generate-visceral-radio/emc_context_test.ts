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

Deno.test('EMC search disambiguates organ, side and acute versus chronic disease',()=>{
 const misleading=[
 {id:'wrong',title:'Traumatismes fermés du foie',category:'Foie',url:''},
 {id:'strategy',title:'Stratégie oncochirurgicale des métastases hépatiques',category:'Foie',url:''},
 {id:'rate',title:'Chirurgie des rates pathologiques',category:'Rate',url:''},
 {id:'left',title:'Technique de la colectomie gauche',category:'Colon',url:''},
 {id:'right',title:'Colectomie pour cancer du colon droit',category:'Colon',url:''},
 {id:'chronic',title:'Dérivation dans la pancréatite chronique',category:'Pancréas',url:''},
 {id:'tail',title:'Pancréatectomies gauches',category:'Pancréas',url:''},
 {id:'head',title:'Duodénopancréatectomie céphalique',category:'Pancréas',url:''},
 ];
 for(const [topic,id] of [['Traumatisme splénique','rate'],['Cancer du côlon droit','right'],['Cancer de la tête du pancréas','head']]) {
  if(rankEmc(topic,misleading)[0]?.id!==id)throw Error('wrong context: '+topic);
 }
 if(rankEmc('Pancréatite aiguë',misleading).length)throw Error('chronic operation attributed to acute disease');
});
