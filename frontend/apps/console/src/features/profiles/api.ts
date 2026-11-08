import { decoders, request, type ApiResult, type Reader } from "@/api";

/** Contract: docs/apogee/api/setup.md, `GET /api/console/v1/missions/:mission_id/profiles`. */
const { array, integer, nullable, object, string, token } = decoders;

export type EnumValue = Readonly<{ value: string; label: string }>;

export type ProfileSummary = Readonly<{
  id: string;
  name: string;
  version: number;
  downlinkProtocol: EnumValue;
  uplinkProtocol: EnumValue;
  packetProtocol: EnumValue;
  catalogRevision: Readonly<{ id: string; number: number; label: string | null }> | null;
  spacecraftCount: number;
  /** Subset of spacecraftCount pinned below `version`. */
  spacecraftOnOlderVersions: number;
}>;

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
    catalog_revision: nullable(object({ id: token, number: integer, label: nullable(string) })),
    spacecraft_count: count,
    spacecraft_on_older_versions: count,
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
    spacecraftCount: raw.spacecraft_count,
    spacecraftOnOlderVersions: raw.spacecraft_on_older_versions,
  };
};

export const profilesReader: Reader<readonly ProfileSummary[]> = (value, path = "") =>
  object({ profiles: array(profile, 1000) })(value, path).profiles;

export function fetchProfiles(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly ProfileSummary[]>> {
  return request(`/missions/${encodeURIComponent(missionId)}/profiles`, profilesReader, { signal });
}

/** "CCSDS TM / TC" style protocol line. */
export function protocolLine(p: ProfileSummary): string {
  return `${p.downlinkProtocol.label} ↓ · ${p.uplinkProtocol.label} ↑`;
}
