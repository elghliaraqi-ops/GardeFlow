import {
  GroqRosterVision, mergeChunkReads,
  GROQ_MAX_IMAGES_PER_REQUEST, GROQ_MAX_COMPLETION_TOKENS,
  parseGroqRetryAfter, GroqRateLimitError,
} from './groq_vision.ts';

function assert(ok: boolean, message: string): void {
  if (!ok) throw new Error(message);
}

function samplePdf(): Uint8Array {
  // PDF généré en mémoire pour tester le moteur PDFium (pas d'API Groq).
  const stream = 'BT /F1 18 Tf 50 740 Td (URGENCES OCTOBRE 2026) Tj ET\n';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ' +
      '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ' + stream.length + ' >>\nstream\n' + stream + 'endstream',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (let i = 0; i < objects.length; i++) {
    offsets.push(pdf.length);
    pdf += (i + 1) + ' 0 obj\n' + objects[i] + '\nendobj\n';
  }
  const xref = pdf.length;
  pdf += 'xref\n0 ' + (objects.length + 1) + '\n';
  pdf += '0000000000 65535 f \n';
  for (const position of offsets.slice(1)) {
    pdf += String(position).padStart(10, '0') + ' 00000 n \n';
  }
  pdf += 'trailer\n<< /Size ' + (objects.length + 1) +
    ' /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF\n';
  return new TextEncoder().encode(pdf);
}

Deno.test('Groq PDF preprocessor renders the official source, not client pictures', async () => {
  const rendered = await GroqRosterVision.fromPdf(samplePdf());
  assert(rendered.pageCount === 1, 'One PDF page must produce exactly one Groq image');
});

Deno.test('Multi-page readings include all pages without dropping coverage', () => {
  const base = {
    month: null, year: null, document_scope: 'urgences',
    coverage_mode: 'explicit_range', confidence: 0.96,
    warnings: [] as string[],
  };
  const merged = mergeChunkReads([
    { ...base, coverage_start: '2026-10-01', coverage_end: '2026-10-01',
      rows: [{ date: '2026-10-01', shift: 'urg-jour', doctors: [],
        red_names: [], page_number: 1, zone: 'p1' }] },
    { ...base, coverage_start: '2026-10-02', coverage_end: '2026-10-02',
      confidence: 0.93,
      rows: [{ date: '2026-10-02', shift: 'urg-nuit', doctors: [],
        red_names: [], page_number: 6, zone: 'p6' }] },
  ]);
  assert(merged.rows.length === 2, 'Both disjoint chunks must survive');
  assert(merged.coverage_start === '2026-10-01', 'First date must survive');
  assert(merged.coverage_end === '2026-10-02', 'Last date must survive');
  assert(merged.confidence === 0.93, 'Use the least certain chunk');
  assert(merged.document_scope === 'urgences', 'Urgences scope retained');
});

Deno.test('Any mixed/Service page makes whole extraction fail closed', () => {
  const base = {
    month: null, year: null, coverage_mode: 'explicit_range',
    confidence: 0.98, warnings: [] as string[],
    rows: [{ date: '2026-10-01', shift: 'urg-jour', doctors: [],
      red_names: [], page_number: 1, zone: 'p1' }],
  };
  const merged = mergeChunkReads([
    { ...base, document_scope: 'urgences' },
    { ...base, document_scope: 'non_urgences' },
  ]);
  assert(merged.document_scope === 'mixed_or_uncertain',
    'Mixed scope must never be accepted as Urgences');
});

Deno.test('Groq R6 requests fit the free-tier per-request token budget', () => {
  assert(GROQ_MAX_IMAGES_PER_REQUEST === 1,
    'Only one 2048-token image must be sent per request');
  assert(GROQ_MAX_COMPLETION_TOKENS <= 4096,
    'Completion token reservation must remain bounded');
  assert(GROQ_MAX_IMAGES_PER_REQUEST * 2048 + GROQ_MAX_COMPLETION_TOKENS < 8000,
    'Leave room for verification instructions under the nominal 8K TPM budget');
});

Deno.test('Groq rate-limit retry delay is validated and clamped', () => {
  assert(parseGroqRetryAfter('6') === 6, 'Seconds parsed');
  assert(parseGroqRetryAfter('0.5') === 1, 'Fraction rounds upward');
  assert(parseGroqRetryAfter(null) === null, 'Missing header is unknown');
  assert(parseGroqRetryAfter('bad') === null, 'Invalid header ignored');
  assert(parseGroqRetryAfter('10000') === 3600, 'Long waits capped');
  const rateLimit = new GroqRateLimitError(32);
  assert(rateLimit.message === 'groq_rate_limited', 'Stable API error');
  assert(rateLimit.retryAfterSeconds === 32, 'Wait duration survives');
});
