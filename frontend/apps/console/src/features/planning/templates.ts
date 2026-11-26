import type { MissionId } from "@/api/index.ts";
import {
  decoders,
  getAt,
  isRecord,
  jsonObject,
  request,
  setAt,
  type ApiResult,
  type Decoded,
  type Reader,
  type JsonObject,
} from "@/api";
import {
  displayValue,
  schemaFieldReader,
  toValue,
  visible,
  type FormValues,
  type SchemaField,
} from "@/features/changes/index.ts";

/** Contract: docs/apogee/api/scheduling.md "Templates (CP3)" + GET /templates/schema. */
const { array, boolean, integer, nullable, object, string, token } = decoders;
const doc: Reader<JsonObject> = jsonObject;

export const templateSchemaReader = (value: unknown, path = "") => {
  const r = object({ fields: array(schemaFieldReader, 500), defaults: nullable(doc) })(value, path);
  const meta = object({
    fields: array(object({ path: string, group: token, advanced: boolean }), 500),
  })(value, path).fields;
  return { ...r, meta };
};
export type TemplateSchema = ReturnType<typeof templateSchemaReader>;

const base = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/contact-planning/templates`;

export function fetchTemplateSchema(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<TemplateSchema>> {
  return request(`${base(missionId)}/schema`, templateSchemaReader, { signal });
}

export type Target =
  | Readonly<{ kind: "profile"; spacecraft_type_id: string }>
  | Readonly<{ kind: "plane"; plane: number }>
  | Readonly<{ kind: "spacecraft_ids"; spacecraft_ids: readonly string[] }>;

/** Template preview warnings (api CP3). */
export const previewWarnings = ["applies_to_nobody", "excluded_outside_target"] as const;
export const previewReader = object({
  spacecraft_count: integer,
  occurrences: integer,
  contacts: integer,
  contacts_per_day: nullable(decoders.number),
  warnings: array(object({ code: decoders.knownText(previewWarnings) }), 20),
});
export type TemplatePreview = Decoded<typeof previewReader>;

export function previewTemplate(
  missionId: MissionId,
  body: Readonly<{ target: Target; document: unknown; days?: number }>,
  signal: AbortSignal,
) {
  return request(`${base(missionId)}/preview`, previewReader, { method: "POST", body, signal });
}

export function saveTemplate(
  missionId: MissionId,
  id: string | null,
  body: Readonly<{
    name: string;
    target: Target;
    document: unknown;
    expected_version?: number;
    /** Creates only: one per form open, reused on retry (api 66875fb39). */
    operation_id?: string;
  }>,
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
  const document: Record<string, unknown> = isRecord(base) ? structuredClone(base) : {};
  const errors: Record<string, string> = {};
  for (const f of fields) {
    // Hidden fields (visible_when false) carry over from `base` unchecked.
    if (!visible(f, values)) continue;
    const checked = toValue(f, values[f.path] ?? "");
    if (!checked.ok) {
      errors[f.path] = checked.message;
      continue;
    }
    setAt(document, f.path, checked.value);
  }
  return Object.keys(errors).length > 0 ? { ok: false, errors } : { ok: true, document };
}

export const warningWords: Readonly<Record<(typeof previewWarnings)[number], string>> = {
  applies_to_nobody: "This target matches no spacecraft right now.",
  excluded_outside_target: "Some excluded spacecraft aren't in the target anyway.",
};
/** A preview warning in words, or the server's own code for one the console doesn't know. */
export const warningText = (w: TemplatePreview["warnings"][number]["code"]) =>
  decoders.vocabularyText(w, warningWords);

/**
 * The template page's max-gap fact (#74, domain e99fe3830): the schema field's own label and unit, as
 * on the requirement page; an empty limit reads "No limit" (ux P4). Null until the schema is read.
 */
export function maxGapFact(
  fields: readonly SchemaField[] | null,
  document: unknown,
): Readonly<{ key: string; label: string; value: string; mono: boolean }> | null {
  // compared-as-text: a schema field path, an open set the server's schema defines
  const f = fields?.find((x) => x.path === "requirement.max_gap_seconds");
  if (!f) return null;
  const v = getAt(document, f.path);
  return v === null || v === undefined
    ? { key: f.path, label: f.label, value: "No limit", mono: false }
    : { key: f.path, label: f.label, value: displayValue(f, v), mono: true };
}
