import type { MissionId } from "@/api/index.ts";
import {
  scid as scidReader,
  actor as sharedActor,
  decoders as d,
  request,
  vocabularyText,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { change, changeSetStates, revisionDetailReader } from "@/features/changes/shapes.ts";

/**
 * Investigate › Configuration (Investigate.md §Configuration; ops.md, api-ops 8d8f5c83): what is
 * this spacecraft running, and what changed? Read-only; changes and revisions use Setup's shapes.
 */
/** The shared entity (typing §12 A5). */
const actor = d.nullable(sharedActor);
const catalogRev = d.nullable(d.object({ id: d.token, revision_number: d.nullable(d.integer) }));

const configurationReader = d.object({
  spacecraft: d.object({
    id: d.token,
    name: d.string,
    scid: d.nullable(scidReader),
    norad_id: d.nullable(d.integer),
    plane: d.nullable(d.integer),
    slot: d.nullable(d.integer),
    archived: d.nullable(d.object({ at: d.timestamp, by: actor })),
  }),
  profile: d.nullable(
    d.object({
      id: d.token,
      name: d.nullable(d.string),
      version: d.nullable(d.integer),
      latest_version: d.nullable(d.integer),
      // §11c parity (api c61444ede): the pinned version's facts; null when it can't be read.
      lifecycle: d.optional(d.nullable(d.knownText(["active", "deleted"] as const))),
      uplink_protocol: d.optional(d.nullable(d.knownText(["tc", "uslp"] as const))),
      packet_protocol: d.optional(d.nullable(d.knownText(["space_packet"] as const))),
    }),
  ),
  catalog: d.object({ running: catalogRev, profile: catalogRev }),
  overrides: d.array(
    d.object({
      section: d.nullable(d.string),
      path: d.string,
      label: d.nullable(d.string),
      unit: d.nullable(d.string),
      profile_value_json: d.nullable(d.string),
      spacecraft_value_json: d.nullable(d.string),
      // free-text: the reason a person gave for the override.
      reason: d.nullable(d.string),
      set_at: d.nullable(d.timestamp),
      actor,
    }),
    500,
  ),
  routing_rules: d.array(
    d.object({
      id: d.token,
      name: d.nullable(d.string),
      purpose: d.nullable(d.string),
      direction: d.nullable(d.token),
      role: d.nullable(d.known(["primary", "candidate", "contributing"] as const)),
      enabled: d.boolean,
      active: d.boolean,
      transport: d.nullable(d.object({ id: d.token, name: d.nullable(d.string) })),
      station: d.nullable(
        d.object({
          id: d.nullable(d.token),
          // free-text: the station's short code, an identifier shown as is.
          code: d.nullable(d.string),
          name: d.nullable(d.string),
        }),
      ),
    }),
    200,
  ),
  pending: d.array(
    d.object({
      change_set_id: d.token,
      state: d.known(changeSetStates),
      base_revision: d.nullable(d.integer),
      changes: d.array(change, 500),
    }),
    20,
  ),
  recent_revisions: d.array(revisionDetailReader, 5),
});
export type SpacecraftConfiguration = Decoded<typeof configurationReader>;

export function fetchConfiguration(
  missionId: MissionId,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<SpacecraftConfiguration>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/configuration`,
    configurationReader,
    signal ? { signal } : {},
  );
}

/** JSON text → display ("not set" for null); strings unquoted. */
export function jsonWords(json: string | null, unit: string | null): string {
  if (json === null) return "not set";
  let v: unknown;
  try {
    v = JSON.parse(json);
  } catch {
    return json;
  }
  const text = typeof v === "string" ? v : json;
  return unit ? `${text} ${unit}` : text;
}

/** "Running rev 14; the profile is on rev 15." when they differ (DECISIONS #65), else null. */
export function catalogCaution(c: SpacecraftConfiguration["catalog"]): string | null {
  const run = c.running?.revision_number ?? null;
  const prof = c.profile?.revision_number ?? null;
  return run !== null && prof !== null && run !== prof
    ? `Running rev ${run}; the profile is on rev ${prof}.`
    : null;
}

const UPLINK: Readonly<Record<"tc" | "uslp", string>> = { tc: "TC uplink", uslp: "USLP uplink" };
const PACKETS: Readonly<Record<"space_packet", string>> = { space_packet: "Space Packet" };

/**
 * G1's protocol fact line (§11c parity; api c61444ede): `TC uplink · Space Packet`, dropping what
 * the pinned version doesn't say; null when it says nothing.
 */
export function protocolLine(p: NonNullable<SpacecraftConfiguration["profile"]>): string | null {
  const parts = [
    p.uplink_protocol ? vocabularyText(p.uplink_protocol, UPLINK) : null,
    p.packet_protocol ? vocabularyText(p.packet_protocol, PACKETS) : null,
  ].filter((x): x is string => x !== null);
  return parts.length ? parts.join(" · ") : null;
}

/** G3: "SVB · primary · Primary downlink" (station or transport · role · rule). */
export function routingWords(r: SpacecraftConfiguration["routing_rules"][number]): string {
  const where = r.station?.code ?? r.station?.name ?? r.transport?.name ?? "No station";
  // Say the role once: skip it when the rule's name already carries it ("Primary downlink").
  const known = r.role === "unrecognized" ? null : r.role;
  const role = known && !(r.name ?? "").toLowerCase().includes(known) ? known : null;
  return [where, role, r.name].filter(Boolean).join(" · ");
}
