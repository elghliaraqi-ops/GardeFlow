// Shared by the initial fiche and historic chapter enrichment: prompt = JSON.
const technique = {
  type:'object',additionalProperties:false,
  required:['name','indications','steps'],
  properties:{
    name:{type:'string',maxLength:120},
    indications:{type:'string',maxLength:260},
    steps:{type:'array',minItems:4,maxItems:6,items:{type:'string',maxLength:160}},
  },
};
export const operativeTechniquesSchema={type:'array',minItems:1,maxItems:3,items:technique};
export const surgicalTeachingPolicy =
  'CHAPITRE 08 OBLIGATOIRE (sections[7]) : principales techniques chirurgicales pertinentes au sujet, avec leur nom exact, leurs indications conditionnelles selon gravité, stabilité, terrain et alternatives, puis leurs principales étapes opératoires dans l ordre. '+
  'Le champ RACINE operative_techniques contient 1 à 3 objets {name,indications,steps}, en priorité DEUX techniques. steps comporte 4 à 6 étapes concrètes. Ne place pas ce champ dans les sections : l application rattache ces cartes au chapitre 08 après lecture du JSON. '+
  'Dans le chapitre 08, content conserve une explication complémentaire de 650 à 800 caractères ; les cartes structurées détaillent les gestes sans répéter tout le paragraphe. Nom précis, indications de 90 à 160 caractères et étapes de 40 à 90 caractères quand cela suffit. '+
  'Distingue une technique de première intention, une alternative et un geste de sauvetage ; ne présente pas une alternative comme systématique. Pas de procédure hors sujet ni de décision future du patient. Pas de lien vidéo inventé : les liens sont ajoutés par l application.';
export function hasSurgicalTechniques(fiche:any):boolean {
  return Array.isArray(fiche?.sections?.[7]?.operative_techniques) && fiche.sections[7].operative_techniques.length>0;
}
export function addSurgicalTechniques(fiche:any,techniques:unknown):any {
  // Add the cards only: preserve every existing chapter, key and paragraph.
  const sections=(fiche.sections||[]).map((s:any,i:number)=>i===7?{...s,operative_techniques:techniques}:s);
  return {...fiche,sections};
}
