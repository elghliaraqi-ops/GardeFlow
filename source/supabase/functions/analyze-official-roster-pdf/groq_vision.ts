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

async function scanChunk(
  pages: Page[],
  key: string,
  prompt: string,
  model: string,
): Promise<any> {
  const schemaHint =
    'Retourne uniquement un objet JSON sans Markdown, avec les champs ' +
    'month,year,document_scope,coverage_mode,coverage_start,coverage_end,' +
    'confidence,warnings,rows. Dans rows : date,shift,doctors,red_names,' +
    'page_number,zone ; chaque doctor a first_name,last_name,full_name,confidence. ' +
    'Tu dois lire uniquement les pages envoyées, sans inventer des pages manquantes. ' +
    'Numéros exacts des pages PDF : ' + pages.map(p => p.pageNumber).join(', ') + '. ' +
    'Seuls les créneaux urg-jour, urg-nuit, urg-24h sont autorisés. ' +
    'Si le document concerne le Service, document_scope vaut non_urgences.';
  // Une erreur 429 ponctuelle peut être retentée si le serveur annonce un
  // délai bref. Pas de boucle longue au sein d'une Edge Function.
  let result: Response | null = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    result = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + key,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      temperature: 0.1,
      stream: false,
      // Réduire la réservation de tokens au lieu de demander 16000 tokens
      // pour une seule page. Une sortie tronquée est rejetée plus bas.
      max_completion_tokens: 4096,
      reasoning_effort: 'none',
      response_format: { type: 'json_object' },
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
    if (result.status === 429 && attempt === 0) {
      const retryAfter = Number(result.headers.get('retry-after'));
      // Respecter Retry-After uniquement si une reprise courte est possible.
      if (Number.isFinite(retryAfter) && retryAfter > 0 && retryAfter <= 8) {
        await new Promise((resolve) => setTimeout(resolve, retryAfter * 1000));
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
    if (result.status === 429) throw new Error('groq_rate_limited');
    if ([401, 403].includes(result.status)) throw new Error('groq_authentication_failed');
    if ([400, 404, 422].includes(result.status)) throw new Error('groq_request_invalid');
    throw new Error('groq_read_failed');
  }
  if (payload?.choices?.[0]?.finish_reason === 'length') {
    throw new Error('groq_response_truncated');
  }
  const value = parseJSON(payload?.choices?.[0]?.message?.content);
  if (!Array.isArray(value?.rows) || !value?.document_scope) {
    throw new Error('groq_invalid_response');
  }
  const validPages = new Set(pages.map(p => p.pageNumber));
  if (value.rows.some((r: any) => !validPages.has(r?.page_number))) {
    throw new Error('groq_invalid_page_reference');
  }
  return value;
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
      const extraction = await scanChunk(group, key, prompt, model);
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
