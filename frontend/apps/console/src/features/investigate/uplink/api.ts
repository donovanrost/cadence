import type { MissionId } from "@/api/index.ts";
import {
  actor,
  decoders as d,
  spacecraftRef,
  stationRef,
  request,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { memberStages } from "@/features/commands/groups/api.ts";
import { passReadinessReader } from "@/features/contacts/readiness.ts";

/**
 * Investigate › Uplink (Investigate.md §Tab · Uplink; ops.md §spacecraft/:id/uplink, aa1f493e):
 * can I command this spacecraft now, and what's going up?
 */
/** §12 A5: the shared station and spacecraft references (api/entities.ts). */
const station = stationRef;
const provider = d.nullable(d.object({ id: d.nullable(d.token), name: d.nullable(d.string) }));
const pass = d.object({
  reservation_id: d.token,
  contact_id: d.nullable(d.token),
  station,
  provider: d.optional(provider),
  starts_at: d.timestamp,
  ends_at: d.timestamp,
});
const group = d.nullable(d.object({ id: d.token, title: d.string }));

const uplinkReader = d.object({
  spacecraft: spacecraftRef,
  route: d.nullable(
    d.object({
      routing_rule_id: d.nullable(d.token),
      name: d.nullable(d.string),
      transport_id: d.nullable(d.token),
      transport_name: d.nullable(d.string),
      gateway_scid: d.nullable(d.integer),
    }),
  ),
  now: d.nullable(
    d.object({ in_contact: d.boolean, pass, readiness: d.nullable(passReadinessReader) }),
  ),
  next_passes: d.array(
    d.object({
      reservation_id: d.token,
      contact_id: d.nullable(d.token),
      station,
      provider: d.optional(provider),
      starts_at: d.timestamp,
      ends_at: d.timestamp,
      /** ops.md: booked (the provider confirmed the uplink leg) or attested. */
      uplink_evidence: d.known(["booked", "attested"] as const),
      uplink_confirmed: d.nullable(d.boolean),
      attested_by: d.nullable(actor),
    }),
    10,
  ),
  queue: d.array(
    d.object({
      position: d.integer,
      request_id: d.token,
      command_id: d.token,
      command_name: d.nullable(d.string),
      arguments_json: d.nullable(d.string),
      group,
      not_before: d.nullable(d.timestamp),
      expires_at: d.nullable(d.timestamp),
      queued_at: d.timestamp,
    }),
    1_000,
  ),
  waits_for: d.nullable(d.object({ pass, readiness: d.nullable(passReadinessReader) })),
  released: d.array(
    d.object({
      request_id: d.token,
      command_name: d.nullable(d.string),
      group,
      released_at: d.timestamp,
      contact_id: d.nullable(d.token),
      /** The member stage (Reads.CommandGroups.row_stage); null before a status row exists. */
      verification_state: d.nullable(d.known(memberStages)),
    }),
    1_000,
  ),
});
export type SpacecraftUplink = Decoded<typeof uplinkReader>;

export function fetchSpacecraftUplink(
  missionId: MissionId,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<SpacecraftUplink>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/uplink`,
    uplinkReader,
    signal ? { signal } : {},
  );
}

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
/** §4 short form: "03:00Z" today, "11-12 03:00Z" otherwise. */
export const shortAt = (iso: string, now: Date) =>
  `${iso.slice(0, 10) === now.toISOString().slice(0, 10) ? "" : `${iso.slice(5, 10)} `}${hhmm(iso)}`;

/** Header meta: 'Route · S-band TC · rule "BLOCK 1 · ALL STATIONS"', or none. */
export function routeMeta(u: SpacecraftUplink): string | undefined {
  const r = u.route;
  if (!r) return "No uplink route";
  return ["Route", r.transport_name, r.name ? `rule “${r.name}”` : null]
    .filter(Boolean)
    .join(" · ");
}

/** U3 release rule: "At next AOS" / "Not before 03:00Z", plus "expires 04:00Z". */
export function releaseRule(q: SpacecraftUplink["queue"][number], now: Date): string {
  const rule = q.not_before ? `Not before ${shortAt(q.not_before, now)}` : "At next AOS";
  return q.expires_at ? `${rule} · expires ${shortAt(q.expires_at, now)}` : rule;
}

/** U2 evidence (U32/#46): "Booked", or "Attested · uplink unconfirmed" (caution). */
export function evidenceWords(p: SpacecraftUplink["next_passes"][number]) {
  return p.uplink_evidence === "attested" || p.uplink_confirmed === false
    ? { text: "Attested · uplink unconfirmed", caution: true }
    : { text: "Booked", caution: false };
}

export const argsSummary = (json: string | null) =>
  !json || json.trim() === "{}"
    ? ""
    : json.replace(/[{}"]/g, "").replace(/,/g, ", ").replace(/:/g, " ");
