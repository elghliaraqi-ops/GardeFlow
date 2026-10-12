// A deterministic generation plan, not a second model/reviewer request.
export function courseBatchPlan(offset: number, count: number): string {
  const objectives = [
    'anatomie topographique', 'physiopathologie', 'interrogatoire et terrain',
    'examen clinique', 'signes de gravité', 'diagnostics différentiels',
    'choix initial de l’imagerie', 'sémiologie radiologique',
    'limites des examens biologiques', 'classification et son interprétation',
    'réanimation initiale', 'traitement médical et contre-indications',
    'indication et délai de l’intervention', 'choix de la voie d’abord',
    'geste opératoire et alternatives', 'adaptation aux constatations opératoires',
    'surveillance postopératoire', 'diagnostic d’une complication',
    'traitement d’une complication selon la stabilité', 'prévention et suivi',
  ];
  return objectives.slice(offset, offset + count)
    .map((objective, i) => `${offset + i + 1}. ${objective}`).join('\n');
}

function fingerprint(statement: unknown): string {
  return String(statement ?? '').normalize('NFKD').toLocaleLowerCase('fr')
    .replace(/\p{M}/gu, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

export function assertNewStatements(previous: any[], generated: any[]): void {
  const seen = new Set(previous.map(q => fingerprint(q.statement)));
  for (const question of generated) {
    const key = fingerprint(question.statement);
    if (!key || seen.has(key)) throw new Error('duplicate_question_statement');
    seen.add(key);
  }
}
