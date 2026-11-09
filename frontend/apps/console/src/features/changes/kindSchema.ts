import { decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:id/config/kinds/:kind/schema`. */
const { array, boolean, nullable, number, object, oneOf, optional, string, token } = decoders;

const raw: Reader<unknown> = (value) => (value === undefined ? null : value);

export const schemaFieldReader = object({
  path: string,
  label: string,
  type: oneOf(["integer", "boolean", "enum", "string", "reference"]),
  unit: nullable(string),
  enum: nullable(array(object({ value: raw, label: string }), 200)),
  range: nullable(object({ min: optional(nullable(number)), max: optional(nullable(number)) })),
  default: raw,
  required: boolean,
  help: nullable(string),
  visible_when: nullable(object({ path: string, equals: raw })),
  pattern: optional(nullable(string)),
});
export const kindSchemaReader = object({ kind: token, fields: array(schemaFieldReader, 500) });
export type KindSchema = Decoded<typeof kindSchemaReader>;
export type SchemaField = Decoded<typeof schemaFieldReader>;
export type EditableKind = "ground_station" | "transport";

export function fetchKindSchema(
  key: Readonly<{ missionId: string; kind: EditableKind }>,
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
    const v = f.path
      .split(".")
      .reduce<unknown>(
        (at, key) =>
          at !== null && typeof at === "object" ? (at as Record<string, unknown>)[key] : undefined,
        doc,
      );
    values[f.path] = v === null || v === undefined ? "" : displayValue(f, v);
  }
  return values;
}

/** U24: format by schema unit (seconds as durations, micros as currency units). */
export function displayValue(f: SchemaField, v: unknown): string {
  if (typeof v === "number" && f.unit === "s") return formatSeconds(v);
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number" && f.unit === "micros") return (v / 1_000_000).toFixed(2);
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
  return parts.reduce((sum, p) => sum + Number(p[1]) * scale[p[2] as keyof typeof scale], 0);
}

export function visible(f: SchemaField, values: FormValues): boolean {
  if (!f.visible_when) return true;
  const want = f.visible_when.equals;
  return values[f.visible_when.path] === (typeof want === "string" ? want : JSON.stringify(want));
}

export type FieldCheck = Readonly<{ ok: true; value: unknown } | { ok: false; message: string }>;

/** Text → typed value, with the schema's own required/range rules (the server re-validates). */
export function toValue(f: SchemaField, text: string): FieldCheck {
  const t = text.trim();
  if (t === "")
    return f.required
      ? { ok: false, message: `${f.label} is required.` }
      : { ok: true, value: null };
  switch (f.type) {
    case "integer": {
      let n: number;
      if (f.unit === "s") {
        const secs = parseDuration(t);
        if (secs === null)
          return { ok: false, message: `${f.label}: write a duration like 48h, 2d or 90m.` };
        n = secs;
      } else if (f.unit === "micros") {
        if (!/^\d+(\.\d{1,6})?$/.test(t))
          return { ok: false, message: `${f.label}: write an amount like 1250.00.` };
        n = Math.round(Number(t) * 1_000_000);
      } else {
        if (!/^-?\d+$/.test(t)) return { ok: false, message: `${f.label} must be a whole number.` };
        n = Number(t);
      }
      const bound = (b: number) =>
        f.unit === "s"
          ? formatSeconds(b)
          : f.unit === "micros"
            ? (b / 1_000_000).toFixed(2)
            : String(b);
      if (f.range?.min != null && n < f.range.min)
        return { ok: false, message: `${f.label} is at least ${bound(f.range.min)}.` };
      if (f.range?.max != null && n > f.range.max)
        return { ok: false, message: `${f.label} is at most ${bound(f.range.max)}.` };
      return { ok: true, value: n };
    }
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
    case "string":
    case "reference":
      if (f.pattern && !safeTest(f.pattern, t))
        return { ok: false, message: `${f.label} doesn't match the required format.` };
      if (f.range?.max != null && t.length > f.range.max)
        return { ok: false, message: `${f.label} is at most ${f.range.max} characters.` };
      return { ok: true, value: t };
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

/** Server patterns are hints; an unparsable one never blocks (the server re-validates). */
function safeTest(pattern: string, text: string): boolean {
  try {
    return new RegExp(pattern).test(text);
  } catch {
    return true;
  }
}
