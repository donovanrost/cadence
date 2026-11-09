import { decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";
import { formatCount } from "@/ui";

/** Requested shape: docs/apogee/plans/setup-shapes.md §ST1 (mission and organization). */
const { array, nullable, object, oneOf, string, timestamp, token, integer } = decoders;
const raw: Reader<unknown> = (value) => (value === undefined ? null : value);

const field = object({
  path: string,
  label: string,
  type: oneOf(["integer", "boolean", "enum", "string", "reference"]),
  unit: nullable(string),
  enum: nullable(array(object({ value: raw, label: string }), 200)),
  help: nullable(string),
  value: raw,
  source: oneOf(["mission", "organization", "default"]),
  inherited_value: raw,
});
export const settingsReader = object({
  sections: array(
    object({ key: token, title: string, purpose: nullable(string), fields: array(field, 200) }),
    50,
  ),
  version: nullable(
    object({ version: integer, at: timestamp, actor: nullable(object({ name: string })) }),
  ),
  permissions: array(token, 50),
});
export type Settings = Decoded<typeof settingsReader>;
export type SettingsField = Decoded<typeof field>;

export type SettingsScope = Readonly<
  { kind: "mission"; id: string } | { kind: "organization"; id: string }
>;

export function fetchSettings(
  scope: SettingsScope,
  signal: AbortSignal,
): Promise<ApiResult<Settings>> {
  const base = scope.kind === "mission" ? "missions" : "organizations";
  return request(`/${base}/${encodeURIComponent(scope.id)}/settings`, settingsReader, { signal });
}

export function valueText(f: SettingsField): string {
  const v = f.value;
  if (v === null) return "Not set";
  if (f.type === "enum")
    return (
      f.enum?.find((o) => o.value === v)?.label ?? (typeof v === "string" ? v : JSON.stringify(v))
    );
  if (f.type === "boolean") return v === true ? "Yes" : "No";
  const text =
    typeof v === "number" ? formatCount(v) : typeof v === "string" ? v : JSON.stringify(v);
  return f.unit ? `${text} ${f.unit}` : text;
}

export function sourceLabel(f: SettingsField, scope: SettingsScope["kind"]): string {
  if (f.source === "default") return "Default";
  if (f.source === "organization")
    return scope === "mission" ? "Inherited from org" : "Set for this organization";
  return "Set for this mission";
}
