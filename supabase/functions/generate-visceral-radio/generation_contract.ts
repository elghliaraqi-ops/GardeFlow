/**
 * Single source of truth for Groq output contracts in Practice Viscéral × Radio.
 * The prompt instructions and the JSON Schema are produced together.
 * Strict JSON formatting is not a second medical reviewer.
 */
type JsonSchema = Record<string, unknown>;
export type GenerationMode = 'fiche' | 'course_qcms' | 'case' | 'case_qcms';
export type GenerationContract = {
  mode: GenerationMode;
  name: string;
  schema: JsonSchema;
  outputInstructions: string;
  requestedCount: number | null;
};

const stringType = { type: 'string' };
const stringList = { type: 'array', items: stringType };
function fixedArray(items: JsonSchema, count: number): JsonSchema {
  return { type: 'array', items, minItems: count, maxItems: count };
}
function object(properties: Record<string, JsonSchema>): JsonSchema {
  return {
    type: 'object',
    properties,
    required: Object.keys(properties),
    additionalProperties: false,
  };
}

export const imageRequestSchema = object({
  query: stringType,
  modality: stringType,
  purpose: stringType,
  image_type: { type: 'string', enum: ['anatomical_diagram', 'radiology_scan', 'operative_diagram', 'clinical_photo'] },
  anatomy: stringType,
  plane: { type: 'string', enum: ['axial', 'sagittal', 'coronal', 'multiplanar', 'not_applicable'] },
  required_features: stringList,
  excluded_features: stringList,
  fallback_queries: stringList,
  preferred_sources: stringList,
  allow_article_figures: {type:'boolean'},
  allow_source_illustrations: {type:'boolean'},
  allow_open_graph_preview: {type:'boolean'},
  allow_page_preview: {type:'boolean'},
});
export const sectionSchema = object({
  key: stringType,
  title: stringType,
  content: {type:'string',minLength:650,maxLength:1800},
  key_points: {type:'array',minItems:4,maxItems:6,items:{type:'string',maxLength:240}},
  image_requests: { type: 'array', maxItems: 1, items: imageRequestSchema },
});
export const ficheSchema = object({
  title: stringType,
  summary: stringType,
  sections: fixedArray(sectionSchema, 10),
  study_core: {type:'array',minItems:10,maxItems:20,items:{type:'string',maxLength:240}},
  references: stringList,
});
export const caseStageSchema = object({
  phase: { type: 'integer', enum: [1, 2, 3, 4] },
  title: stringType,
  narrative: stringType,
  clinical_findings: stringType,
  imaging_findings: stringType,
  decisions: stringType,
  image_requests: { type: 'array', maxItems: 1, items: imageRequestSchema },
});
export const caseSchema = object({
  title: stringType,
  patient: stringType,
  difficulty: { type: 'string', enum: ['simple', 'intermediaire', 'complexe'] },
  recommended_qcms: { type: 'integer', enum: [10, 15, 20] },
  stages: fixedArray(caseStageSchema, 4),
  final_diagnosis: stringType,
  learning_points: stringList,
  references: stringList,
});
export const questionOptionSchema = object({
  key: { type: 'string', enum: ['A', 'B', 'C', 'D', 'E'] },
  text: stringType,
  correct: { type: 'boolean' },
  explanation: stringType,
});

export function questionSchema(allowedPhases: number[],courseKeys:string[]=[]): JsonSchema {
  return object({
    phase: { type: 'integer', enum: [...new Set(allowedPhases)] },
    category: {
      type: 'string',
      enum: ['chirurgie', 'radiologie', 'technique_operatoire'],
    },
    statement: stringType,
    course_section_key: courseKeys.length?{type:'string',enum:courseKeys}:stringType,
    teaching_point: {type:'string',minLength:40,maxLength:300},
    options: fixedArray(questionOptionSchema, 5),
    global_explanation: stringType,
    reference: stringType,
    image_requests: { type: 'array', maxItems: 1, items: imageRequestSchema },
  });
}
export function qcmSchema(count: number, phases: number[],courseKeys:string[]=[]): JsonSchema {
  if (count !== 5 && count !== 10) {
    throw new Error('unsupported_qcm_batch_size');
  }
  if (!phases.length || phases.some((p) => ![1, 2, 3, 4].includes(p))) {
    throw new Error('invalid_qcm_phases');
  }
  return object({ questions: fixedArray(questionSchema(phases,courseKeys), count) });
}

const prescriptions: Record<GenerationMode, string> = {
  fiche:
    'Cours de RÉSIDANAT, pas résumé d externat : EXACTEMENT 10 sections. Chaque content contient 650 à 1800 caractères, vise 900 à 1200 caractères avec paragraphes et sous-titres. Chaque section enseigne 4 à 6 key_points précis et expliqués (au plus 240 caractères chacun), non de simples intitulés. Définition, rapports anatomiques/espaces/nerfs, physiopathologie, clinique et gravité, biologie et limites, protocole imagerie/sémiologie/classifications, indications et alternatives, étapes opératoires/repères/pièges, complications et surveillance, synthèse décisionnelle. Expliquer critères, contexte, exceptions et implications chirurgicales. study_core contient 10 à 20 faits enseignés, jamais de simples objectifs. La fiche doit permettre de résoudre les futurs QCM sans notion absente du cours.',
  course_qcms:
    'Les QCM de niveau résidanat portent EXCLUSIVEMENT sur les faits enseignés dans les chapitres transmis. course_section_key est la clé du chapitre correspondant et teaching_point rappelle le fait expliqué dans ce chapitre. Chaque proposition A–E possède text, correct et explanation. Les distracteurs sont des erreurs ou inversions des faits enseignés, jamais des notions nouvelles. Au moins une réponse correcte par question. Expliquer les cinq propositions et donner global_explanation. category vaut chirurgie, radiologie ou technique_operatoire. phase vaut toujours 1.',
  case:
    'Créer un SEUL cas clinique fictif strictement lié au sujet de la fiche, avec EXACTEMENT quatre phases 1, 2, 3, 4 chronologiques : admission, explorations et imagerie, traitement/chirurgie, suites et suivi. Ne pas révéler le diagnostic dans la première phase. difficulty vaut simple/intermediaire/complexe et recommended_qcms vaut 10/15/20, en cohérence avec la difficulté.',
  case_qcms:
    'Chaque QCM porte exclusivement sur le même patient du cas transmis et les notions expliquées dans le cours. course_section_key rattache la notion au chapitre et teaching_point explique le raisonnement de niveau résidanat. Questions chronologiques : clinique puis examens/radiologie puis diagnostic/traitement puis chirurgie/suivi. Chaque proposition A–E comporte text, correct et explanation, avec une ou plusieurs bonnes réponses, global_explanation et référence si disponible. Ne jamais divulguer les résultats futurs.',
};

