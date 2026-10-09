/**
 * One clinical case, 10 QCMs, always the same progressive decision pathway.
 * The UI unlocks them in groups 2/3/3/2 across four stages.
 * This module is deterministic, with no LLM calls or patient information.
 */
export const progressiveAxes=[
 'symptomes','examen_clinique',
 'hypotheses_diagnostiques','classification_gravite','examens_complementaires',
 'interpretation_diagnostic','decision_therapeutique','conduite_a_tenir',
 'surveillance_revaluation','complications_suivi'
] as const;
export type ProgressiveAxis=typeof progressiveAxes[number];
export const progressiveStages=[0,0,1,1,1,2,2,2,3,3] as const;
export function expectedProgressiveAxes(batch:0|1):readonly ProgressiveAxis[]{
 return progressiveAxes.slice(batch*5,batch*5+5);
}
export function validateProgressiveAxisSequence(input:unknown,batch:0|1):boolean{
 if(!Array.isArray(input)||input.length!==5)return false;
 return input.every((item,i)=>item!==null&&typeof item==='object'&&
  (item as {axis?:unknown}).axis===progressiveAxes[batch*5+i]);
}
export function progressiveJsonContract(batch:0|1):string{
 const steps=expectedProgressiveAxes(batch);
 const topics=['symptome','examen','synthese','synthese','examen',
  'synthese','prise_en_charge','prise_en_charge','prise_en_charge','orientation'];
 const sample={
  qcms:steps.map((axis,i)=>({
   axis,question:'REMPLACER par une question sur '+axis+' du même patient',
   options:['Choix clinique A','Choix clinique B','Choix clinique C','Choix clinique D'],
   correct_index:0,
   correction:'REMPLACER par explication précise conforme aux références vérifiées.',
   topic:topics[batch*5+i],
   references:[{url:'REMPLACER_PAR_URL_EXACTE_DU_CATALOGUE'}],
   image_search_query:''
  }))
 };
 return 'CONTRAT JSON OBLIGATOIRE : objet racine avec exactement la clé qcms '+
  'et EXACTEMENT cinq objets. Voici UN MODÈLE JSON SYNTAXIQUEMENT VALIDE '+
  'avec 5 questions, dont tous les textes, réponses et références PLACEHOLDERS '+
  'doivent être remplacés par les faits du dossier et les liens exacts vérifiés. '+
  'Ne reprends JAMAIS les placeholders ni les options génériques. '+
  'MODELE_JSON_DEBUT\n'+JSON.stringify(sample)+'\nMODELE_JSON_FIN\n'+
  'Chaque QCM comporte axis, question, options (4 chaînes), correct_index '+
  '(entier 0, 1, 2 ou 3), correction médicale détaillée, topic autorisé, '+
  'references (1 à 3 objets {url} du catalogue uniquement), image_search_query. '+
  'L’ordre clinique est ABSOLUMENT imposé : '+
  steps.map((axis,i)=>(batch*5+i+1)+':'+axis).join(' → ')+'. '+
  'Chaque question doit correspondre réellement à son axis, aux données du patient '+
  'et aux informations révélées à cette étape. Pas de Markdown, texte ni commentaire hors JSON.';
}
