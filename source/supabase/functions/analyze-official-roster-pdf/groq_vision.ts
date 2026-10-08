// Lecteur Groq R6 : conversion des OCTETS du PDF officiel en images en mémoire.
// Ne stocke jamais les images ; ne s'appuie ni sur l'annuaire ni sur des images
// non certifiées soumises par le client. Tous les créneaux sont Urgences uniquement.
import { PDFiumLibrary } from 'npm:@hyzyla/pdfium@2.1.13';
import UPNG from 'npm:upng-js@2.1.0';

type Page = { pageNumber: number; imageUrl: string };
// Qwen 3.6 was retired for standard Groq accounts on 14 Sep 2026.
const DEFAULT_MODEL = 'qwen/qwen3.8-27b';
// Les trois images autorisées par Groq coûtent à elles seules 6144 tokens.
// Une seule page réduit le risque de 429 dans les organisations à 8K TPM.
export const GROQ_MAX_IMAGES_PER_REQUEST = 1;

function b64(raw: Uint8Array): string {
  const parts: string[] = [];
  for (let i = 0; i < raw.length; i += 32768) {
    parts.push(String.fromCharCode(...raw.subarray(i, i + 32768)));
  }
  return btoa(parts.join(''));
}

async function pdfPages(bytes: Uint8Array): Promise<Page[]> {
  const pages: Page[] = [];
  let document: any = null;
  let library: any = null;
  try {
    library = await PDFiumLibrary.init();
    document = await library.loadDocument(bytes);
    for (const page of document.pages()) {
      if (pages.length >= 24) throw new Error('pdf_too_many_pages');
      const bitmap = await page.render({
        scale: 2.4,
        render: async (p: { data: Uint8Array; width: number; height: number }) => {
          const data = new Uint8Array(p.data);
          const png = UPNG.encode([data.buffer], p.width, p.height, 0);
          return new Uint8Array(png);
        },
      });
      const image = new Uint8Array(bitmap.data);
      if (image.byteLength === 0 || image.byteLength > 3 * 1024 * 1024) {
        throw new Error('pdf_page_image_too_large');
      }
      pages.push({
        pageNumber: pages.length + 1,
        imageUrl: 'data:image/png;base64,' + b64(image),
      });
    }
    if (!pages.length) throw new Error('pdf_render_empty');
    return pages;
  } catch (e) {
    console.error('PDF pages conversion failure', e instanceof Error ? e.message : 'error');
    throw new Error('groq_pdf_render_failed');
  } finally {
    document?.destroy();
    library?.destroy();
  }
}

function parseJSON(value: unknown): any {
  if (typeof value !== 'string' || !value.trim()) throw new Error('groq_invalid_response');
  try {
    return JSON.parse(value);
  } catch (_) {
    const begin = value.indexOf('{'), end = value.lastIndexOf('}');
    if (begin >= 0 && end > begin) return JSON.parse(value.slice(begin, end + 1));
    throw new Error('groq_invalid_response');
  }
}

/** Décode uniquement les cellules explicitement décrites par le modèle.
 * Le numéro de page est lié aux octets PDF rendus par le serveur, jamais à une
 * entrée libre du modèle. Un champ manquant annule intégralement la relecture.
 */
export function expandCompactRoster(raw: any, pageNumber: number): any {
  if (!Number.isInteger(pageNumber) || pageNumber < 1 || !raw ||
      typeof raw !== 'object' || !Array.isArray(raw.r) ||
      !['U', 'S', '?'].includes(raw.scope) ||
      !['M', 'R'].includes(raw.mode) ||
      typeof raw.start !== 'string' || typeof raw.end !== 'string' ||
      typeof raw.q !== 'number' || raw.q < 0 || raw.q > 1 ||
      !Array.isArray(raw.w) || !raw.w.every((w: any) => typeof w === 'string')) {
    throw new Error('groq_invalid_response');
  }
  const shifts: Record<string, string> = {
    J: 'urg-jour', N: 'urg-nuit', H: 'urg-24h',
  };
  const rows = raw.r.map((r: any) => {
    if (!Array.isArray(r) || r.length !== 5 ||
        typeof r[0] !== 'string' ||
        !Object.prototype.hasOwnProperty.call(shifts, r[1]) ||
        !Array.isArray(r[2]) || !Array.isArray(r[3]) ||
        !r[3].every((name: any) => typeof name === 'string') ||
        typeof r[4] !== 'string' || r[4].trim().length === 0) {
      throw new Error('groq_invalid_response');
    }
    const doctors = r[2].map((d: any) => {
      if (!Array.isArray(d) || d.length !== 4 ||
          !d.slice(0, 3).every((v: any) => typeof v === 'string') ||
          typeof d[3] !== 'number' || d[3] < 0 || d[3] > 1) {
        throw new Error('groq_invalid_response');
      }
      return {
        first_name: d[0], last_name: d[1], full_name: d[2],
        confidence: d[3],
      };
    });
    return {
      date: r[0], shift: shifts[r[1]], doctors,
      red_names: r[3], page_number: pageNumber, zone: r[4],
    };
  });
  if (raw.mode === 'M' &&
      (!Number.isInteger(raw.m) || raw.m < 1 || raw.m > 12 ||
       !Number.isInteger(raw.y) || raw.y < 2020 || raw.y > 2100)) {
    throw new Error('groq_invalid_response');
  }
  if (raw.mode === 'R' && (raw.m != null || raw.y != null)) {
    throw new Error('groq_invalid_response');
  }
  return {
    month: raw.mode === 'M' ? raw.m : null,
    year: raw.mode === 'M' ? raw.y : null,
    document_scope: raw.scope === 'U' ? 'urgences'
      : raw.scope === 'S' ? 'non_urgences' : 'mixed_or_uncertain',
    coverage_mode: raw.mode === 'M' ? 'full_month' : 'explicit_range',
    coverage_start: raw.start, coverage_end: raw.end,
    confidence: raw.q, warnings: raw.w, rows,
  };
}

