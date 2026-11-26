import { actor, decoders, request, type ApiResult, type Decoded, type Reader, orNull } from "@/api";
import {
  displayValue,
  schemaFieldReader,
  type FormValues,
  type SchemaField,
} from "@/features/changes/index.ts";

/** Contract: docs/apogee/api/setup.md, Settings (ST1), mission and organization. */
const { array, boolean, integer, nullable, object, optional, string, timestamp, token } = decoders;
const raw: Reader<unknown> = (value) => (value === undefined ? null : value);

const where = object({
  value: raw,
  // known: one new server value mustn't fail the whole settings read (ux, typing rules).
  source: optional(nullable(decoders.known(["mission", "organization", "default"] as const))),
  inherited_value: raw,
  /**
   * #233 (api): the values THIS viewer may choose, as the enum's own values; [] = the viewer can't
   * change it. Absent (fields that aren't governed) = no field-level limit.
   */
  allowed_values: optional(nullable(array(raw, 50))),
  /** #233, mission only: whether this viewer may clear the mission's value back to the organization's. */
  can_inherit: optional(nullable(boolean)),
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
  body: Readonly<{
    values: Readonly<Record<string, unknown>>;
    expected_version: number | null;
    /** #499: the digest of the grants the person saw this save suspend, to go ahead. */
    acknowledged_suspensions?: string;
  }>,
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
 * Where a section's values come from, for the section-level tag (ux 823e4f7a1) until per-field
 * overrides replace it. api's per-field storage (14455857d) lets one section mix sources, so any
 * field set for the mission makes the section "mission"; otherwise the first field that says.
 */
export type SectionSource = "mission" | "organization" | "default";
/** Only what the server says; null when no field says, or says something unrecognized (U20). */
export function sectionSource(s: SettingsSection): SectionSource | null {
  if (s.fields.some((f) => f.source === "mission")) return "mission";
  const src = s.fields.find((f) => f.source !== null && f.source !== undefined)?.source;
  return src === "organization" || src === "default" ? src : null;
}
/** The header tag, or null for no tag when the source is unknown. */
export function sectionTag(s: SettingsSection, scope: SettingsScope["kind"]): string | null {
  switch (sectionSource(s)) {
    case "mission":
      return "Set for this mission";
    case "organization":
      return scope === "mission" ? "Inherited from org" : "Set for this organization";
    case "default":
      return "Default";
    case null:
      return null;
  }
}

/**
 * ux (SettingsAuditProviders.md › Settings, per field): at mission scope each field carries its own
 * source tag, like a profile override (P3). Null when the server doesn't say (U20).
 */
export function fieldTag(f: SettingsField): string | null {
  switch (f.source) {
    case "mission":
      return "Set for this mission";
    case "organization":
      return "Inherited from org";
    case "default":
      return "Default";
    // No tag when the server doesn't say, or says something this console doesn't know yet.
    case "unrecognized":
    case null:
    case undefined:
      return null;
  }
}

/** ux: a Reset's outcome keeps the old value so it can be put back. */
export function resetLine(f: SettingsField, version: number): string {
  return `${f.label} follows the organization again (was ${valueText(f)}). Saved as v${version}.`;
}

/** ux: governance and approval fields confirm a Reset (the director treats them as explicit). */
export const confirmsReset = (sectionKey: string) => sectionKey === "cadence.governance";
export function resetConfirm(f: SettingsField, orgName: string): string {
  return `${f.label} will follow ${orgName}: ${valueText(f, f.inherited_value)}.`;
}

/** The mission section header: how many fields are set here, or null for none (ux). */
export function setHereCount(s: Pick<SettingsSection, "fields">): string | null {
  const n = s.fields.filter((f) => f.source === "mission").length;
  return n > 0 ? `${n} set for this mission` : null;
}

/** Form text for each field's effective value. */
export function initialValues(s: Pick<SettingsSection, "fields">): FormValues {
  const values: FormValues = {};
  for (const f of s.fields)
    values[f.path] = f.value === null || f.value === undefined ? "" : displayValue(f, f.value);
  return values;
}
