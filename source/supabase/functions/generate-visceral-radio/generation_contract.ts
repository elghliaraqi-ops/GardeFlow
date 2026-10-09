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
});
export const sectionSchema = object({
  key: stringType,
  title: stringType,
  content: stringType,
  key_points: stringList,
  image_requests: { type: 'array', items: imageRequestSchema },
});
export const ficheSchema = object({
  title: stringType,
  summary: stringType,
  sections: fixedArray(sectionSchema, 10),
  study_core: stringList,
  references: stringList,
});
export const caseStageSchema = object({
  phase: { type: 'integer', enum: [1, 2, 3, 4] },
  title: stringType,
  narrative: stringType,
  clinical_findings: stringType,
  imaging_findings: stringType,
  decisions: stringType,
  image_requests: { type: 'array', items: imageRequestSchema },
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

export function questionSchema(allowedPhases: number[]): JsonSchema {
  return object({
    phase: { type: 'integer', enum: [...new Set(allowedPhases)] },
    category: {
      type: 'string',
      enum: ['chirurgie', 'radiologie', 'technique_operatoire'],
    },
    statement: stringType,
    options: fixedArray(questionOptionSchema, 5),
    global_explanation: stringType,
    reference: stringType,
    image_requests: { type: 'array', items: imageRequestSchema },
  });
}
export function qcmSchema(count: number, phases: number[]): JsonSchema {
  if (count !== 5 && count !== 10) {
    throw new Error('unsupported_qcm_batch_size');
  }
  if (!phases.length || phases.some((p) => ![1, 2, 3, 4].includes(p))) {
    throw new Error('invalid_qcm_phases');
  }
  return object({ questions: fixedArray(questionSchema(phases), count) });
}

const prescriptions: Record<GenerationMode, string> = {
  fiche:
    'Produire une fiche unique en EXACTEMENT 10 sections substantielles couvrant définition, anatomie, physiopathologie, clinique, biologie, radiologie, traitements, techniques opératoires, complications et synthèse. Chaque section contient key, title, content, key_points et image_requests. Les images ne contiennent jamais d’URL.',
  course_qcms:
    'Les QCM portent EXCLUSIVEMENT sur la fiche transmise. Chaque proposition A–E possède text, correct et explanation. Au moins une réponse correcte par question. Expliquer les cinq propositions et donner global_explanation. category vaut chirurgie, radiologie ou technique_operatoire. phase vaut toujours 1. Références et images : ne jamais inventer de lien.',
  case:
    'Créer un SEUL cas clinique fictif strictement lié au sujet de la fiche, avec EXACTEMENT quatre phases 1, 2, 3, 4 chronologiques : admission, explorations et imagerie, traitement/chirurgie, suites et suivi. Ne pas révéler le diagnostic dans la première phase. difficulty vaut simple/intermediaire/complexe et recommended_qcms vaut 10/15/20, en cohérence avec la difficulté.',
  case_qcms:
    'Chaque QCM porte exclusivement sur le même patient du cas transmis. Questions chronologiques : clinique puis examens/radiologie puis diagnostic/traitement puis chirurgie/suivi. Chaque proposition A–E comporte text, correct et explanation, avec une ou plusieurs bonnes réponses, global_explanation et référence si disponible. Ne jamais divulguer les résultats futurs.',
};

export function generationContract(
  mode: GenerationMode,
  options: { count?: number; phases?: number[] } = {},
): GenerationContract {
  const isQcm = mode === 'course_qcms' || mode === 'case_qcms';
  const count = isQcm ? (options.count ?? 10) : null;
  const phases = mode === 'course_qcms' ? [1] : (options.phases ?? [1, 2, 3, 4]);
  const schema = mode === 'fiche'
    ? ficheSchema
    : mode === 'case'
    ? caseSchema
    : qcmSchema(count as number, phases);
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
