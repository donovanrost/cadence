import type { MissionId } from "@/api/index.ts";
import { decoders, pathGet, request, type ApiResult, type Decoded, type Reader } from "@/api";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:id/config/kinds/:kind/schema`. */
const { array, boolean, nullable, number, object, optional, string, token } = decoders;

const raw: Reader<unknown> = (value) => (value === undefined ? null : value);

const condition = object({ path: string, equals: raw });
const allConditions = object({ all: array(condition, 20) });
/** One condition, or (U83, a transport's listener) `{all: [...]}`: shown when every one holds. */
const visibleWhen: Reader<Decoded<typeof condition> | Decoded<typeof allConditions>> = (
  value,
  path = "",
) =>
  typeof value === "object" && value !== null && Object.hasOwn(value, "all")
    ? allConditions(value, path)
    : condition(value, path);

export const schemaFieldReader = object({
  path: string,
  label: string,
  // known, not oneOf (lead): a new field type reads as text instead of failing the whole schema.
  type: decoders.known([
    "integer",
    "number",
    "boolean",
    "enum",
    "string",
    // api fa7e9e463: multi-line text (a derived point's expression).
    "text",
    "reference",
    "datetime",
    "time",
    "list",
    // domain (comms parity 4): a JSON object (a ground station's metadata); default {}.
    "json",
  ] as const),
  unit: nullable(string),
  enum: nullable(array(object({ value: raw, label: string }), 200)),
  range: nullable(object({ min: optional(nullable(number)), max: optional(nullable(number)) })),
  default: raw,
  required: boolean,
  help: nullable(string),
  visible_when: nullable(visibleWhen),
  pattern: optional(nullable(string)),
  /** api fa7e9e463: set on create only (a derived point's id); the edit form leaves it out. */
  create_only: optional(boolean),
});
export const kindSchemaReader = object({
  // free-text: the schema's own kind name, echoed back; templates, requirements and settings build theirs locally.
  kind: token,
  fields: array(schemaFieldReader, 500),
});
export type KindSchema = Decoded<typeof kindSchemaReader>;
export type SchemaField = Decoded<typeof schemaFieldReader>;
export type EditableKind = "ground_station" | "transport" | "spacecraft_profile" | "spacecraft";

export function fetchKindSchema(
  key: Readonly<{ missionId: MissionId; kind: EditableKind }>,
  signal: AbortSignal,
): Promise<ApiResult<KindSchema>> {
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/config/kinds/${key.kind}/schema`,
    kindSchemaReader,
    { signal },
  );
}

/** Form values are kept as text per path; `toValue` converts on stage. */
export type FormValues = Record<string, string>;

export function fromDocument(
  schema: KindSchema,
  doc: Readonly<Record<string, unknown>>,
): FormValues {
  const values: FormValues = {};
  for (const f of schema.fields) {
    const v = pathGet(doc, f.path.split("."));
    values[f.path] = v === null || v === undefined ? "" : displayValue(f, v);
  }
  return values;
}

/**
 * ux 11-16, create forms only: a REQUIRED field starts on its schema default, or on the only
 * option of a one-option enum, and is staged explicitly. Optional fields stay empty (empty means
 * inherit the default), and edit forms are untouched.
 */
export function createDefaults(schema: KindSchema, values: FormValues): FormValues {
  const out: FormValues = { ...values };
  for (const f of schema.fields) {
    if (!f.required || (out[f.path] ?? "") !== "") continue;
    const only = f.type === "enum" && f.enum?.length === 1 ? f.enum[0] : undefined;
    const preset = f.default !== null && f.default !== undefined ? f.default : only?.value;
    if (preset !== null && preset !== undefined) out[f.path] = displayValue(f, preset);
  }
  return out;
}

/**
 * The schema units the console formats itself (U24): seconds as durations, micros as currency
 * units, ratio as a percent. Units are otherwise open display text from the server's schema, so
 * this maps the text to the few the console knows once; anything else is shown as sent.
 */
const formattedUnits = ["s", "micros", "ratio"] as const;
type FormattedUnit = (typeof formattedUnits)[number];
export const formattedUnit = (f: Readonly<{ unit: string | null }>): FormattedUnit | null =>
  formattedUnits.find((u) => u === f.unit) ?? null;

