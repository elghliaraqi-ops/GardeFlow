import {
  confirmedObservations,
  unansweredWarnings,
  factualDraft,
  type QuestionFact,
} from './report_contract.ts';

function check(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}
const questions: QuestionFact[] = [
  {id: 'q1', kind: 'qcu', title: 'Fracture du plancher orbitaire', options: []},
  {id: 'q2', kind: 'qcm', title: 'Signes radiologiques maxillo-faciaux',
   options: ['Hémosinus', 'Hernie graisseuse', 'Emphysème']},
  {id: 'q3', kind: 'texte', title: 'Déplacement de la fracture', options: []},
  {id: 'q4', kind: 'qcu', title: 'Intégrité paroi médiale', options: []},
  {id: 'q5', kind: 'qcu', title: 'Plancher du sinus maxillaire', options: []},
];
Deno.test('positive, negative, selected QCM and text observations are preserved', () => {
  const obs = confirmedObservations(questions, {
    q1: {status: 'observed', value: 'oui', selected: [], notes: 'à droite'},
    q2: {status: 'observed', selected: ['Hémosinus'], notes: ''},
    q3: {status: 'observed', value: '3 mm en inférieur', notes: ''},
    q4: {status: 'observed', value: 'non', notes: ''},
    q5: {status: 'unanswered', notes: ''},
  });
  check(obs[0].status === 'présent' && obs[0].details.includes('droite'),
    'Explicit present sign should be retained with laterality');
  check(obs[1].details.includes('Hémosinus'), 'Selected sign must remain');
  check(!obs[1].details.includes('Hernie graisseuse'),
    'Unselected QCM options must never be described as absent or present');
  check(obs[1].details.includes('statut inconnu'), 'Unknown options must be labelled');
  check(obs[2].details.includes('3 mm'), 'Free measurement must be unchanged');
  check(obs[3].status === 'absent', 'Explicit negative must remain negative');
  check(obs[4].status === 'non_renseigne', 'Missing is not a normal finding');
  const draft = factualDraft({
    indication: 'Traumatisme orbitaire',
    technique: 'Scanner sans injection',
  }, obs);
  check(draft.results.includes('3 mm'), 'Fallback draft should preserve size');
  check(!draft.results.includes('Plancher du sinus maxillaire'),
    'Unanswered questions must not become normal findings');
  check(draft.conclusion.includes('à rédiger'),
    'A fallback draft must not fabricate a diagnosis');
});
Deno.test('explicitly absent QCM means only offered signs were checked', () => {
  const obs = confirmedObservations(questions.slice(1, 2), {
    q2: {status: 'absent', selected: [], notes: ''},
  });
  check(obs[0].status === 'absent', 'Explicit QCM absence must be preserved');
  check(obs[0].details.includes('Aucun des signes proposés'),
    'Do not turn this into broad normal imaging');
});
Deno.test('uncertain and not evaluable signs are flagged', () => {
  const obs = confirmedObservations(questions.slice(0, 2), {
    q1: {status: 'not_evaluable', notes: ''},
    q2: {status: 'uncertain', notes: 'artéfact de mouvement'},
  });
  check(unansweredWarnings(obs).length === 2, 'Both warning classes expected');
  const draft = factualDraft({indication: 'Traumatisme', technique: ''}, obs);
  check(draft.results.includes('non évaluable') &&
    draft.results.includes('incertain'), 'Uncertain statuses must not be normalized');
  check(draft.technique === 'Protocole non renseigné.',
    'Do not invent an acquisition technique');
});

Deno.test('Groq outage fallback uses medical prose rather than machine statuses', () => {
  const obs = confirmedObservations(questions, {
    q1: {status:'observed', value:'non'},
    q2: {status:'observed', selected:['Hémosinus']},
    q3: {status:'observed',value:'Décalage osseux inférieur de 4 mm.'},
    q4: {status:'uncertain',notes:'Artéfacts de mouvement'},
    q5: {status:'not_evaluable',notes:'Champ osseux incomplet'},
  });
  const draft = factualDraft({
    indication:'Traumatisme orbitaire',technique:'TDM sans injection',
  },obs);
  check(!/:\s*(absent|présent|oui|non)\b/i.test(draft.results),
    'Mechanical statuses forbidden in the final clinical report');
  check(draft.results.includes('Absence de fracture'),
    'Negative verified finding uses idiomatic radiology language');
  check(draft.results.includes('Hémosinus'), 'QCM selected finding preserved');
  check(draft.results.includes('4 mm'), 'Free measurement preserved');
  check(draft.results.includes('non évaluable') &&
    draft.results.includes('incertain'), 'Limitations must remain visible');
});
