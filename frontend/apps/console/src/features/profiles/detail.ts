import type { MissionId } from "@/api/index.ts";
import {
  actor,
  decoders,
  orNull,
  request,
  spacecraftRef,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api";
import { formatCount } from "@/ui";
import { catalogRevision } from "./api.ts";
import { compositionKey } from "@/features/catalog/composition.ts";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:mission_id/profiles/:profile_id`. */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

const raw: Reader<unknown> = (value) => (value === undefined ? null : value);
const enumValue = object({ value: token, label: string });

const field = object({
  path: string,
  label: string,
  // known, not oneOf: a new field type (handled_apids brought `list`, domain 9251b745) never fails the page.
  type: decoders.known(["integer", "boolean", "enum", "string", "reference", "list"] as const),
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
    object({
      id: token,
      // free-text: a station's short code, an identifier shown as is.
      code: nullable(string),
      name: string,
      transport_id: nullable(token),
    }),
    500,
  ),
  legs: array(
    object({
      direction: oneOf(["downlink", "uplink"]),
      role: decoders.known(["primary", "candidate", "contributing"] as const),
    }),
    20,
  ),
  route_count: integer,
  samples: array(string, 10),
});
export type ProfileRule = Decoded<typeof rule>;

/** U79 (api C, additive): a spacecraft's own extra route on this profile, one entry per route. */
const extraRoute = object({
  spacecraft: spacecraftRef,
  route_id: token,
  name: string,
  station: nullable(
    object({
      id: token,
      // free-text: the station's short code, an identifier (null when the station is gone).
      code: nullable(string),
      name: nullable(string),
    }),
  ),
  legs: array(
    object({
      direction: oneOf(["downlink", "uplink"]),
      role: oneOf(["primary", "candidate", "contributing"]),
    }),
    2,
  ),
});
export type ExtraRouteRow = Decoded<typeof extraRoute>;

const override = object({
  spacecraft: spacecraftRef,
  section: token,
  path: string,
  profile_value: raw,
  spacecraft_value: raw,
  // free-text: the reason a person gave for the override.
  reason: nullable(string),
  since_revision: nullable(integer),
  set_at: nullable(timestamp),
  actor: orNull(actor),
  redundant: boolean,
  /** D2 (#581; U109): for a catalog_revision_id override, the composition behind the revision it sets. */
  composition: compositionKey,
});
export type ProfileOverride = Decoded<typeof override>;

/** The shared entity (typing §12 A5). */
const actorName = orNull(actor);

export const profileDetailReader = object({
  profile: object({
    id: token,
    name: string,
    version: integer,
    catalog_revision: nullable(catalogRevision),
    /** D2 (#581; U109): the composition behind the catalog revision. */
    composition: compositionKey,
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
  /** Optional until api serves it (U79 C); absent reads as none. */
  extra_routes: decoders.optional(array(extraRoute, 5000)),
  routing_model: oneOf(["per_spacecraft", "profile"]),
  versions: array(
    object({
      version: integer,
      created_at: timestamp,
      actor: actorName,
      /** api c3b07440d: spacecraft on this version ("12 spacecraft on v5"); optional for older servers. */
      spacecraft_count: decoders.optional(integer),
    }),
    500,
  ),
});

export type ProfileDetail = Decoded<typeof profileDetailReader>;
export type ProfileField = Decoded<typeof field>;
export type ProfileSection = ProfileDetail["sections"][number];

export function fetchProfileDetail(
  key: Readonly<{ missionId: MissionId; profileId: string }>,
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
  // domain 9251b745: a null APID list means every APID the catalog defines.
  // compared-as-text: a schema field path, an open set the server's schema defines
  if (f.path === "handled_apids" && f.value === null) return "All of the catalog's APIDs";
  if (f.value === null)
    return f.default === null
      ? "Not set"
      : `Not set · default ${fieldText({ ...f, value: f.default, default: null })}`;
  // Enum and reference fields with choices (a catalog revision) read as the choice's label.
  if (f.enum) {
    const option = f.enum.find((o) => o.value === f.value);
    if (option) return option.label;
  }
  if (f.type === "boolean") return f.value === true ? "Yes" : "No";
  if (Array.isArray(f.value)) return f.value.map((v) => String(v)).join(", ");
  const text =
    typeof f.value === "number"
      ? formatCount(f.value)
      : typeof f.value === "string"
        ? f.value
        : JSON.stringify(f.value);
  return f.unit ? `${text} ${f.unit}` : text;
}