/** Accepte aussi une sortie historique complète (validation strictement
 * inchangée) ; la sortie compacte est préférée pour ne pas dépasser 4096 tokens.
 */
function decodeGroqResult(value: any, pages: Page[]): any {
  if (value && Array.isArray(value.r)) {
    if (pages.length !== 1) throw new Error('groq_invalid_response');
    return expandCompactRoster(value, pages[0].pageNumber);
  }
  if (!Array.isArray(value?.rows) || !value?.document_scope) {
    throw new Error('groq_invalid_response');
  }
  const validPages = new Set(pages.map(p => p.pageNumber));
  if (value.rows.some((r: any) => !validPages.has(r?.page_number))) {
    throw new Error('groq_invalid_page_reference');
  }
  return value;
}

export class GroqRateLimitError extends Error {
  constructor(readonly retryAfterSeconds: number | null) {
    super('groq_rate_limited');
    this.name = 'GroqRateLimitError';
  }
}

const GROQ_MAX_WAIT_MS = 35000;
const GROQ_READING_DEADLINE_MS = 105000;

function retryAfterMs(response: Response): number | null {
  const v = response.headers.get('retry-after');
  if (!v) return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.ceil(n * 1000) + 300;
}

export async function scanChunk(
  pages: Page[],
  key: string,
  prompt: string,
  model: string,
  deadline: number,
  fetchImpl: typeof fetch = fetch,
): Promise<any> {
  const schemaHint = [
    'Réponds en JSON MINIFIÉ uniquement. Format COMPACT OBLIGATOIRE (pas les noms de champs longs).',
    '{"m":10,"y":2026,"scope":"U","mode":"M","start":"2026-10-01",',
    '"end":"2026-10-31","q":0.98,"w":[],"r":[',
    '["2026-10-01","J",[["Prénom","Nom","Prénom Nom",0.98]],[],"ligne 1/J"]]}',
    'm/y = mois et année si mode M (full_month), sinon null et mode R (explicit_range).',
    'scope: U uniquement si clairement Urgences; S pour Service; ? si mixte ou incertain.',
    'r : CHAQUE cellule visible, même vide, représentée par',
    '[date ISO, J (urg-jour) ou N (urg-nuit) ou H (urg-24h),',
    'médecins [[prénom,nom,nom complet exactement imprimé,confiance]],',
    'noms rouges [nom complet], zone exacte ligne/colonne].',
    'Pour chaque jour du tableau: deux cellules J+N, OU une cellule H fusionnée.',
    'Ne jamais associer automatiquement une identité au répertoire, ne jamais inventer.',
    'Garde la totalité des cellules; ne compresse pas en supprimant des lignes.',
    'w = avertissements textuels, q = confiance globale 0..1,',
    'start/end = dates de couverture officiellement affichées.',
    'Page PDF analysée : ' + pages.map(p => p.pageNumber).join(', ') + '.',
    'Le serveur attribue lui-même le numéro de page (ne retourne pas page_number).',
  ].join('\n');

  // Groq may return 400/json_validate_failed when server-enforced JSON mode
  // rejects an answer. One fallback without response_format remains subject
  // to the same strict downstream R6 validation.
  let result: Response | null = null;
  let relaxedJson = false;
  let retriedRateLimit = false;
  for (let attempt = 0; attempt < 3; attempt++) {
    result = await fetchImpl('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + key,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.1,
        stream: false,
        max_completion_tokens: 4096,
        reasoning_effort: 'none',
        ...(relaxedJson ? {} : { response_format: { type: 'json_object' } }),
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: prompt + '\n\n' + schemaHint },
            ...pages.map(page => ({
              type: 'image_url',
              image_url: { url: page.imageUrl },
            })),
          ],
        }],
      }),
    });

    if (result.status === 400 && !relaxedJson) {
      const body = await result.clone().json().catch(() => ({}));
      if (body?.error?.code === 'json_validate_failed' &&
          attempt < 2 && Date.now() < deadline) {
        relaxedJson = true;
        console.warn('Groq R6 JSON validation rejected; retrying as plain text');
        continue;
      }
    }
    if (result.status === 429 && !retriedRateLimit) {
      const delayMs = retryAfterMs(result);
      if (delayMs != null && delayMs <= GROQ_MAX_WAIT_MS &&
          Date.now() + delayMs < deadline && attempt < 2) {
        retriedRateLimit = true;
        console.info('Groq R6 rate limit: retry after seconds', Math.ceil(delayMs / 1000));
        await new Promise((resolve) => setTimeout(resolve, delayMs));
        continue;
      }
    }
    break;
  }
  if (!result) throw new Error('groq_read_failed');
  const payload = await result.json().catch(() => ({}));
  if (!result.ok) {
    const error = payload?.error ?? {};
    console.error('Groq R6 request failed', {
      http_status: result.status,
      error_code: String(error.code ?? '').slice(0, 90),
      error_type: String(error.type ?? '').slice(0, 90),
      retry_after_seconds: result.headers.get('retry-after') ?? null,
      remaining_tokens: result.headers.get('x-ratelimit-remaining-tokens') ?? null,
    });
    if (result.status === 429) {
      const delayMs = retryAfterMs(result);
      throw new GroqRateLimitError(delayMs == null ? null : Math.ceil(delayMs / 1000));
    }
    if ([401, 403].includes(result.status)) throw new Error('groq_authentication_failed');
    if ([400, 404, 422].includes(result.status)) throw new Error('groq_request_invalid');
    throw new Error('groq_read_failed');
  }
  if (payload?.choices?.[0]?.finish_reason === 'length') {
    throw new Error('groq_response_truncated');
  }
  const value = parseJSON(payload?.choices?.[0]?.message?.content);
  return decodeGroqResult(value, pages);
}

