import { actor, decoders, request, type ApiResult, type Decoded, type Reader, orNull } from "@/api";
import {
  displayValue,
  schemaFieldReader,
  type FormValues,
  type SchemaField,
} from "@/features/changes/index.ts";

/** Contract: docs/apogee/api/setup.md, Settings (ST1), mission and organization. */
const { array, boolean, integer, nullable, object, oneOf, optional, string, timestamp, token } =
  decoders;
const raw: Reader<unknown> = (value) => (value === undefined ? null : value);

const where = object({
  value: raw,
  source: optional(nullable(oneOf(["mission", "organization", "default"]))),
  inherited_value: raw,
});
/** A kind-schema field plus its effective value and where that value comes from. */
const field: Reader<SchemaField & Decoded<typeof where>> = (value, path = "") => ({
  ...schemaFieldReader(value, path),
  ...where(value, path),
});
export type SettingsField = Decoded<typeof field>;

const section = object({
  key: token,
  title: string,
  purpose: nullable(string),
  fields: array(field, 200),
  locked: optional(boolean),
  version: nullable(object({ version: integer, at: timestamp, actor: orNull(actor) })),
});
export type SettingsSection = Decoded<typeof section>;
export const settingsReader = object({
  sections: array(section, 50),
  permissions: array(token, 50),
});
export type Settings = Decoded<typeof settingsReader>;

export type SettingsScope = Readonly<
  { kind: "mission"; id: string } | { kind: "organization"; id: string }
>;
const base = (scope: SettingsScope) =>
  `/${scope.kind === "mission" ? "missions" : "organizations"}/${encodeURIComponent(scope.id)}/settings`;

export function fetchSettings(
  scope: SettingsScope,
  signal: AbortSignal,
): Promise<ApiResult<Settings>> {
  return request(base(scope), settingsReader, { signal });
}

/** Saves directly (201, active). For a mission, a null value inherits that field. */
export function saveSection(
  scope: SettingsScope,
  key: string,
  body: Readonly<{ values: Readonly<Record<string, unknown>>; expected_version: number | null }>,
): Promise<ApiResult<{ version: number }>> {
  return request(`${base(scope)}/${encodeURIComponent(key)}`, object({ version: integer }), {
    method: "PUT",
    body,
  });
}

export function valueText(f: SettingsField, v: unknown = f.value): string {
  if (v === null || v === undefined) return "Not set";
  if (f.type === "enum")
    return (
      f.enum?.find((o) => JSON.stringify(o.value) === JSON.stringify(v))?.label ??
      displayValue(f, v)
    );
  if (f.type === "boolean") return v === true ? "Yes" : "No";
  const text = displayValue(f, v);
  return f.unit && !["s", "micros", "ratio"].includes(f.unit) ? `${text} ${f.unit}` : text;
}

/**
 * Where a section's values come from (ux 823e4f7a1: section-level overrides). The server overrides a
 * whole section, so every field shares one source; the tag sits on the section header.
 */
export type SectionSource = "mission" | "organization" | "default";
export function sectionSource(s: SettingsSection): SectionSource {
  const src = s.fields.find((f) => f.source)?.source;
  return src === "mission" ? "mission" : src === "organization" ? "organization" : "default";
}
export function sectionTag(s: SettingsSection, scope: SettingsScope["kind"]): string {
  const src = sectionSource(s);
  if (src === "mission") return "Set for this mission";
  if (src === "organization")
    return scope === "mission" ? "Inherited from org" : "Set for this organization";
  return "Default";
}

/** Form text for each field's effective value. */
export function initialValues(s: SettingsSection): FormValues {
  const values: FormValues = {};
  for (const f of s.fields)
    values[f.path] = f.value === null || f.value === undefined ? "" : displayValue(f, f.value);
  return values;
}
