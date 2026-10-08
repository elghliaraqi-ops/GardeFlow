/** Validated client-side pdfrx 2.6.5 text hints; original PDF remains canonical. */
export type SeniorPdfEvidence = {
  text: string;
  pageCount: number;
  pagesRead: number;
  extractedFragments: number;
  truncated: boolean;
};

export function validateSeniorPdfEvidence(
  input: unknown,
  resource: { id: string; updated_at: string; mime_type: string; display_name: string },
): { ok: true; evidence: SeniorPdfEvidence | null } |
   { ok: false; error: 'invalid_pdf_evidence' | 'pdf_evidence_source_mismatch' } {
  if (input === null || input === undefined) return { ok: true, evidence: null };
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { ok: false, error: 'invalid_pdf_evidence' };
  }
  const value = input as Record<string, unknown>;
  const isPdf = resource.mime_type.toLowerCase() === 'application/pdf' ||
    resource.display_name.toLowerCase().endsWith('.pdf');
  if (!isPdf || value.extractor !== 'pdfrx-2.6.5') {
    return { ok: false, error: 'invalid_pdf_evidence' };
  }
  const date = Date.parse(String(value.sourceUpdatedAt ?? ''));
  const resourceDate = Date.parse(resource.updated_at);
  if (value.sourceResourceId !== resource.id || !Number.isFinite(date) ||
      !Number.isFinite(resourceDate) || date !== resourceDate) {
    return { ok: false, error: 'pdf_evidence_source_mismatch' };
  }
  const pageCount = Number(value.pageCount);
  const pagesRead = Number(value.pagesRead);
  const fragments = Number(value.extractedFragments);
  const text = value.structuredText;
  if (!Number.isInteger(pageCount) || pageCount < 1 || pageCount > 500 ||
      !Number.isInteger(pagesRead) || pagesRead < 0 || pagesRead > 30 ||
      pagesRead > pageCount ||
      !Number.isInteger(fragments) || fragments < 0 || fragments > 100000 ||
      typeof text !== 'string' || text.length > 36000 ||
      typeof value.truncated !== 'boolean' ||
      (fragments > 0 && !/x=-?\d+(?:\.\d+)? y=-?\d+(?:\.\d+)? \|/.test(text))) {
    return { ok: false, error: 'invalid_pdf_evidence' };
  }
  return {
    ok: true,
    evidence: {
      text: fragments > 0 ? text : '',
      pageCount,
      pagesRead,
      extractedFragments: fragments,
      truncated: value.truncated,
    },
  };
}
