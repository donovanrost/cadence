import type { MissionId } from "@/api/index.ts";
import { actor, decoders, orNull, request, type ApiResult, type Decoded, type Reader } from "@/api";
import { formatShort } from "@/ui";
import { compositionKey, type Composition } from "@/features/catalog/composition.ts";

/** Contract: docs/apogee/api/setup.md, `GET /api/console/v1/missions/:mission_id/profiles`. */
const { array, integer, nullable, object, string, token } = decoders;

/**
 * The catalog revision a profile's latest version sets (setup.md): number and label are null when
 * the revision isn't among the mission's (#246; #247: the detail read sent only its id).
 */
export const catalogRevision = object({
  id: token,
  number: orNull(integer),
  label: orNull(string),
});
export type CatalogRevision = Decoded<typeof catalogRevision>;
/** "rev 4", or null when the server couldn't number it. */
export const catalogRevText = (r: CatalogRevision): string | null =>
  r.number === null ? null : `rev ${r.number}`;

export type EnumValue = Readonly<{ value: string; label: string }>;

export type ProfileSummary = Readonly<{
  id: string;
  name: string;
  version: number;
  downlinkProtocol: EnumValue;
  uplinkProtocol: EnumValue;
  packetProtocol: EnumValue;
  catalogRevision: CatalogRevision | null;
  /** D2 (#581; U109): the composition behind the catalog revision; composed only after D4. */
  composition: Composition | null;
  spacecraftCount: number;
  /** Subset of spacecraftCount pinned below `version`. */
  spacecraftOnOlderVersions: number;
  /** Asked of api (Profile.md list); null until the list sends them. */
  overrideCount: number | null;
  lastChange: LastChange | null;
}>;

/** The detail's `profile.last_change`: `r5` with change sets, else `v4 · 10-19 02:29Z by …`. */
export type LastChange = Readonly<{
  version: number;
  revision: number | null;
  at: string;
  actor: Readonly<{ name: string | null }> | null;
}>;
const lastChange = nullable(
  object({
    version: integer,
    revision: nullable(integer),
    at: decoders.timestamp,
    actor: nullable(actor),
  }),
);
const optionalOf =
  <T>(read: Reader<T>): Reader<T | null> =>
  (value, path) =>
    value === undefined ? null : read(value, path);

const enumValue = object({ value: token, label: string });
const count: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 0) throw new decoders.DecodeError(path, "non-negative integer");
  return n;
};

const profile: Reader<ProfileSummary> = (value, path = "") => {
  const raw = object({
    id: token,
    name: string,
    version: integer,
    downlink_protocol: enumValue,
    uplink_protocol: enumValue,
    packet_protocol: enumValue,
    catalog_revision: nullable(catalogRevision),
    composition: compositionKey,
    spacecraft_count: count,
    spacecraft_on_older_versions: count,
    override_count: optionalOf(count),
    last_change: optionalOf(lastChange),
  })(value, path);
  if (raw.version < 1) throw new decoders.DecodeError(`${path}.version`, "version ≥ 1");
  if (raw.spacecraft_on_older_versions > raw.spacecraft_count)
    throw new decoders.DecodeError(`${path}.spacecraft_on_older_versions`, "≤ spacecraft_count");
  return {
    id: raw.id,
    name: raw.name,
    version: raw.version,
    downlinkProtocol: raw.downlink_protocol,
    uplinkProtocol: raw.uplink_protocol,
    packetProtocol: raw.packet_protocol,
    catalogRevision: raw.catalog_revision,
    composition: raw.composition ?? null,
    spacecraftCount: raw.spacecraft_count,
    spacecraftOnOlderVersions: raw.spacecraft_on_older_versions,
    overrideCount: raw.override_count,
    lastChange: raw.last_change,
  };
};

export const profilesReader: Reader<readonly ProfileSummary[]> = (value, path = "") =>
  object({ profiles: array(profile, 1000) })(value, path).profiles;

export function fetchProfiles(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<readonly ProfileSummary[]>> {
  return request(`/missions/${encodeURIComponent(missionId)}/profiles`, profilesReader, { signal });
}

/**
 * P7 (#313, ux §10): "CCSDS TM / TC", no arrows. A family both labels share ("CCSDS") is said
 * once; otherwise both labels in full ("CCSDS TM / Custom TC").
 */
export function protocolLine(p: ProfileSummary): string {
  const down = p.downlinkProtocol.label;
  const up = p.uplinkProtocol.label;
  const [family, downName] = splitFamily(down);
  const [upFamily, upName] = splitFamily(up);
  return family !== null && family === upFamily
    ? `${family} ${downName} / ${upName}`
    : `${down} / ${up}`;
}
const splitFamily = (label: string): readonly [string | null, string] => {
  const at = label.lastIndexOf(" ");
  return at > 0 ? [label.slice(0, at), label.slice(at + 1)] : [null, label];
};

/** Profile.md list: overrides read caution past 10% of the profile's fleet [decision]. */
export const manyOverrides = (p: ProfileSummary) =>
  p.overrideCount !== null && p.spacecraftCount > 0 && p.overrideCount > p.spacecraftCount * 0.1;

/** `r5` with change sets, else `v4 · 10-19 02:29Z` (Profile.md list, as the page subline). */
export function lastChangeText(c: LastChange): string {
  return c.revision !== null ? `r${c.revision}` : `v${c.version} · ${formatShort(new Date(c.at))}`;
}
