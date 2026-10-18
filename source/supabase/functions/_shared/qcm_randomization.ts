/** Randomize the display positions without changing which answers are true. */
export function shuffleSingleAnswer(
  options: string[], correctIndex: number, random: () => number = Math.random,
): { options: string[]; correctIndex: number } {
  if (options.length !== 4 || !Number.isInteger(correctIndex) ||
      correctIndex < 0 || correctIndex >= options.length) {
    throw new Error('invalid_single_answer_options');
  }
  const order = shuffledIndexes(options.length, random);
  return { options: order.map(index => options[index]), correctIndex: order.indexOf(correctIndex) };
}

/** Shuffle entire option objects and relabel keys A-E, keeping corrections attached. */
export function shuffleMultipleAnswer<T extends { key: string }>(
  options: T[], random: () => number = Math.random,
): T[] {
  if (options.length !== 5) throw new Error('invalid_multiple_answer_options');
  const order = shuffledIndexes(options.length, random);
  return order.map((index, displayIndex) => ({
    ...options[index], key: 'ABCDE'[displayIndex],
  }));
}

function shuffledIndexes(length: number, random: () => number): number[] {
  const result = Array.from({ length }, (_, i) => i);
  for (let i = result.length - 1; i > 0; i--) {
    const roll = random();
    if (!Number.isFinite(roll) || roll < 0 || roll >= 1) throw new Error('invalid_random_roll');
    const j = Math.floor(roll * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}
