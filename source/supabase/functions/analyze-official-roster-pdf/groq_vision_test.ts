import { GROQ_MAX_IMAGES_PER_REQUEST, GroqRosterVision, expandCompactRoster, mergeChunkReads } from './groq_vision.ts';

function assert(ok: boolean, message: string): void {
  if (!ok) throw new Error(message);
}

Deno.test('Groq vision limits one image per request to reduce token pressure', () => {
  assert(GROQ_MAX_IMAGES_PER_REQUEST === 1,
    'A/B/C must request one PDF page per Groq call at free-tier token limits');
});

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

Deno.test('Compact R6 : mêmes identités complètes et créneaux, page liée au PDF officiel', () => {
  const result = expandCompactRoster({
    m: 10, y: 2026, scope: 'U', mode: 'M',
    start: '2026-10-01', end: '2026-10-31', q: 0.96, w: [],
    r: [
      ['2026-10-01', 'J', [['Taha', 'Meral', 'Taha Meral', 0.97]], [], 'ligne 1/J'],
      ['2026-10-01', 'N', [['Marwa', 'Oukkas', 'Marwa Oukkas', 0.98]],
        ['Marwa Oukkas'], 'ligne 1/N'],
    ],
  }, 2);
  assert(result.rows.length === 2, 'Both day and night must be kept');
  assert(result.rows[0].shift === 'urg-jour', 'Day must be Urgences only');
  assert(result.rows[1].shift === 'urg-nuit', 'Night must be Urgences only');
  assert(result.rows[0].doctors[0].first_name === 'Taha', 'First name unchanged');
  assert(result.rows[1].doctors[0].full_name === 'Marwa Oukkas', 'Full name unchanged');
  assert(result.rows[1].red_names[0] === 'Marwa Oukkas', 'Red disciplinary mark preserved');
  assert(result.rows.every((r: any) => r.page_number === 2), 'Server PDF page bound');
});

Deno.test('Compact R6 : un planning Service reste hors périmètre', () => {
  const result = expandCompactRoster({
    m: 10, y: 2026, scope: 'S', mode: 'M',
    start: '2026-10-01', end: '2026-10-31', q: 0.99, w: [],
    r: [['2026-10-01', 'J', [], [], 'zone jour']],
  }, 1);
  assert(result.document_scope === 'non_urgences', 'Service must not become Urgences');
});

Deno.test('Compact R6 : refus d’un médecin tronqué, d’une zone absente ou d’un créneau Service', () => {
  const raw = (r: any) => ({
    m: null, y: null, scope: 'U', mode: 'R',
    start: '2026-10-01', end: '2026-10-01', q: 0.98, w: [], r: [r],
  });
  for (const row of [
    ['2026-10-01', 'J', [['Taha', 'Meral', 'Taha Meral']], [], 'zone'],
    ['2026-10-01', 'J', [['Taha', 'Meral', 'Taha Meral', 0.99]], [], ''],
    ['2026-10-01', 'service-jour', [], [], 'zone'],
  ]) {
    let rejected = false;
    try { expandCompactRoster(raw(row), 1); } catch (_) { rejected = true; }
    assert(rejected, 'Incomplete or out-of-scope content must fail closed');
  }
});

Deno.test('Compact R6 : aucun numéro de promotion ou compte n’est inféré', () => {
  const result = expandCompactRoster({
    m: null, y: null, scope: 'U', mode: 'R',
    start: '2026-10-01', end: '2026-10-01', q: 0.98, w: [],
    r: [['2026-10-01', 'J', [['Lina', 'Bennani', 'Lina Bennani', 0.97]], [], 'ligne 1']],
  }, 1);
  assert(result.rows[0].doctors[0].full_name === 'Lina Bennani',
    'Unknown doctors must be preserved');
  assert(!('owner_id' in result.rows[0]), 'No automatic identity link');
});
