import { decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";
import {
  schemaFieldReader,
  toValue,
  visible,
  type FormValues,
  type SchemaField,
} from "@/features/changes/index.ts";

/** Contract: docs/apogee/api/scheduling.md "Templates (CP3)" + GET /templates/schema. */
const { array, boolean, integer, nullable, object, string, token } = decoders;
const doc: Reader<Readonly<Record<string, unknown>>> = (value, path = "") => {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    throw new decoders.DecodeError(path, "object");
  // Sound: a plain JSON object; read through the schema's paths.
  return value as Readonly<Record<string, unknown>>;
};

export const templateSchemaReader = (value: unknown, path = "") => {
  const r = object({ fields: array(schemaFieldReader, 500), defaults: nullable(doc) })(value, path);
  const meta = object({
    fields: array(object({ path: string, group: token, advanced: boolean }), 500),
  })(value, path).fields;
  return { ...r, meta };
};
export type TemplateSchema = ReturnType<typeof templateSchemaReader>;

const base = (missionId: string) =>
  `/missions/${encodeURIComponent(missionId)}/contact-planning/templates`;

export function fetchTemplateSchema(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<TemplateSchema>> {
  return request(`${base(missionId)}/schema`, templateSchemaReader, { signal });
}

export type Target =
  | Readonly<{ kind: "profile"; spacecraft_type_id: string }>
  | Readonly<{ kind: "plane"; plane: number }>
  | Readonly<{ kind: "spacecraft_ids"; spacecraft_ids: readonly string[] }>;

export const previewReader = object({
  spacecraft_count: integer,
  occurrences: integer,
  contacts: integer,
  contacts_per_day: nullable(decoders.number),
  warnings: array(object({ code: token }), 20),
});
export type TemplatePreview = Decoded<typeof previewReader>;

export function previewTemplate(
  missionId: string,
  body: Readonly<{ target: Target; document: unknown; days?: number }>,
  signal: AbortSignal,
) {
  return request(`${base(missionId)}/preview`, previewReader, { method: "POST", body, signal });
}

export function saveTemplate(
  missionId: string,
  id: string | null,
  body: Readonly<{ name: string; target: Target; document: unknown; expected_version?: number }>,
) {
  return request(
    id ? `${base(missionId)}/${encodeURIComponent(id)}` : base(missionId),
    object({ id: token, version: integer }),
    {
      method: "POST",
      body,
    },
  );
}

/** Read a dotted path from a nested document. */
export function readPath(doc: unknown, path: string): unknown {
  return path
    .split(".")
    .reduce<unknown>(
      (at, key) =>
        at !== null && typeof at === "object" && !Array.isArray(at)
          ? (at as Record<string, unknown>)[key]
          : undefined,
      doc,
    );
}

/**
 * The nested document from form values over any depth of dotted paths, starting from `base` (the
 * template's current document or the server defaults) so fields the form doesn't show carry over.
 */
export function buildNested(
  fields: readonly SchemaField[],
  values: FormValues,
  base: unknown,
): Readonly<
  { ok: true; document: Record<string, unknown> } | { ok: false; errors: Record<string, string> }
> {
  const document = structuredClone((base ?? {}) as Record<string, unknown>);
  const errors: Record<string, string> = {};
  for (const f of fields) {
    // Hidden fields (visible_when false) carry over from `base` unchecked.
    if (!visible(f, values)) continue;
    const checked = toValue(f, values[f.path] ?? "");
    if (!checked.ok) {
      errors[f.path] = checked.message;
      continue;
    }
    const keys = f.path.split(".");
    let at = document;
    for (const k of keys.slice(0, -1)) {
      const next = at[k];
      at = (at[k] =
        next !== null && typeof next === "object" && !Array.isArray(next) ? next : {}) as Record<
        string,
        unknown
      >;
    }
    at[keys.at(-1) ?? f.path] = checked.value;
  }
  return Object.keys(errors).length > 0 ? { ok: false, errors } : { ok: true, document };
}

export const warningText: Readonly<Record<string, string>> = {
  applies_to_nobody: "This target matches no spacecraft right now.",
  excluded_outside_target: "Some excluded spacecraft aren't in the target anyway.",
};
