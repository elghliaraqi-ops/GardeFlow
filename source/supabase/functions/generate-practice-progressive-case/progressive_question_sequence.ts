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
 return 'CONTRAT JSON OBLIGATOIRE (objet racine uniquement): '+
  '{"qcms":[{"axis":"'+steps[0]+
  '","question":"Question contextualisée au patient",'+
  '"options":["Proposition A","Proposition B","Proposition C","Proposition D"],'+
  '"correct_index":0,"correction":"Justification médicale détaillée",'+
  '"topic":"symptome","references":[{"url":"URL réelle autorisée"}],'+
  '"image_search_query":""}, ... EXACTEMENT cinq objets]}.'+
  ' Ne pas inclure les points de suspension littéraux dans la réponse. '+
  'Chaque objet doit comporter EXACTEMENT les champs axis, question, options, '+
  'correct_index, correction, topic, references, image_search_query. '+
  'Les axis dans ce lot doivent être STRICTEMENT dans cet ordre : '+
  steps.map((a,i)=>(batch*5+i+1)+':'+a).join(' → ')+'. '+
  'Le champ axis décrit la nature de la question, pas une simple étiquette : '+
  'respecte réellement son contenu, le niveau de révélation des résultats et la chronologie.';
}
