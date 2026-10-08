import { validateGroqStoredSelection, validateGroqPreflightSelection } from './groq_request_scope.ts';

const a = (ok: boolean, message: string) => { if (!ok) throw new Error(message); };
const base = {
  manualGroqConfirmed: true,
  selectedSlot: 'hm6_bouskoura',
  selectedResourceId: 'resource-bouskoura',
  selectedUpdatedAt: '2026-09-30T00:49:00.000Z',
  resourceId: 'resource-bouskoura',
  actualSlot: 'hm6_bouskoura',
  actualUpdatedAt: '2026-09-30T00:49:00+00:00',
};

Deno.test('Manual Groq is limited to the exact chosen PDF and its revision', () => {
  a(validateGroqStoredSelection(base) === null, 'selected resource must pass');
  a(validateGroqStoredSelection({ ...base, selectedResourceId: 'resource-rabat' }) ===
    'groq_pdf_selection_mismatch', 'other PDFs must fail');
  a(validateGroqStoredSelection({ ...base, actualSlot: 'hm6_rabat' }) ===
    'groq_pdf_selection_mismatch', 'other hospital must fail');
  a(validateGroqStoredSelection({ ...base, actualUpdatedAt: '2026-10-01T00:49:00Z' }) ===
    'groq_pdf_selection_mismatch', 'changed PDF must fail');
  a(validateGroqStoredSelection({ ...base, selectedUpdatedAt: 'bad-date' }) ===
    'groq_pdf_selection_mismatch', 'invalid time must fail');
  a(validateGroqStoredSelection({ ...base, manualGroqConfirmed: false }) ===
    'groq_manual_confirmation_required', 'background/legacy requests must fail');
});

Deno.test('Manual Groq preflight accepts only the selected hospital', () => {
  const preflight = {
    manualGroqConfirmed: true,
    selectedSlot: 'hck_casa',
    selectedResourceId: '',
    slot: 'hck_casa',
  };
  a(validateGroqPreflightSelection(preflight) === null, 'explicit upload choice passes');
  a(validateGroqPreflightSelection({ ...preflight, slot: 'hm6_rabat' }) ===
    'groq_pdf_selection_mismatch', 'cross-hospital preflight blocked');
  a(validateGroqPreflightSelection({ ...preflight, selectedResourceId: 'other-pdf' }) ===
    'groq_pdf_selection_mismatch', 'preflight cannot select another stored PDF');
  a(validateGroqPreflightSelection({ ...preflight, manualGroqConfirmed: false }) ===
    'groq_manual_confirmation_required', 'legacy automatic preflight blocked');
});
