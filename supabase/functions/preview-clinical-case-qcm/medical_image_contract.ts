/**
 * Shared QCM medical-image contract for ALL Groq QCM generators.
 * This is a JSON input/output agreement, not an independent medical reviewer.
 * URL/pixel storage is intentionally forbidden.
 */
export const medicalImageSchema={
  type:'object',additionalProperties:false,
  required:['query','modality','purpose','image_type','anatomy','plane','required_features','excluded_features'],
  properties:{
    query:{type:'string'}, modality:{type:'string'},purpose:{type:'string'},
    image_type:{type:'string',enum:['none','anatomical_diagram','radiology_scan','operative_diagram','clinical_photo']},
    anatomy:{type:'string'},
    plane:{type:'string',enum:['axial','sagittal','coronal','multiplanar','not_applicable']},
    required_features:{type:'array',items:{type:'string'}},
    excluded_features:{type:'array',items:{type:'string'}},
  },
} as const;
export const medicalImagePrompt=[
  'CONTRAT JSON IMAGES OBLIGATOIRE dans chaque QCM: fournir image_request comme objet avec TOUS les champs EXACTS '+Object.keys(medicalImageSchema.properties).join(', ')+'.',
  'Le JSON du prompt et le JSON Schema emploient le même nom image_request et exactement les mêmes champs; aucun URL, aucune miniature ni base64.',
  'image_type=none et query="" si le sujet ne nécessite pas d’image; mettre alors les autres champs texte à "", plane=not_applicable et les deux tableaux à [].',
  'Sinon query est une recherche en ANGLAIS très spécifique (organe, type d’image, coupe, signe, anatomie); modality désigne IRM T2, TDM, échographie, radiographie, ECG, schéma, etc.; purpose décrit exactement l’illustration pédagogique souhaitée.',
  'image_type=anatomical_diagram uniquement pour schémas anatomiques (pas de livre, rapport ni scanner); radiology_scan uniquement pour vrai examen de la modalité et du plan demandés; operative_diagram pour gestes opératoires; clinical_photo pour photos cliniques pertinentes.',
  'anatomy nomme l’organe central et plane vaut axial/sagittal/coronal/multiplanar/not_applicable; required_features liste les signes indispensables et excluded_features les artefacts et sujets interdits.',
  'TOUJOURS exclure couvertures de livres et de rapports, publicités, captures d’articles, diagrammes statistiques, organes non concernés, fausses IRM et images sans rapport.',
  'Exemple rectum : image_type=anatomical_diagram, anatomy=rectum mesorectum, query=rectum mesorectum sphincters sagittal labeled anatomy illustration, required_features=[rectum,mesorectum,sphincters], excluded_features=[book cover,prostate screening,report cover].',
  'Exemple sémiologie rectale : image_type=radiology_scan, modality=IRM T2, plane=axial, query=rectal cancer T2 axial pelvic MRI extramural invasion.',
  'Ne jamais inventer une image ou affirmer qu’un aperçu représente le patient fictif.',
].join('\n');
export const emptyMedicalImageRequest={
  query:'',modality:'',purpose:'',image_type:'none',anatomy:'',
  plane:'not_applicable',required_features:[],excluded_features:[],
};
export function normalizeMedicalImageRequest(raw:any, fallback='') {
  const x=raw&&typeof raw==='object'&&!Array.isArray(raw)?raw:{};
  const query=String(x.query??fallback).trim().slice(0,260);
  const kind=['none','anatomical_diagram','radiology_scan','operative_diagram','clinical_photo'].includes(x.image_type)
    ?x.image_type:(query?'radiology_scan':'none');
  if(!query||kind==='none')return {...emptyMedicalImageRequest};
  return {
    query, modality:String(x.modality??'').slice(0,80),
    purpose:String(x.purpose??'').slice(0,230),
    image_type:kind,anatomy:String(x.anatomy??'').slice(0,120),
    plane:['axial','sagittal','coronal','multiplanar','not_applicable'].includes(x.plane)
      ?x.plane:'not_applicable',
    required_features:Array.isArray(x.required_features)?x.required_features.slice(0,5).map((z:any)=>String(z).slice(0,70)):[],
    excluded_features:Array.isArray(x.excluded_features)?x.excluded_features.slice(0,8).map((z:any)=>String(z).slice(0,70)):[],
  };
}
export function medicalImageCorrectionSuffix(raw:any,fallback='') {
  const request=normalizeMedicalImageRequest(raw,fallback);
  return request.image_type==='none'?'':'\n\n§IMAGE_SPEC§\n'+JSON.stringify(request);
}
