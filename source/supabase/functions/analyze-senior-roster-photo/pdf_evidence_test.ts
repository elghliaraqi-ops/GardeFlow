import { validateSeniorPdfEvidence } from './pdf_evidence.ts';

const assert = (ok: boolean, message: string) => {
  if (!ok) throw new Error(message);
};
const resource = {
  id: 'selected-senior-pdf',
  updated_at: '2026-10-08T10:00:00+00:00',
  mime_type: 'application/pdf',
  display_name: 'astreintes.pdf',
};
const evidence = {
  extractor: 'pdfrx-2.6.5',
  sourceResourceId: 'selected-senior-pdf',
  sourceUpdatedAt: '2026-10-08T10:00:00Z',
  pageCount: 2,
  pagesRead: 2,
  extractedFragments: 1,
  structuredText: '=== PAGE 1 / 2 ===\nx=10.0 y=45.2 | Dr Bensalem\n',
  truncated: false,
};

Deno.test('selected PDF pdfrx evidence is accepted', () => {
  const result = validateSeniorPdfEvidence(evidence, resource);
  assert(result.ok && result.evidence?.text.includes('Dr Bensalem') === true,
    'valid geometric extraction must be retained as a hint');
});

Deno.test('no evidence preserves PDF vision fallback', () => {
  const result = validateSeniorPdfEvidence(undefined, resource);
  assert(result.ok && result.evidence === null,
    'legacy clients and image-only PDFs must continue');
});

Deno.test('reject another PDF, another version, and images', () => {
  for (const modified of [
    { ...evidence, sourceResourceId: 'different-pdf' },
    { ...evidence, sourceUpdatedAt: '2026-10-07T10:00:00Z' },
    { ...evidence, sourceUpdatedAt: 'invalid' },
  ]) {
    const result = validateSeniorPdfEvidence(modified, resource);
    assert(!result.ok, 'pdfrx evidence from another resource must be rejected');
  }
  assert(!validateSeniorPdfEvidence(evidence, {
    ...resource,
    mime_type: 'image/jpeg',
    display_name: 'photo.jpg',
  }).ok, 'pdfrx PDF evidence must never be used for photos');
});

Deno.test('reject oversized, forged or malformed PDF metadata', () => {
  const cases: unknown[] = [
    { ...evidence, structuredText: 'a'.repeat(36001) },
    { ...evidence, extractedFragments: 1, structuredText: 'hallucinated name' },
    { ...evidence, pageCount: 0 },
    { ...evidence, pagesRead: 40 },
    { ...evidence, extractor: 'other-engine' },
    { ...evidence, truncated: 'false' },
  ];
  for (const entry of cases) {
    assert(!validateSeniorPdfEvidence(entry, resource).ok,
      'malformed or suspicious metadata must be rejected');
  }
});
