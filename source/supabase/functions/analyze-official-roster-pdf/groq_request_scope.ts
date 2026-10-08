// Sécurise la lecture Groq manuelle à UN PDF officiel sélectionné.
// Aucun accès réseau : testé indépendamment du lecteur de PDF et de Groq.
export type GroqScopeError =
  | 'groq_manual_confirmation_required'
  | 'groq_pdf_selection_mismatch'
  | null;

const VALID_SLOTS = new Set(['hm6_bouskoura', 'hm6_rabat', 'hck_casa']);

export function validateGroqStoredSelection(input: {
  manualGroqConfirmed: boolean;
  selectedSlot: string;
  selectedResourceId: string;
  selectedUpdatedAt: string;
  resourceId: string;
  actualSlot: unknown;
  actualUpdatedAt: unknown;
}): GroqScopeError {
  if (!input.manualGroqConfirmed) return 'groq_manual_confirmation_required';
  const selectedDate = Date.parse(input.selectedUpdatedAt);
  const actualDate = Date.parse(String(input.actualUpdatedAt));
  if (!VALID_SLOTS.has(input.selectedSlot) ||
      input.selectedResourceId !== input.resourceId ||
      input.actualSlot !== input.selectedSlot ||
      !Number.isFinite(selectedDate) ||
      !Number.isFinite(actualDate) ||
      selectedDate !== actualDate) {
    return 'groq_pdf_selection_mismatch';
  }
  return null;
}

export function validateGroqPreflightSelection(input: {
  manualGroqConfirmed: boolean;
  selectedSlot: string;
  selectedResourceId: string;
  slot: string;
}): GroqScopeError {
  if (!input.manualGroqConfirmed) return 'groq_manual_confirmation_required';
  if (!VALID_SLOTS.has(input.selectedSlot) ||
      input.selectedSlot !== input.slot ||
      input.selectedResourceId !== '') {
    return 'groq_pdf_selection_mismatch';
  }
  return null;
}