export function mergeChunkReads(chunks: any[]): any {
  if (chunks.length === 1) return chunks[0];
  const rows = chunks.flatMap(c => c.rows);
  const dates = rows.map((r: any) => String(r.date ?? ''))
    .filter((d: string) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort();
  const scopes = [...new Set(chunks.map(c => c.document_scope))];
  const months = [...new Set(chunks
    .filter(c => Number.isInteger(c.month) && Number.isInteger(c.year))
    .map(c => String(c.year) + '-' + String(c.month).padStart(2, '0')))];
  // Les groupes paginés ne peuvent déclarer le mois complet qu'après
  // assemblage. Une discordance de mois/périmètre bloque la validation.
  const scope = scopes.length === 1 ? scopes[0] : 'mixed_or_uncertain';
  const uniqueMonth = months.length === 1 ? String(months[0]) : null;
  const mode = uniqueMonth != null &&
    chunks.every(c => c.coverage_mode === 'full_month') ? 'full_month' : 'explicit_range';
  return {
    month: mode === 'full_month' ? Number(uniqueMonth!.slice(5, 7)) : null,
    year: mode === 'full_month' ? Number(uniqueMonth!.slice(0, 4)) : null,
    document_scope: scope,
    coverage_mode: mode,
    coverage_start: dates[0] ?? '',
    coverage_end: dates[dates.length - 1] ?? '',
    confidence: Math.min(...chunks.map(c =>
      typeof c.confidence === 'number' ? c.confidence : 0)),
    warnings: chunks.flatMap(c => Array.isArray(c.warnings) ? c.warnings : [])
      .slice(0, 50),
    rows,
  };
}

export class GroqRosterVision {
  private readonly readDeadline = Date.now() + GROQ_READING_DEADLINE_MS;
  private constructor(private readonly pages: Page[]) {}

  static async fromPdf(bytes: Uint8Array): Promise<GroqRosterVision> {
    return new GroqRosterVision(await pdfPages(bytes));
  }

  async read(key: string, prompt: string, modelEnv: string): Promise<any> {
    const configuredModel =
      (Deno.env.get(modelEnv) || Deno.env.get('GROQ_VISION_MODEL') || '').trim();
    // Avoid stale server configuration pointing at the retired Groq model.
    const model = !configuredModel || configuredModel === 'qwen/qwen3.6-27b'
      ? DEFAULT_MODEL
      : configuredModel;
    const chunks: any[] = [];
    for (let index = 0; index < this.pages.length; index += GROQ_MAX_IMAGES_PER_REQUEST) {
      const group = this.pages.slice(index, index + GROQ_MAX_IMAGES_PER_REQUEST);
      if (Date.now() >= this.readDeadline) throw new Error('groq_rate_limited');
      const extraction = await scanChunk(group, key, prompt, model, this.readDeadline);
      if (extraction.rows.length === 0) {
        throw new Error('groq_page_without_cells');
      }
      chunks.push(extraction);
    }
    return mergeChunkReads(chunks);
  }

  get pageCount(): number {
    return this.pages.length;
  }
}
