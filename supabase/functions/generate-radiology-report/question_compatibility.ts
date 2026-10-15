/**
 * Clients published before the systematic reporting release reject any plan
 * containing more than 12 questions, even when the server returns HTTP 200.
 * Keep legacy browsers functional; modern builds explicitly negotiate capacity.
 */
export function clientQuestionCapacity(raw: unknown): number {
  const value = typeof raw === 'number' ? raw : NaN;
  return Number.isInteger(value) && value >= 5
    ? Math.min(value, 48) : 12;
}
type PlanQuestion = {
  id: string;
  title: string;
  section?: string;
};
export function compatibleQuestionSet<T extends PlanQuestion>(
  questions: T[],
  capacity: number,
  indication = '',
  comparative = false,
): { questions: T[]; available: number; truncated: boolean } {
  const available = questions.length;
  if (available <= capacity) return {
    questions, available, truncated: false,
  };
  const chosen = new Set<number>();
  // Comparison and especially the olfactory skull base are essential
  // if named in the clinical indication, even on the legacy UI.
  if (comparative) {
    const idx = questions.findIndex(q => q.section === 'Comparaison');
    if (idx >= 0) chosen.add(idx);
  }
  const norm = indication.normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '').toLowerCase();
  if (/(anosm|olfact|base du crane|cribl|ethmoid)/.test(norm)) {
    for (let i = 0; i < questions.length; i++) {
      if (/(cribl|toit ethmoidal)/i.test(
          questions[i].title.normalize('NFD')
            .replace(/[\u0300-\u036f]/g, ''))) {
        chosen.add(i);
        break;
      }
    }
  }
  // A legacy 12-question browser must still examine ALL THREE TAP regions.
  // Otherwise the first 8 thoracic questions consume the budget and pelvis
  // silently vanishes. Round-robin selection preserves anatomical balance;
  // the final returned questions are resorted into reporting order.
  const tapGroups = ['Thorax', 'Abdomen', 'Pelvis'].map(region =>
    questions.flatMap((q, i) =>
      q.section?.startsWith(region + ' · ') ? [i] : []));
  if (capacity >= 3 && tapGroups.every(group => group.length > 0)) {
    for (let level = 0; chosen.size < capacity &&
        tapGroups.some(group => group.length > level); level++) {
      for (const group of tapGroups) {
        if (chosen.size < capacity && group[level] !== undefined)
          chosen.add(group[level]);
      }
    }
  }
  for (let i = 0; i < questions.length && chosen.size < capacity; i++) {
    chosen.add(i);
  }
  const subset = [...chosen].sort((a,b) => a - b).slice(0, capacity)
    .map(i => questions[i]);
  return {
    questions: subset.map((q,i) => ({...q, id: 'q' + (i + 1)} as T)),
    available,
    truncated: true,
  };
}