/** U24: format by schema unit (seconds as durations, micros as currency units). */
export function displayValue(f: SchemaField, v: unknown): string {
  if (f.type === "json") return JSON.stringify(v, null, 2);
  if (typeof v === "number" && formattedUnit(f) === "s") return formatSeconds(v);
  if (typeof v === "boolean") return v ? "true" : "false";
  if (Array.isArray(v))
    return v.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join(", ");
  if (typeof v === "number" && formattedUnit(f) === "micros") return (v / 1_000_000).toFixed(2);
  if (typeof v === "number" && formattedUnit(f) === "ratio") return `${trimNumber(v * 100)}%`;
  return typeof v === "string" ? v : JSON.stringify(v);
}

export function formatSeconds(total: number): string {
  const d = Math.floor(total / 86_400);
  const h = Math.floor((total % 86_400) / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const hh = d * 24 + h;
  if (s !== 0) return `${hh}h ${String(m).padStart(2, "0")}m ${String(s).padStart(2, "0")}s`;
  return `${hh}h ${String(m).padStart(2, "0")}m`;
}

/** "48h", "2d", "90m", "1d 6h", "48h 00m", "45s" or plain seconds → seconds; null if not a duration. */
export function parseDuration(text: string): number | null {
  const t = text.trim().toLowerCase();
  if (/^\d+$/.test(t)) return Number(t);
  const parts = [...t.matchAll(/(\d+)\s*([dhms])/g)];
  if (
    parts.length === 0 ||
    parts
      .map((p) => p[0])
      .join("")
      .replace(/\s/g, "") !== t.replace(/\s/g, "")
  )
    return null;
  const scale = { d: 86_400, h: 3600, m: 60, s: 1 } as const;
  const unitSeconds = (u: string | undefined): number =>
    u === "d" || u === "h" || u === "m" || u === "s" ? scale[u] : 0;
  return parts.reduce((sum, p) => sum + Number(p[1]) * unitSeconds(p[2]), 0);
}

export function visible(f: SchemaField, values: FormValues): boolean {
  const when = f.visible_when;
  if (!when) return true;
  return ("all" in when ? when.all : [when]).every(
    (c) => values[c.path] === (typeof c.equals === "string" ? c.equals : JSON.stringify(c.equals)),
  );
}

export type FieldCheck = Readonly<{ ok: true; value: unknown } | { ok: false; message: string }>;

/** Text → typed value, with the schema's own required/range rules (the server re-validates). */
export function toValue(f: SchemaField, text: string): FieldCheck {
  const t = text.trim();
  if (f.type === "json") return toObject(f, t);
  if (t === "")
    return f.required
      ? { ok: false, message: `${f.label} is required.` }
      : { ok: true, value: null };
  switch (f.type) {
    case "integer": {
      let n: number;
      if (formattedUnit(f) === "s") {
        const secs = parseDuration(t);
        if (secs === null)
          return { ok: false, message: `${f.label}: write a duration like 48h, 2d or 90m.` };
        n = secs;
      } else if (formattedUnit(f) === "micros") {
        if (!/^\d+(\.\d{1,6})?$/.test(t))
          return { ok: false, message: `${f.label}: write an amount like 1250.00.` };
        n = Math.round(Number(t) * 1_000_000);
      } else {
        if (!/^-?\d+$/.test(t)) return { ok: false, message: `${f.label} must be a whole number.` };
        n = Number(t);
      }
      const bound = (b: number) =>
        formattedUnit(f) === "s"
          ? formatSeconds(b)
          : formattedUnit(f) === "micros"
            ? (b / 1_000_000).toFixed(2)
            : String(b);
      if (f.range?.min != null && n < f.range.min)
        return { ok: false, message: `${f.label} is at least ${bound(f.range.min)}.` };
      if (f.range?.max != null && n > f.range.max)
        return { ok: false, message: `${f.label} is at most ${bound(f.range.max)}.` };
      return { ok: true, value: n };
    }
    case "number":
      return toNumber(f, t);
    case "boolean":
      return { ok: true, value: t === "true" };
    case "enum": {
      const option = f.enum?.find(
        (o) => (typeof o.value === "string" ? o.value : JSON.stringify(o.value)) === t,
      );
      return option
        ? { ok: true, value: option.value }
        : { ok: false, message: `Choose a ${f.label.toLowerCase()}.` };
    }
    case "datetime": {
      const ms = Date.parse(t);
      return Number.isNaN(ms) || !/T|\s/.test(t)
        ? { ok: false, message: `${f.label}: write a UTC time like 2026-11-12T06:00:00Z.` }
        : { ok: true, value: new Date(ms).toISOString().replace(".000Z", "Z") };
    }
    case "time":
      return /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(t)
        ? { ok: true, value: t.length === 5 ? `${t}:00` : t }
        : { ok: false, message: `${f.label}: write a UTC time of day like 06:30.` };
    case "list":
      return {
        ok: true,
        value: t
          .split(",")
          .map((x) => x.trim())
          .filter(Boolean),
      };
    case "string":
    case "text":
    case "reference":
    case "unrecognized":
      if (f.pattern && !safeTest(f.pattern, t))
        return { ok: false, message: `${f.label} doesn't match the required format.` };
      if (f.range?.max != null && t.length > f.range.max)
        return { ok: false, message: `${f.label} is at most ${f.range.max} characters.` };
      return { ok: true, value: t };
  }
}

/** A `json` field holds one JSON object; empty means `{}` (the kind's default). */
function toObject(f: SchemaField, t: string): FieldCheck {
  if (t === "") return { ok: true, value: {} };
  const bad = {
    ok: false,
    message: `${f.label} must be a JSON object, like {"site": "north"}.`,
  } as const;
  try {
    const parsed: unknown = JSON.parse(t);
    return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
      ? { ok: true, value: parsed }
      : bad;
  } catch {
    return bad;
  }
}

export type Edits =
  | Readonly<{ ok: true; changes: readonly Readonly<{ path: string; value: unknown }>[] }>
  | Readonly<{ ok: false; errors: Readonly<Record<string, string>> }>;

/** Changed, visible fields as change-set `changes`, or the per-field problems. */
export function diffEdits(schema: KindSchema, before: FormValues, after: FormValues): Edits {
  const errors: Record<string, string> = {};
  const changes: { path: string; value: unknown }[] = [];
  for (const f of schema.fields) {
    if (!visible(f, after)) continue;
    const checked = toValue(f, after[f.path] ?? "");
    if (!checked.ok) errors[f.path] = checked.message;
    else if ((after[f.path] ?? "") !== (before[f.path] ?? ""))
      changes.push({ path: f.path, value: checked.value });
  }
  return Object.keys(errors).length > 0 ? { ok: false, errors } : { ok: true, changes };
}

/** Decimal fields; `ratio` is written as a percent ("95%" or "95") and stored as 0.95. */
function toNumber(f: SchemaField, t: string): FieldCheck {
  const ratio = formattedUnit(f) === "ratio";
  const text = ratio ? t.replace(/%$/, "").trim() : t;
  if (!/^-?\d+(\.\d+)?$/.test(text))
    return { ok: false, message: `${f.label}: write a number${ratio ? " like 95%" : ""}.` };
  const n = ratio ? Number(text) / 100 : Number(text);
  const shown = (b: number) => (ratio ? `${trimNumber(b * 100)}%` : String(b));
  if (f.range?.min != null && n < f.range.min)
    return { ok: false, message: `${f.label} is at least ${shown(f.range.min)}.` };
  if (f.range?.max != null && n > f.range.max)
    return { ok: false, message: `${f.label} is at most ${shown(f.range.max)}.` };
  return { ok: true, value: n };
}

/** 95.00000000000001 → "95"; keeps up to 4 decimals. */
function trimNumber(n: number): string {
  return String(Math.round(n * 10_000) / 10_000);
}

/** Server patterns are hints; an unparsable one never blocks (the server re-validates). */
function safeTest(pattern: string, text: string): boolean {
  try {
    return new RegExp(pattern).test(text);
  } catch {
    return true;
  }
}

/**
 * ux (percent fields): a percent typed as a fraction (0.9 for 90%). Shown inline as a caution, with
 * a one-tap fix; Save stays enabled, so 0.9% can still be meant. Null when it doesn't apply.
 */
export function ratioSlip(
  f: SchemaField,
  text: string,
): Readonly<{ line: string; fix: string; label: string }> | null {
  if (formattedUnit(f) !== "ratio") return null;
  const t = text.trim();
  if (!/^\d*\.?\d+$/.test(t)) return null;
  const n = Number(t);
  if (!(n > 0 && n <= 1)) return null;
  const fix = trimNumber(n * 100);
  return { line: `That's ${t}%. Did you mean ${fix}%?`, fix, label: `Use ${fix}%` };
}