export function generationContract(
  mode: GenerationMode,
  options: { count?: number; phases?: number[]; courseKeys?:string[] } = {},
): GenerationContract {
  const isQcm = mode === 'course_qcms' || mode === 'case_qcms';
  const count = isQcm ? (options.count ?? 10) : null;
  const phases = mode === 'course_qcms' ? [1] : (options.phases ?? [1, 2, 3, 4]);
  const schema = mode === 'fiche'
    ? ficheSchema
    : mode === 'case'
    ? caseSchema
    : qcmSchema(count as number, phases,options.courseKeys??[]);
  const rootFields = Object.keys(schema.properties as Record<string, unknown>);
  const instruction = [
    'CONTRAT GROQ UNIQUE — LE TEXTE ET JSON_SCHEMA SONT ALIGNÉS.',
    'Répondre UNIQUEMENT par un objet JSON conforme au JSON Schema imposé par l’API.',
    'Champs racine EXACTS : ' + rootFields.join(', ') + '.',
    isQcm
      ? 'Retourner EXACTEMENT ' + count + ' questions dans questions, chaque question avec EXACTEMENT cinq options A, B, C, D et E dans cet ordre.'
      : mode === 'fiche'
      ? 'Retourner EXACTEMENT 10 objets sections dans sections.'
      : 'Retourner EXACTEMENT 4 objets stages dans stages, dans l’ordre phase 1, 2, 3, 4.',
    mode === 'course_qcms'
      ? 'Phase autorisée: 1.'
      : mode === 'case_qcms'
      ? 'Phases autorisées: ' + [...new Set(phases)].join(', ') + '.'
      : '',
    prescriptions[mode],
    'CONTRAT DES IMAGES OBLIGATOIRE POUR CHAQUE image_requests (dans sections, stages ou questions) : les champs query, modality, purpose, image_type, anatomy, plane, required_features, excluded_features, fallback_queries, preferred_sources, allow_article_figures, allow_source_illustrations, allow_open_graph_preview et allow_page_preview sont tous requis. Ne jamais ajouter d’URL d’image.',
    'Choisir image_type de façon clinique : anatomical_diagram uniquement pour les rapports anatomiques (schéma annoté; pas de radiographie ou ouvrage), radiology_scan pour une vraie coupe médicale (IRM/TDM/échographie) avec modalité, plan, séquence et signes attendus, operative_diagram pour les gestes chirurgicaux; clinical_photo uniquement si pertinent.',
    'query doit être une requête visuelle précise en anglais combinant organe + modalité/type + anomalie ou repères recherchés. required_features énumère 2 à 4 éléments réellement visibles et nécessaires; excluded_features proscrit couvertures de livres, publicités, graphiques statistiques, images d’un autre organe ou d’un autre examen. Les vraies figures d’articles sources médicaux sont AUTORISÉES.',
    'Exemple anatomie rectale : image_type=anatomical_diagram, anatomy=rectum mesorectum sphincter, query=rectum mesorectum levator ani labeled sagittal anatomy illustration, required_features=[rectum,mesorectum,levator ani], excluded_features=[book cover,prostate screening,annual report].',
    'Exemple stade T3/T4 rectal : image_type=radiology_scan, modality=IRM T2, plane=axial, anatomy=rectum, query=rectal cancer T2 axial pelvic MRI extramural invasion, required_features=[rectal tumor,T2 MRI], excluded_features=[book cover,non medical photo,wrong organ].',
    'fallback_queries : 2 à 4 alternatives courtes en anglais. preferred_sources : Europe PMC, PubMed Central, Radiopaedia, Eurorad, The Radiology Assistant selon le type de figure. allow_article_figures, allow_source_illustrations, allow_open_graph_preview et allow_page_preview = true pour les demandes pertinentes. La recherche peut proposer une carte article sourcée quand sa figure n’est pas directement utilisable.',
    'Les aperçus recherchés doivent illustrer fidèlement les signes et structures demandés, sans affirmer qu’ils viennent du patient fictif. Si aucun visuel fiable n’est approprié, image_requests=[] plutôt qu’une proposition hors sujet.',
    'Tous les objets doivent renseigner chaque champ required du schéma, même si un tableau est vide.',
    'Ne créer aucune clé supplémentaire ni champ manquant, aucun Markdown, aucun texte hors JSON.',
  ].filter(Boolean).join('\n');
  return {
    mode,
    name: ({
      fiche: 'visceral_radio_fiche',
      course_qcms: 'visceral_radio_course_questions',
      case: 'visceral_radio_case',
      case_qcms: 'visceral_radio_progressive_questions',
    })[mode],
    schema,
    outputInstructions: instruction,
    requestedCount: count,
  };
}
