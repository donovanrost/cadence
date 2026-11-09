import { decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";
import { formatCount } from "@/ui";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:mission_id/profiles/:profile_id`. */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

const raw: Reader<unknown> = (value) => (value === undefined ? null : value);
const enumValue = object({ value: token, label: string });

const field = object({
  path: string,
  label: string,
  type: oneOf(["integer", "boolean", "enum", "string", "reference"]),
  unit: nullable(string),
  enum: nullable(array(object({ value: raw, label: string }), 200)),
  range: nullable(object({ min: nullable(decoders.number), max: nullable(decoders.number) })),
  default: raw,
  overridable: boolean,
  runtime_impact: oneOf(["generation", "routes", "none"]),
  help: nullable(string),
  value: raw,
  overridden_by: integer,
});

/** Domain P2 (docs/apogee/api/domain.md "P2 additions"), ProfileRouting.rules/overrides. */
const rule = object({
  id: token,
  label: string,
  name_template: string,
  enabled: boolean,
  stations: array(
    object({ id: token, code: nullable(string), name: string, transport_id: nullable(token) }),
    500,
  ),
  legs: array(object({ direction: oneOf(["downlink", "uplink"]), role: token }), 20),
  route_count: integer,
  samples: array(string, 10),
});
export type ProfileRule = Decoded<typeof rule>;

const override = object({
  spacecraft: object({ id: token, name: string }),
  section: token,
  path: string,
  profile_value: raw,
  spacecraft_value: raw,
  reason: nullable(string),
  since_revision: nullable(integer),
  set_at: nullable(timestamp),
  actor: nullable(object({ name: string })),
  redundant: boolean,
});
export type ProfileOverride = Decoded<typeof override>;

const actorName = nullable(
  object({ kind: decoders.optional(token), id: decoders.optional(token), name: string }),
);

export const profileDetailReader = object({
  profile: object({
    id: token,
    name: string,
    version: integer,
    catalog_revision: nullable(object({ id: token, number: integer, label: nullable(string) })),
    protocols: object({ downlink: enumValue, uplink: enumValue, packet: enumValue }),
    last_change: nullable(
      object({ version: integer, revision: nullable(integer), at: timestamp, actor: actorName }),
    ),
  }),
  inherit_count: integer,
  on_older_versions: integer,
  override_count: integer,
  sections: array(object({ key: token, label: string, fields: array(field, 500) }), 50),
  applications: raw,
  rules: array(rule, 200),
  overrides: array(override, 5000),
  routing_model: oneOf(["per_spacecraft", "profile"]),
  versions: array(object({ version: integer, created_at: timestamp, actor: actorName }), 500),
});

export type ProfileDetail = Decoded<typeof profileDetailReader>;
export type ProfileField = Decoded<typeof field>;
export type ProfileSection = ProfileDetail["sections"][number];

export function fetchProfileDetail(
  key: Readonly<{ missionId: string; profileId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<ProfileDetail>> {
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/profiles/${encodeURIComponent(key.profileId)}`,
    profileDetailReader,
    { signal },
  );
}

/** A field's value as text: enum label, yes/no, number + unit, or "Not set". */
export function fieldText(f: ProfileField): string {
  if (f.value === null)
    return f.default === null
      ? "Not set"
      : `Not set · default ${fieldText({ ...f, value: f.default, default: null })}`;
  if (f.type === "enum" && f.enum) {
    const option = f.enum.find((o) => o.value === f.value);
    if (option) return option.label;
  }
  if (f.type === "boolean") return f.value === true ? "Yes" : "No";
  const text =
    typeof f.value === "number"
      ? formatCount(f.value)
      : typeof f.value === "string"
        ? f.value
        : JSON.stringify(f.value);
  return f.unit ? `${text} ${f.unit}` : text;
}
