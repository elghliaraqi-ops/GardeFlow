import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { GroqRosterVision, GroqRateLimitError } from './groq_vision.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const PARSER_REVISION = 'v12.0.3-groq-r6';
const SHIFTS = new Set(['urg-jour', 'urg-nuit', 'urg-24h']);
const MIN_CONFIDENCE = 0.90;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function extractResponseText(payload: any): string {
  if (typeof payload?.output_text === 'string') return payload.output_text;
  const parts: string[] = [];
  for (const item of payload?.output ?? []) {
    for (const part of item?.content ?? []) {
      if (typeof part?.text === 'string') parts.push(part.text);
    }
  }
  return parts.join('\n');
}

function parseJsonLoose(raw: string): any {
  const value = raw.trim();
  if (!value) throw new Error('empty_model_output');
  try {
    return JSON.parse(value);
  } catch (_) {
    // Continue with fenced / embedded JSON extraction.
  }
  const fenced = value.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced) return JSON.parse(fenced[1]);
  const start = value.indexOf('{');
  const end = value.lastIndexOf('}');
  if (start >= 0 && end > start) {
    return JSON.parse(value.slice(start, end + 1));
  }
  throw new Error('invalid_model_json');
}

function normalizeText(value: unknown): string {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('fr')
    .replace(/[’'\-–—]/g, ' ')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function validIsoDate(raw: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return false;
  const d = new Date(raw + 'T00:00:00Z');
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === raw;
}

type Doctor = {
  first_name: string;
  last_name: string;
  full_name: string;
  confidence: number;
};

type Row = {
  date: string;
  shift: 'urg-jour' | 'urg-nuit' | 'urg-24h';
  doctors: Doctor[];
  names: string[];
  red_names: string[];
  page_number: number | null;
  zone: string | null;
};

type Read = {
  month: number | null;
  year: number | null;
  document_scope: 'urgences' | 'non_urgences' | 'mixed_or_uncertain';
  coverage_mode: 'full_month' | 'explicit_range';
  coverage_start: string;
  coverage_end: string;
  confidence: number;
  warnings: string[];
  rows: Row[];
  validationErrors: string[];
};

type LocalCell = {
  date: string;
  shift: 'urg-jour' | 'urg-nuit' | 'urg-24h';
  text: string;
  red_text: string;
  page_number: number | null;
  zone: string | null;
};

type Conflict = {
  code: string;
  date: string | null;
  shift: string | null;
  message: string;
  a: unknown;
  b: unknown;
  c?: unknown;
  resolution?: unknown;
};

type ManualResolution = {
  date: string;
  shift: string;
  action: 'use_b' | 'use_c' | 'manual' | 'remove';
  final_date?: string;
  final_shift?: string;
  doctors?: unknown[];
  red_names?: unknown[];
};

function normalizeDoctor(raw: any): Doctor | null {
  const first = String(raw?.first_name ?? '').replace(/\s+/g, ' ').trim();
  const last = String(raw?.last_name ?? '').replace(/\s+/g, ' ').trim();
  const full = String(raw?.full_name ?? '').replace(/\s+/g, ' ').trim();
  const effective = full || (first + ' ' + last).trim();
  if (!effective) return null;
  const confidence =
    typeof raw?.confidence === 'number'
      ? Math.max(0, Math.min(1, raw.confidence))
      : 0;
  return {
    first_name: first,
    last_name: last,
    full_name: effective,
    confidence,
  };
}

function normalizeNameList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const result: string[] = [];
  for (const raw of value) {
    const name = String(raw ?? '').replace(/\s+/g, ' ').trim();
    if (!name) continue;
    const key = normalizeText(name);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(name);
  }
  result.sort((a, b) => normalizeText(a).localeCompare(normalizeText(b), 'fr'));
  return result;
}

function mergeDoctors(values: unknown): Doctor[] {
  if (!Array.isArray(values)) return [];
  const byKey = new Map<string, Doctor>();
  for (const raw of values) {
    const doctor = normalizeDoctor(raw);
    if (!doctor) continue;
    const key =
      normalizeText(doctor.first_name) + '|' +
      normalizeText(doctor.last_name) + '|' +
      normalizeText(doctor.full_name);
    const previous = byKey.get(key);
    if (!previous || doctor.confidence > previous.confidence) {
      byKey.set(key, doctor);
    }
  }
  return [...byKey.values()].sort((a, b) =>
    normalizeText(a.full_name).localeCompare(normalizeText(b.full_name), 'fr')
  );
}

function validateCoverage(
  rows: Array<{ date: string; shift: string }>,
  options?: {
    coverageMode?: string | null;
    coverageStart?: string | null;
    coverageEnd?: string | null;
    month?: number | null;
    year?: number | null;
  },
): string[] {
  const errors: string[] = [];
  const byDate = new Map<string, Set<string>>();
  for (const row of rows) {
    if (!validIsoDate(row.date)) {
      errors.push('Date invalide: ' + row.date);
      continue;
    }
    if (!SHIFTS.has(row.shift)) {
      errors.push('Créneau invalide ' + row.date + ': ' + row.shift);
      continue;
    }
    if (!byDate.has(row.date)) byDate.set(row.date, new Set());
    byDate.get(row.date)!.add(row.shift);
  }

  const dates = [...byDate.keys()].sort();
  if (dates.length === 0) {
    errors.push('Aucune date exploitable détectée.');
    return errors;
  }

  const coverageMode = options?.coverageMode ?? null;
  const declaredStart = options?.coverageStart ?? null;
  const declaredEnd = options?.coverageEnd ?? null;

  let expectedStart = dates[0];
  let expectedEnd = dates[dates.length - 1];

  if (coverageMode != null) {
    if (coverageMode !== 'full_month' && coverageMode !== 'explicit_range') {
      errors.push('Mode de couverture officiel invalide.');
    }

    if (!declaredStart || !validIsoDate(declaredStart)) {
      errors.push('Début de couverture officiel absent ou invalide.');
    } else {
      expectedStart = declaredStart;
    }
    if (!declaredEnd || !validIsoDate(declaredEnd)) {
      errors.push('Fin de couverture officielle absente ou invalide.');
    } else {
      expectedEnd = declaredEnd;
    }

    if (
      declaredStart &&
      declaredEnd &&
      validIsoDate(declaredStart) &&
      validIsoDate(declaredEnd) &&
      declaredStart > declaredEnd
    ) {
      errors.push('Plage de couverture officielle inversée.');
    }

    if (coverageMode === 'full_month') {
      const month = options?.month ?? null;
      const year = options?.year ?? null;
      if (
        month == null ||
        year == null ||
        month < 1 ||
        month > 12 ||
        year < 2020 ||
        year > 2100
      ) {
        errors.push('Mois/année principal requis pour une couverture mensuelle.');
      } else {
        const monthStart = new Date(Date.UTC(year, month - 1, 1))
          .toISOString()
          .slice(0, 10);
        const monthEnd = new Date(Date.UTC(year, month, 0))
          .toISOString()
          .slice(0, 10);
        let monthCursor = new Date(monthStart + 'T00:00:00Z');
        const monthLast = new Date(monthEnd + 'T00:00:00Z');
        while (monthCursor <= monthLast) {
          const key = monthCursor.toISOString().slice(0, 10);
          if (!byDate.has(key)) {
            errors.push('Jour du mois principal absent: ' + key);
          }
          monthCursor.setUTCDate(monthCursor.getUTCDate() + 1);
        }
      }
    } else if (
      coverageMode === 'explicit_range' &&
      (options?.month != null || options?.year != null)
    ) {
      errors.push(
        'month/year doivent être null pour une plage explicite non mensuelle.',
      );
    }
  }

  if (validIsoDate(expectedStart) && validIsoDate(expectedEnd)) {
    const firstObserved = dates[0];
    const lastObserved = dates[dates.length - 1];
    if (firstObserved > expectedStart) {
      errors.push('Début de planning non interprété: ' + expectedStart);
    }
    if (lastObserved < expectedEnd) {
      errors.push('Fin de planning non interprétée: ' + expectedEnd);
    }
    if (firstObserved < expectedStart || lastObserved > expectedEnd) {
      errors.push('Date détectée hors de la plage officielle déclarée.');
    }

    let cursor = new Date(expectedStart + 'T00:00:00Z');
    const last = new Date(expectedEnd + 'T00:00:00Z');
    while (cursor <= last) {
      const key = cursor.toISOString().slice(0, 10);
      if (!byDate.has(key)) errors.push('Date absente: ' + key);
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
  }

  for (const date of dates) {
    const shifts = byDate.get(date)!;
    const valid24 = shifts.size === 1 && shifts.has('urg-24h');
    const validSplit =
      shifts.size === 2 &&
      shifts.has('urg-jour') &&
      shifts.has('urg-nuit');
    if (!valid24 && !validSplit) {
      errors.push(
        'Couverture incomplète ' + date + ': ' + [...shifts].sort().join(', '),
      );
    }
  }
  return errors;
}

function normalizeExtraction(raw: any): Read {
  const merged = new Map<string, Row>();
  const validationErrors: string[] = [];
  const month =
    Number.isInteger(raw?.month) && raw.month >= 1 && raw.month <= 12
      ? raw.month
      : null;
  const year =
    Number.isInteger(raw?.year) && raw.year >= 2020 && raw.year <= 2100
      ? raw.year
      : null;
  const documentScope =
    raw?.document_scope === 'urgences' ||
      raw?.document_scope === 'non_urgences' ||
      raw?.document_scope === 'mixed_or_uncertain'
      ? raw.document_scope as
          | 'urgences'
          | 'non_urgences'
          | 'mixed_or_uncertain'
      : 'mixed_or_uncertain';
  if (documentScope !== 'urgences') {
    validationErrors.push(
      documentScope === 'non_urgences'
        ? 'Le document fourni n’est pas un planning officiel des Urgences.'
        : 'Le périmètre du document est mixte ou incertain : import Urgences bloqué.',
    );
  }

  const coverageMode =
    raw?.coverage_mode === 'full_month' ||
      raw?.coverage_mode === 'explicit_range'
      ? raw.coverage_mode as 'full_month' | 'explicit_range'
      : 'explicit_range';
  if (
    raw?.coverage_mode !== 'full_month' &&
    raw?.coverage_mode !== 'explicit_range'
  ) {
    validationErrors.push('Mode de couverture officiel absent ou invalide.');
  }
  const coverageStart =
    typeof raw?.coverage_start === 'string'
      ? raw.coverage_start.trim()
      : '';
  const coverageEnd =
    typeof raw?.coverage_end === 'string'
      ? raw.coverage_end.trim()
      : '';
  const rawRows = Array.isArray(raw?.rows) ? raw.rows : [];

  for (const candidate of rawRows) {
    const date = String(candidate?.date ?? '').trim();
    const shift = String(candidate?.shift ?? '').trim();
    if (!validIsoDate(date)) {
      validationErrors.push('Date invalide: ' + date);
      continue;
    }
    if (!SHIFTS.has(shift)) {
      validationErrors.push('Créneau invalide le ' + date + ': ' + shift);
      continue;
    }

    const doctors = mergeDoctors(candidate?.doctors);
    const redNames = normalizeNameList(candidate?.red_names);
    const pageNumber =
      Number.isInteger(candidate?.page_number) && candidate.page_number > 0
        ? candidate.page_number
        : null;
    const zone =
      typeof candidate?.zone === 'string' && candidate.zone.trim()
        ? candidate.zone.trim().slice(0, 180)
        : null;

    const key = date + '|' + shift;
    const existing = merged.get(key);
    if (existing) {
      validationErrors.push(
        'Cellule dupliquée dans la lecture visuelle: ' + date + ' ' + shift,
      );
    }
    if (!existing) {
      merged.set(key, {
        date,
        shift: shift as Row['shift'],
        doctors,
        names: doctors.map((doctor) => doctor.full_name),
        red_names: redNames,
        page_number: pageNumber,
        zone,
      });
    } else {
      existing.doctors = mergeDoctors([...existing.doctors, ...doctors]);
      existing.names = existing.doctors.map((doctor) => doctor.full_name);
      existing.red_names = normalizeNameList([
        ...existing.red_names,
        ...redNames,
      ]);
      existing.page_number ??= pageNumber;
      existing.zone ??= zone;
    }
  }

  const rows = [...merged.values()].sort(
    (a, b) => a.date.localeCompare(b.date) || a.shift.localeCompare(b.shift),
  );

  validationErrors.push(
    ...validateCoverage(rows, {
      coverageMode,
      coverageStart,
      coverageEnd,
      month,
      year,
    }),
  );
  for (const row of rows) {
    for (const doctor of row.doctors) {
      if (!normalizeText(doctor.first_name) || !normalizeText(doctor.last_name)) {
        validationErrors.push(
          'Prénom/nom incomplet ' + row.date + ' ' + row.shift + ': ' +
            doctor.full_name,
        );
      }
      if (doctor.confidence < MIN_CONFIDENCE) {
        validationErrors.push(
          'Confiance nominative faible ' + row.date + ' ' + row.shift + ': ' +
            doctor.full_name,
        );
      }
    }
    if (row.page_number == null) {
      validationErrors.push(
        'Page non localisée ' + row.date + ' ' + row.shift + '.',
      );
    }
    if (row.zone == null || row.zone.trim().length === 0) {
      validationErrors.push(
        'Zone non localisée ' + row.date + ' ' + row.shift + '.',
      );
    }
  }

  const confidence =
    typeof raw?.confidence === 'number'
      ? Math.max(0, Math.min(1, raw.confidence))
      : 0;
  const warnings = Array.isArray(raw?.warnings)
    ? raw.warnings.map((value: any) => String(value)).slice(0, 50)
    : [];
  return {
    month,
    year,
    document_scope: documentScope,
    coverage_mode: coverageMode,
    coverage_start: coverageStart,
    coverage_end: coverageEnd,
    confidence,
    warnings,
    rows,
    validationErrors: [...new Set(validationErrors)],
  };
}

function normalizeLocalEvidence(raw: unknown): {
  cells: LocalCell[];
  validationErrors: string[];
} {
  const validationErrors: string[] = [];
  if (!Array.isArray(raw) || raw.length === 0) {
    return {
      cells: [],
      validationErrors: [
        'Lecture A locale absente. Vérification indépendante impossible.',
      ],
    };
  }

  const merged = new Map<string, LocalCell>();
  for (const candidate of raw.slice(0, 300)) {
    const date = String(candidate?.date ?? '').trim();
    const shift = String(candidate?.shift ?? '').trim();
    if (!validIsoDate(date) || !SHIFTS.has(shift)) {
      validationErrors.push(
        'Preuve A invalide: ' + date + ' / ' + shift,
      );
      continue;
    }
    const text = String(candidate?.text ?? '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 1200);
    const redText = String(candidate?.red_text ?? '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 1200);
    const pageNumber =
      Number.isInteger(candidate?.page_number) && candidate.page_number > 0
        ? candidate.page_number
        : null;
    const zone =
      typeof candidate?.zone === 'string' && candidate.zone.trim()
        ? candidate.zone.trim().slice(0, 180)
        : null;
    const key = date + '|' + shift;
    const previous = merged.get(key);
    if (!previous) {
      merged.set(key, {
        date,
        shift: shift as LocalCell['shift'],
        text,
        red_text: redText,
        page_number: pageNumber,
        zone,
      });
    } else {
      previous.text = (previous.text + ' ' + text).replace(/\s+/g, ' ').trim();
      previous.red_text =
        (previous.red_text + ' ' + redText).replace(/\s+/g, ' ').trim();
    }
  }

  const cells = [...merged.values()].sort(
    (a, b) => a.date.localeCompare(b.date) || a.shift.localeCompare(b.shift),
  );
  validationErrors.push(...validateCoverage(cells));
  return {
    cells,
    validationErrors: [...new Set(validationErrors)],
  };
}

function tokenBag(value: string): Map<string, number> {
  const bag = new Map<string, number>();
  for (const token of normalizeText(value).split(' ')) {
    if (!token) continue;
    bag.set(token, (bag.get(token) ?? 0) + 1);
  }
  return bag;
}

function sameBag(a: Map<string, number>, b: Map<string, number>): boolean {
  if (a.size !== b.size) return false;
  for (const [key, value] of a.entries()) {
    if (b.get(key) !== value) return false;
  }
  return true;
}

function rowJson(row: Row | undefined): unknown {
  return row ?? {};
}

function localJson(cell: LocalCell | undefined): unknown {
  return cell ?? {};
}

function compareLocalVisual(local: LocalCell[], visual: Read): Conflict[] {
  const visualRows = visual.rows;
  const a = new Map(local.map((cell) => [cell.date + '|' + cell.shift, cell]));
  const b = new Map(visualRows.map((row) => [row.date + '|' + row.shift, row]));
  const keys = [...new Set([...a.keys(), ...b.keys()])].sort();
  const conflicts: Conflict[] = [];

  for (const key of keys) {
    const cell = a.get(key);
    const row = b.get(key);
    const parts = key.split('|');
    const date = parts[0] ?? null;
    const shift = parts[1] ?? null;
    if (!cell || !row) {
      conflicts.push({
        code: 'missing_cell',
        date,
        shift,
        message: !cell
          ? 'Cellule présente en lecture visuelle mais absente en A.'
          : 'Cellule présente en A mais absente en lecture visuelle.',
        a: localJson(cell),
        b: rowJson(row),
      });
      continue;
    }

    const visualNames = row.doctors.map((doctor) => doctor.full_name).join(' ');
    if (!sameBag(tokenBag(cell.text), tokenBag(visualNames))) {
      conflicts.push({
        code: 'identity_mismatch',
        date,
        shift,
        message: 'Le contenu nominatif de la cellule diffère entre A et B.',
        a: cell,
        b: row,
      });
    }

    if (cell.red_text || row.red_names.length > 0) {
      if (!sameBag(tokenBag(cell.red_text), tokenBag(row.red_names.join(' ')))) {
        conflicts.push({
          code: 'disciplinary_mismatch',
          date,
          shift,
          message: 'Le marquage rouge diffère entre A et B.',
          a: cell,
          b: row,
        });
      }
    }
  }
  const localDates = [...new Set(local.map((cell) => cell.date))].sort();
  if (localDates.length > 0) {
    const localStart = localDates[0];
    const localEnd = localDates[localDates.length - 1];
    if (
      visual.coverage_start !== localStart ||
      visual.coverage_end !== localEnd
    ) {
      conflicts.push({
        code: 'coverage_scope_mismatch',
        date: null,
        shift: null,
        message:
          'La plage officielle déclarée par la lecture visuelle diffère de la structure A.',
        a: { coverage_start: localStart, coverage_end: localEnd },
        b: {
          coverage_mode: visual.coverage_mode,
          coverage_start: visual.coverage_start,
          coverage_end: visual.coverage_end,
        },
      });
    }
  }

  return conflicts;
}

function canonical(read: Read): string {
  return read.rows
    .map((row) => {
      const doctors = row.doctors
        .map((doctor) =>
          normalizeText(doctor.first_name) + '|' +
          normalizeText(doctor.last_name) + '|' +
          normalizeText(doctor.full_name)
        )
        .sort()
        .join(',');
      const red = row.red_names.map(normalizeText).sort().join(',');
      return row.date + '|' + row.shift + '|' + doctors + '|red:' + red;
    })
    .join('\n');
}

function canonicalRow(row: Row): string {
  const doctors = row.doctors
    .map((doctor) =>
      normalizeText(doctor.first_name) + '|' +
      normalizeText(doctor.last_name) + '|' +
      normalizeText(doctor.full_name)
    )
    .sort()
    .join(',');
  const red = row.red_names.map(normalizeText).sort().join(',');
  return row.date + '|' + row.shift + '|' + doctors + '|red:' + red;
}

function compareVisualReads(
  first: Read,
  second: Read,
  code: string,
): Conflict[] {
  const left = new Map(
    first.rows.map((row) => [row.date + '|' + row.shift, row]),
  );
  const right = new Map(
    second.rows.map((row) => [row.date + '|' + row.shift, row]),
  );
  const keys = [...new Set([...left.keys(), ...right.keys()])].sort();
  const conflicts: Conflict[] = [];
  if (
    first.document_scope !== second.document_scope ||
    first.coverage_mode !== second.coverage_mode ||
    first.coverage_start !== second.coverage_start ||
    first.coverage_end !== second.coverage_end ||
    first.month !== second.month ||
    first.year !== second.year
  ) {
    conflicts.push({
      code: 'coverage_scope_mismatch',
      date: null,
      shift: null,
      message:
        'Les lectures ne concordent pas sur la plage officielle du document.',
      a: {
        document_scope: first.document_scope,
        coverage_mode: first.coverage_mode,
        coverage_start: first.coverage_start,
        coverage_end: first.coverage_end,
        month: first.month,
        year: first.year,
      },
      b: {
        document_scope: second.document_scope,
        coverage_mode: second.coverage_mode,
        coverage_start: second.coverage_start,
        coverage_end: second.coverage_end,
        month: second.month,
        year: second.year,
      },
    });
  }
  for (const key of keys) {
    const aRow = left.get(key);
    const bRow = right.get(key);
    if (
      !aRow ||
      !bRow ||
      canonicalRow(aRow) !== canonicalRow(bRow)
    ) {
      const parts = key.split('|');
      conflicts.push({
        code,
        date: parts[0] ?? null,
        shift: parts[1] ?? null,
        message: 'Les deux lectures visuelles ne concordent pas.',
        a: aRow ?? {},
        b: bRow ?? {},
      });
    }
  }
  return conflicts;
}

function readIsReliable(read: Read): boolean {
  return read.validationErrors.length === 0 &&
    read.confidence >= MIN_CONFIDENCE &&
    read.rows.every((row) =>
      row.doctors.every((doctor) =>
        doctor.confidence >= MIN_CONFIDENCE &&
        normalizeText(doctor.first_name).length > 0 &&
        normalizeText(doctor.last_name).length > 0
      )
    );
}

function minimumConfidence(read: Read): number {
  let value = read.confidence;
  for (const row of read.rows) {
    for (const doctor of row.doctors) {
      value = Math.min(value, doctor.confidence);
    }
  }
  return Math.max(0, Math.min(1, value));
}

function parseManualResolutions(raw: unknown): ManualResolution[] {
  if (!Array.isArray(raw)) return [];
  const result: ManualResolution[] = [];
  for (const value of raw.slice(0, 120)) {
    const date = String(value?.date ?? '').trim();
    const shift = String(value?.shift ?? '').trim();
    const action = String(value?.action ?? '').trim();
    if (
      !validIsoDate(date) ||
      !SHIFTS.has(shift) ||
      !['use_b', 'use_c', 'manual', 'remove'].includes(action)
    ) {
      continue;
    }
    result.push({
      date,
      shift,
      action: action as ManualResolution['action'],
      final_date:
        typeof value?.final_date === 'string'
          ? value.final_date.trim()
          : undefined,
      final_shift:
        typeof value?.final_shift === 'string'
          ? value.final_shift.trim()
          : undefined,
      doctors: Array.isArray(value?.doctors) ? value.doctors : undefined,
      red_names: Array.isArray(value?.red_names) ? value.red_names : undefined,
    });
  }
  return result;
}

function validatedManualRow(
  resolution: ManualResolution,
  source: Row | undefined,
  locationSource?: any,
): Row | null {
  const date = resolution.final_date || resolution.date;
  const shift = resolution.final_shift || resolution.shift;
  if (!validIsoDate(date) || !SHIFTS.has(shift)) return null;

  const rawDoctors =
    resolution.action === 'manual'
      ? resolution.doctors
      : source?.doctors;
  const doctors = mergeDoctors(rawDoctors).map((doctor) => ({
    ...doctor,
    confidence: 1,
  }));
  const redNames = normalizeNameList(
    resolution.action === 'manual'
      ? resolution.red_names
      : source?.red_names,
  );

  if (
    doctors.some(
      (doctor) =>
        !normalizeText(doctor.first_name) ||
        !normalizeText(doctor.last_name),
    )
  ) {
    return null;
  }

  const locationPage =
    Number.isInteger(locationSource?.page_number) &&
      locationSource.page_number > 0
      ? locationSource.page_number as number
      : null;
  const locationZone =
    typeof locationSource?.zone === 'string' && locationSource.zone.trim()
      ? locationSource.zone.trim()
      : null;

  return {
    date,
    shift: shift as Row['shift'],
    doctors,
    names: doctors.map((doctor) => doctor.full_name),
    red_names: redNames,
    page_number: source?.page_number ?? locationPage,
    zone: source?.zone ?? locationZone ?? 'Correction admin ciblée',
  };
}

function applyManualResolutions(
  readB: Read,
  readC: Read | null,
  conflicts: Conflict[],
  resolutions: ManualResolution[],
): {
  read: Read;
  conflicts: Conflict[];
} | null {
  if (resolutions.length === 0) return null;

  const requiredKeys = new Set<string>();
  for (const conflict of conflicts) {
    if (!conflict.date || !conflict.shift) {
      // Une anomalie purement structurelle sans cellule localisable ne peut
      // jamais être masquée par une correction manuelle.
      return null;
    }
    requiredKeys.add(conflict.date + '|' + conflict.shift);
  }

  const byResolution = new Map(
    resolutions.map((resolution) => [
      resolution.date + '|' + resolution.shift,
      resolution,
    ]),
  );
  for (const key of requiredKeys) {
    if (!byResolution.has(key)) return null;
  }

  const base =
    readC != null && readC.rows.length >= readB.rows.length ? readC : readB;
  const rows = new Map(
    base.rows.map((row) => [row.date + '|' + row.shift, { ...row }]),
  );
  const bRows = new Map(
    readB.rows.map((row) => [row.date + '|' + row.shift, row]),
  );
  const cRows = new Map(
    (readC?.rows ?? []).map((row) => [row.date + '|' + row.shift, row]),
  );

  for (const key of requiredKeys) {
    const resolution = byResolution.get(key)!;
    rows.delete(key);
    if (resolution.action === 'remove') continue;

    const source = resolution.action === 'use_b'
      ? bRows.get(key)
      : resolution.action === 'use_c'
        ? cRows.get(key)
        : undefined;
    if (
      (resolution.action === 'use_b' && !source) ||
      (resolution.action === 'use_c' && !source)
    ) {
      return null;
    }

    const matchingConflict = conflicts.find(
      (conflict) =>
        conflict.date === resolution.date &&
        conflict.shift === resolution.shift,
    );
    const locationCandidates = [
      matchingConflict?.c,
      matchingConflict?.b,
      matchingConflict?.a,
    ];
    const locationSource = locationCandidates.find(
      (candidate: any) =>
        candidate != null &&
        typeof candidate === 'object' &&
        (
          (Number.isInteger(candidate?.page_number) &&
            candidate.page_number > 0) ||
          (typeof candidate?.zone === 'string' && candidate.zone.trim())
        ),
    );

    const row = validatedManualRow(resolution, source, locationSource);
    if (!row) return null;
    rows.set(row.date + '|' + row.shift, row);
  }

  const normalized = normalizeExtraction({
    month: base.month,
    year: base.year,
    document_scope: base.document_scope,
    coverage_mode: base.coverage_mode,
    coverage_start: base.coverage_start,
    coverage_end: base.coverage_end,
    confidence: 1,
    warnings: [
      ...base.warnings,
      'Correction humaine ciblée appliquée aux zones litigieuses.',
    ],
    rows: [...rows.values()],
  });
  if (!readIsReliable(normalized)) return null;

  const resolvedConflicts = conflicts.map((conflict) => {
    const key = conflict.date + '|' + conflict.shift;
    const resolution = byResolution.get(key);
    return {
      ...conflict,
      resolution: resolution ?? null,
    };
  });

  return { read: normalized, conflicts: resolvedConflicts };
}

function attachC(
  conflicts: Conflict[],
  c: Read,
): Conflict[] {
  const cByKey = new Map(
    c.rows.map((row) => [row.date + '|' + row.shift, row]),
  );
  return conflicts.map((conflict) => {
    const key =
      (conflict.date ?? '') + '|' + (conflict.shift ?? '');
    return {
      ...conflict,
      c: cByKey.get(key) ?? {},
    };
  });
}

const extractionSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'month',
    'year',
    'document_scope',
    'coverage_mode',
    'coverage_start',
    'coverage_end',
    'confidence',
    'warnings',
    'rows',
  ],
  properties: {
    month: {
      anyOf: [
        { type: 'integer', minimum: 1, maximum: 12 },
        { type: 'null' },
      ],
    },
    year: {
      anyOf: [
        { type: 'integer', minimum: 2020, maximum: 2100 },
        { type: 'null' },
      ],
    },
    document_scope: {
      type: 'string',
      enum: ['urgences', 'non_urgences', 'mixed_or_uncertain'],
    },
    coverage_mode: {
      type: 'string',
      enum: ['full_month', 'explicit_range'],
    },
    coverage_start: {
      type: 'string',
      pattern: '^\\d{4}-\\d{2}-\\d{2}$',
    },
    coverage_end: {
      type: 'string',
      pattern: '^\\d{4}-\\d{2}-\\d{2}$',
    },
    confidence: {
      type: 'number',
      minimum: 0,
      maximum: 1,
    },
    warnings: {
      type: 'array',
      maxItems: 50,
      items: { type: 'string' },
    },
    rows: {
      type: 'array',
      maxItems: 160,
      items: {
        type: 'object',
        additionalProperties: false,
        required: [
          'date',
          'shift',
          'doctors',
          'red_names',
          'page_number',
          'zone',
        ],
        properties: {
          date: {
            type: 'string',
            pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          },
          shift: {
            type: 'string',
            enum: ['urg-jour', 'urg-nuit', 'urg-24h'],
          },
          doctors: {
            type: 'array',
            maxItems: 16,
            items: {
              type: 'object',
              additionalProperties: false,
              required: [
                'first_name',
                'last_name',
                'full_name',
                'confidence',
              ],
              properties: {
                first_name: { type: 'string' },
                last_name: { type: 'string' },
                full_name: { type: 'string' },
                confidence: {
                  type: 'number',
                  minimum: 0,
                  maximum: 1,
                },
              },
            },
          },
          red_names: {
            type: 'array',
            maxItems: 16,
            items: { type: 'string' },
          },
          page_number: {
            anyOf: [
              { type: 'integer', minimum: 1 },
              { type: 'null' },
            ],
          },
          zone: {
            anyOf: [
              { type: 'string', maxLength: 180 },
              { type: 'null' },
            ],
          },
        },
      },
    },
  },
};

const basePrompt = [
  "Tu es le lecteur visuel indépendant d'un planning officiel de gardes d'Urgences pour GardeFlow.", 
  "Le moteur R6 est STRICTEMENT réservé aux Urgences : n'interprète jamais un planning Service comme un planning Urgences.",
  '',
  'OBJECTIF',
  "Lire le PDF VISUELLEMENT, sans utiliser ni supposer la base des comptes GardeFlow.",
  "Reconstruire l'intégralité du tableau officiel, y compris les médecins qui ne sont pas inscrits dans l'application.",
  '',
  'RÈGLES ABSOLUES',
  "- N'invente jamais un nom, une date ou un créneau.",
  '- Lis toutes les pages utiles et toutes les cellules du tableau.',
  '- Jour / 08H-20H => urg-jour.',
  '- Nuit / 20H-08H => urg-nuit.',
  '- Une cellule réellement fusionnée Jour+Nuit => urg-24h.',
  '- Une cellule peut contenir plusieurs médecins : conserve chaque personne visible.',
  '- Pour CHAQUE médecin, sépare first_name et last_name. Conserve aussi full_name exactement tel que lu.',
  "- Ne décide jamais selon une liste d'utilisateurs : tu n'en disposes pas.",
  "- N'utilise jamais prénom seul, nom seul ou initiales comme identité complète.",
  '- Pour les prénoms/noms composés, conserve toutes les composantes visibles.',
  '- confidence de chaque médecin reflète la certitude sur son identité complète.',
  '- confidence globale reflète la certitude sur la lecture de TOUT le tableau.',
  '- Si une identité est partiellement illisible, baisse sa confidence et signale-le dans warnings.',
  '- Si un nom est rouge, ajoute full_name correspondant dans red_names.',
  "- Pour chaque date, retourne soit urg-24h, soit exactement urg-jour + urg-nuit, même si l'une des cellules est vide.",
  '- page_number est la page PDF où se trouve la cellule.',
  "- zone décrit brièvement la zone utile (ex. 'ligne 26 octobre / colonne Nuit').",
  '- Respecte les changements de mois et d’année.',
  "- document_scope='urgences' seulement si le document est clairement un planning officiel des Urgences.",
  "- document_scope='non_urgences' si le document concerne le Service ou un autre type de garde.",
  "- document_scope='mixed_or_uncertain' si le périmètre est mixte ou impossible à déterminer avec certitude.",
  "- PÉRIMÈTRE STRICT : ce moteur traite uniquement les gardes des URGENCES. N’interprète jamais une garde de Service comme une garde Urgences.",
  '- coverage_start et coverage_end sont les première et dernière dates OFFICIELLEMENT couvertes par tout le tableau visible, y compris les éventuels jours de débord avant/après le mois principal.',
  "- coverage_mode='full_month' uniquement si le document couvre explicitement tous les jours d’un mois civil principal ; sinon coverage_mode='explicit_range'.",
  "- En full_month, month/year désignent ce mois principal et sont obligatoires, même si le tableau affiche aussi quelques jours avant/après.",
  "- En explicit_range, month et year doivent être null : la plage officielle est uniquement coverage_start → coverage_end.",
].join('\n');

// La source visuelle A/B/C provient uniquement des octets officiels PDF.
// Les trois lectures sont indépendantes et restent exclusivement Urgences.
async function runRead(
  vision: GroqRosterVision,
  key: string,
  extraPrompt: string,
  _schemaName: string,
  modelEnv: string,
): Promise<Read> {
  const result = await vision.read(key, basePrompt + '\n\n' + extraPrompt, modelEnv);
  return normalizeExtraction(result);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const safeBuffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(safeBuffer).set(bytes);
  const digest = await crypto.subtle.digest('SHA-256', safeBuffer);
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

function hospitalForSlot(slot: string): string | null {
  if (slot === 'hm6_bouskoura') {
    return 'Hôpital Universitaire International Mohammed VI de Bouskoura';
  }
  if (slot === 'hm6_rabat') {
    return 'Hôpital Universitaire International Mohammed VI de Rabat';
  }
  if (slot === 'hck_casa') {
    return 'Hôpital Universitaire International Cheikh Khalifa de Casablanca';
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'method_not_allowed' }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const groqKey = Deno.env.get('GROQ_API_KEY');
    const authorization = req.headers.get('Authorization') ?? '';

    if (
      !supabaseUrl ||
      !anonKey ||
      !serviceRoleKey ||
      !authorization.startsWith('Bearer ')
    ) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }
    if (!groqKey) {
      return json({ ok: false, error: 'groq_not_configured' }, 503);
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerData, error: callerError } =
      await callerClient.auth.getUser();
    const callerId = callerData.user?.id;
    if (callerError || !callerId) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

    const { data: callerProfile } = await adminClient
      .from('profiles')
      .select('id,role,account_status')
      .eq('id', callerId)
      .maybeSingle();
    if (
      !callerProfile ||
      callerProfile.role !== 'admin' ||
      callerProfile.account_status !== 'active'
    ) {
      return json({ ok: false, error: 'forbidden' }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const manualResolutions = parseManualResolutions(body?.manualResolutions);
    const forceReread = body?.forceReread === true;
    const resourceId =
      typeof body?.resourceId === 'string' ? body.resourceId.trim() : '';
    const tempStoragePath =
      typeof body?.tempStoragePath === 'string'
        ? body.tempStoragePath.trim()
        : '';
    const verificationToken =
      typeof body?.verificationToken === 'string'
        ? body.verificationToken.trim()
        : '';
    const local = normalizeLocalEvidence(body?.localEvidence);

    let storagePath = '';
    let displayName = 'planning-officiel.pdf';
    let slot = '';
    let hospital = '';
    let resourceUpdatedAt = '';
    let cacheResourceId = '';

    if (/^[0-9a-f-]{36}$/i.test(resourceId)) {
      const { data: resource, error } = await adminClient
        .from('shared_resources')
        .select(
          'id,kind,slot,hospital,storage_path,display_name,mime_type,updated_at',
        )
        .eq('id', resourceId)
        .maybeSingle();
      if (
        error ||
        !resource ||
        resource.kind !== 'official_pdf' ||
        resource.mime_type !== 'application/pdf'
      ) {
        return json({ ok: false, error: 'resource_not_found' }, 404);
      }

      // Lecture 2 explicitement demandée : ne jamais retourner une ancienne
      // lecture alors que l'administrateur souhaite corriger son résultat.
      const cached = forceReread
        ? null
        : (await adminClient
            .from('official_roster_verified_reads')
            .select('extraction')
            .eq('resource_id', resource.id)
            .eq('resource_updated_at', resource.updated_at)
            .eq('parser_revision', PARSER_REVISION)
            .maybeSingle()).data;
      if (cached?.extraction?.verified === true) {
        return json({
          ok: true,
          cached: true,
          extraction: cached.extraction,
        });
      }

      storagePath = String(resource.storage_path);
      displayName = String(resource.display_name || displayName);
      slot = String(resource.slot || '');
      hospital = String(resource.hospital || hospitalForSlot(slot) || '');
      resourceUpdatedAt = String(resource.updated_at);
      cacheResourceId = String(resource.id);
    } else {
      slot = typeof body?.slot === 'string' ? body.slot.trim() : '';
      hospital = hospitalForSlot(slot) || '';
      displayName =
        typeof body?.displayName === 'string' && body.displayName.trim()
          ? body.displayName.trim()
          : displayName;
      const expectedPrefix = 'official_preflight/' + callerId + '/';
      if (
        !tempStoragePath ||
        !tempStoragePath.startsWith(expectedPrefix) ||
        !hospital
      ) {
        return json({ ok: false, error: 'invalid_preflight_resource' }, 400);
      }
      storagePath = tempStoragePath;
    }

    const { data: blob, error: downloadError } = await adminClient.storage
      .from('gardeflow-shared')
      .download(storagePath);
    if (downloadError || !blob) {
      console.error('Official PDF download failed', downloadError);
      return json({ ok: false, error: 'pdf_download_failed' }, 500);
    }

    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (bytes.length === 0 || bytes.length > 25 * 1024 * 1024) {
      return json({ ok: false, error: 'invalid_pdf_size' }, 400);
    }

    if (
      cacheResourceId &&
      /^[0-9a-f-]{36}$/i.test(verificationToken)
    ) {
      const nowIso = new Date().toISOString();
      const fileSha256 = await sha256Hex(bytes);
      const { data: preflight } = await adminClient
        .from('official_roster_preflight_reads')
        .select('id,slot,file_sha256,extraction,expires_at')
        .eq('id', verificationToken)
        .eq('owner_id', callerId)
        .gt('expires_at', nowIso)
        .maybeSingle();

      if (
        preflight &&
        preflight.slot === slot &&
        preflight.file_sha256 === fileSha256 &&
        preflight.extraction?.verified === true &&
        preflight.extraction?.parser_revision === PARSER_REVISION
      ) {
        const promotedExtraction = {
          ...preflight.extraction,
          engine:
            String(
              preflight.extraction?.engine ??
                'pdfrx_geometry+groq_vision_conditional',
            ) + '+sha256',
        };
        const { error: promoteError } = await adminClient
          .from('official_roster_verified_reads')
          .upsert(
            {
              resource_id: cacheResourceId,
              resource_updated_at: resourceUpdatedAt,
              parser_revision: PARSER_REVISION,
              engine: promotedExtraction.engine,
              extraction: promotedExtraction,
              confidence: promotedExtraction.confidence ?? 0,
              warnings: promotedExtraction.warnings ?? [],
              created_at: new Date().toISOString(),
            },
            {
              onConflict:
                'resource_id,resource_updated_at,parser_revision',
            },
          );
        if (!promoteError) {
          await adminClient
            .from('official_roster_preflight_reads')
            .delete()
            .eq('id', verificationToken)
            .eq('owner_id', callerId);
          return json({
            ok: true,
            cached: false,
            promoted: true,
            extraction: promotedExtraction,
          });
        }
        console.error('Verified preflight promotion failed', promoteError);
      }
    }

    const vision = await GroqRosterVision.fromPdf(bytes);
    {

      const useLocalA =
        local.validationErrors.length === 0 && local.cells.length > 0;
      let readAVisual: Read | null = null;
      if (!useLocalA) {
        readAVisual = await runRead(
          vision,
          groqKey,
          [
            'LECTURE A VISUELLE DE SECOURS.',
            'La couche texte/lecture géométrique locale est absente ou structurellement incomplète.',
            'Lis le document depuis zéro sans connaître les comptes GardeFlow.',
            'Utilise une stratégie de lecture globale par lignes puis colonnes et vérifie toutes les cellules.',
          ].join('\n'),
          'official_roster_read_a_fallback_r6',
          'GROQ_VISION_MODEL_A',
        );
      }

      const readB = await runRead(
        vision,
        groqKey,
        [
          'LECTURE B INDÉPENDANTE.',
          'Lis le document depuis zéro.',
          'Ne suppose aucune sortie de la lecture A.',
          'Utilise une stratégie centrée sur chaque date et chaque cellule, puis vérifie les identités complètes.',
          'Vérifie particulièrement chaque prénom, nom, date et créneau.',
        ].join('\n'),
        'official_roster_read_b_r6',
        'GROQ_VISION_MODEL_B',
      );

      const aReliable = useLocalA
        ? true
        : (readAVisual != null && readIsReliable(readAVisual));
      const bReliable = readIsReliable(readB);
      const abConflicts = useLocalA
        ? compareLocalVisual(local.cells, readB)
        : compareVisualReads(
            readAVisual!,
            readB,
            'a_b_mismatch',
          );

      let chosen: Read | null = null;
      let status = 'red';
      let agreement = 'none';
      let cExecuted = false;
      let conflicts = abConflicts;
      let readC: Read | null = null;

      if (aReliable && bReliable && abConflicts.length === 0) {
        chosen = readB;
        status = 'green';
        agreement = 'A=B';
      } else {
        cExecuted = true;
        const disputeSummary = JSON.stringify(
          abConflicts.slice(0, 30).map((conflict) => ({
            date: conflict.date,
            shift: conflict.shift,
            code: conflict.code,
            a: conflict.a,
            b: conflict.b,
          })),
        );
        readC = await runRead(
          vision,
          groqKey,
          [
            'LECTURE C CONDITIONNELLE — ARBITRAGE.',
            'Un désaccord ou un contrôle incomplet a été détecté entre A et B.',
            'Analyse en priorité les zones litigieuses ci-dessous.',
            'Si le désaccord semble structurel, si une date manque ou si une zone dépend du reste du tableau, relis tout le document.',
            'Ne choisis jamais par majorité aveugle : rends uniquement ce qui est réellement visible.',
            'Zones litigieuses: ' + disputeSummary,
          ].join('\n'),
          'official_roster_read_c_r6',
          'GROQ_VISION_MODEL_C',
        );

        const cReliable = readIsReliable(readC);
        const acConflicts = useLocalA
          ? compareLocalVisual(local.cells, readC)
          : compareVisualReads(
              readAVisual!,
              readC,
              'a_c_mismatch',
            );
        const bcConflicts = compareVisualReads(
          readB,
          readC,
          'b_c_mismatch',
        );

        if (aReliable && cReliable && acConflicts.length === 0) {
          chosen = readC;
          status = 'orange';
          agreement = 'A=C';
          conflicts = attachC(abConflicts, readC);
        } else if (bReliable && cReliable && bcConflicts.length === 0) {
          chosen = readC;
          status = 'orange';
          agreement = 'B=C';
          conflicts = attachC(abConflicts, readC);
        } else {
          status = 'red';
          agreement = 'none';
          conflicts = [
            ...attachC(abConflicts, readC),
            ...bcConflicts.map((conflict) => ({
              ...conflict,
              a: {},
              b: conflict.a,
              c: conflict.b,
            })),
          ];

          const manual = applyManualResolutions(
            readB,
            readC,
            conflicts,
            manualResolutions,
          );
          if (manual != null) {
            chosen = manual.read;
            conflicts = manual.conflicts;
            status = 'orange';
            agreement = 'ADMIN';
          }
        }
      }

      if (!chosen || status === 'red') {
        return json({
          ok: true,
          cached: false,
          extraction: {
            verified: false,
            parser_revision: PARSER_REVISION,
            engine: useLocalA
              ? 'pdfrx_geometry+groq_vision_conditional'
              : 'groq_vision_a+groq_vision_b+conditional_c',
            status: 'red',
            confidence: Math.min(
              minimumConfidence(readB),
              readC ? minimumConfidence(readC) : 1,
            ),
            agreement,
            hospital,
            slot,
            month: readC?.month ?? readB.month,
            year: readC?.year ?? readB.year,
            document_scope: readC?.document_scope ?? readB.document_scope,
            coverage_mode: readC?.coverage_mode ?? readB.coverage_mode,
            coverage_start: readC?.coverage_start ?? readB.coverage_start,
            coverage_end: readC?.coverage_end ?? readB.coverage_end,
            warnings: [
              ...new Set([
                ...readB.warnings,
                ...(readC?.warnings ?? []),
                'Ambiguïté persistante : publication automatique bloquée.',
              ]),
            ],
            rows: [],
            conflicts,
            validation_errors: [
              ...new Set([
                ...(useLocalA
                  ? local.validationErrors
                  : (readAVisual?.validationErrors ?? [])),
                ...readB.validationErrors,
                ...(readC?.validationErrors ?? []),
              ]),
            ],
            read_summary: {
              a_engine: useLocalA ? 'pdfrx_geometry' : 'groq_vision_fallback',
              a_cells: local.cells.length,
              a_confidence: readAVisual?.confidence ?? null,
              b_executed: true,
              b_confidence: readB.confidence,
              c_executed: cExecuted,
              c_confidence: readC?.confidence ?? null,
            },
          },
        });
      }

      const confidence =
        agreement === 'A=B' && readAVisual
          ? Math.min(
              minimumConfidence(readAVisual),
              minimumConfidence(readB),
            )
          : agreement === 'B=C' && readC
            ? Math.min(
                minimumConfidence(readB),
                minimumConfidence(readC),
              )
            : minimumConfidence(chosen);
      const extraction = {
        verified: true,
        parser_revision: PARSER_REVISION,
        engine: useLocalA
          ? 'pdfrx_geometry+groq_vision_conditional'
          : 'groq_vision_a+groq_vision_b+conditional_c',
        status,
        confidence,
        agreement,
        hospital,
        slot,
        month: chosen.month,
        year: chosen.year,
        document_scope: chosen.document_scope,
        coverage_mode: chosen.coverage_mode,
        coverage_start: chosen.coverage_start,
        coverage_end: chosen.coverage_end,
        warnings: agreement === 'ADMIN'
          ? [
              ...chosen.warnings,
              'Publication autorisée après correction humaine ciblée.',
            ]
          : chosen.warnings,
        rows: chosen.rows,
        conflicts,
        validation_errors: [],
        read_summary: {
          a_engine: useLocalA ? 'pdfrx_geometry' : 'groq_vision_fallback',
          a_cells: local.cells.length,
          a_confidence: readAVisual?.confidence ?? null,
          b_executed: true,
          b_confidence: readB.confidence,
          c_executed: cExecuted,
          c_confidence: readC?.confidence ?? null,
        },
      };

      if (cacheResourceId && resourceUpdatedAt) {
        const { error: cacheError } = await adminClient
          .from('official_roster_verified_reads')
          .upsert(
            {
              resource_id: cacheResourceId,
              resource_updated_at: resourceUpdatedAt,
              parser_revision: PARSER_REVISION,
              engine: extraction.engine,
              extraction,
              confidence: extraction.confidence,
              warnings: extraction.warnings,
              created_at: new Date().toISOString(),
            },
            {
              onConflict:
                'resource_id,resource_updated_at,parser_revision',
            },
          );
        if (cacheError) {
          console.error('Verified roster cache failed', cacheError);
          return json({ ok: false, error: 'cache_failed' }, 500);
        }
      }

      if (!cacheResourceId) {
        const fileSha256 = await sha256Hex(bytes);
        const { data: preflight, error: preflightError } = await adminClient
          .from('official_roster_preflight_reads')
          .insert({
            owner_id: callerId,
            slot,
            file_sha256: fileSha256,
            extraction,
            expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
          })
          .select('id')
          .single();
        if (preflightError || !preflight?.id) {
          console.error(
            'Verified preflight token creation failed',
            preflightError,
          );
          return json({ ok: false, error: 'preflight_cache_failed' }, 500);
        }
        return json({
          ok: true,
          cached: false,
          verificationToken: preflight.id,
          extraction,
        });
      }

      return json({ ok: true, cached: false, extraction });
    }
  } catch (error) {
    console.error('analyze-official-roster-pdf error', error);
    const code = error instanceof Error ? error.message : '';
    if (code === 'groq_rate_limited') {
      const retryAfter = error instanceof GroqRateLimitError
        ? error.retryAfterSeconds : null;
      return json({ ok: false, error: code, retry_after_seconds: retryAfter }, 429);
    }
    if (code === 'groq_authentication_failed') {
      return json({ ok: false, error: code }, 503);
    }
    if ([
      'groq_read_failed', 'groq_request_invalid', 'groq_invalid_response',
      'groq_pdf_render_failed', 'groq_invalid_page_reference',
      'groq_page_without_cells', 'groq_response_truncated',
    ].includes(code)) {
      return json({ ok: false, error: code }, 503);
    }
    return json({ ok: false, error: 'server_error' }, 500);
  }
});
