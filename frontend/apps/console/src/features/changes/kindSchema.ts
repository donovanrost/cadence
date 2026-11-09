import { decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:id/config/kinds/:kind/schema`. */
const { array, boolean, nullable, number, object, oneOf, optional, string, token } = decoders;

const raw: Reader<unknown> = (value) => (value === undefined ? null : value);

const field = object({
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
});
export const kindSchemaReader = object({ kind: token, fields: array(field, 500) });
export type KindSchema = Decoded<typeof kindSchemaReader>;
export type SchemaField = Decoded<typeof field>;
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
    values[f.path] =
      v === null || v === undefined ? "" : typeof v === "string" ? v : JSON.stringify(v);
  }
  return values;
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
      if (!/^-?\d+$/.test(t)) return { ok: false, message: `${f.label} must be a whole number.` };
      const n = Number(t);
      if (f.range?.min != null && n < f.range.min)
        return { ok: false, message: `${f.label} is at least ${f.range.min}.` };
      if (f.range?.max != null && n > f.range.max)
        return { ok: false, message: `${f.label} is at most ${f.range.max}.` };
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
