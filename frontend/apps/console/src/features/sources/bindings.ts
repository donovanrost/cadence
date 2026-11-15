import type { MissionId } from "@/api/index.ts";
import {
  actor as sharedActor,
  decoders as d,
  orNull,
  request,
  type ApiResult,
  type Decoded,
} from "@/api";

/**
 * #90 / U53 (api-ops 65f66a88e, setup.md §Data sources): the mission's bindings, a platform-wide
 * binding's blast radius, and a binding's history.
 */
const base = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/data-source-bindings`;
const named = d.object({ id: d.token, display_name: d.string });
/** A history event's source: its name may be missing (qa 11-15: a null to.display_name). */
const eventSource = d.object({ id: d.token, display_name: d.nullable(d.string) });

export const bindingStatuses = ["active", "disabled", "superseded"] as const;
const missionBinding = d.object({
  id: d.token,
  // free-text: a logical source key, an open set R1 lists (the key, not a vocabulary).
  logical_source: d.token,
  // free-text: the realm the binding serves (flight, …), shown in Technical details only.
  realm: d.string,
  data_source: named,
  status: d.known(bindingStatuses),
  shared: d.boolean,
});
export type MissionBinding = Decoded<typeof missionBinding>;
const missionBindings = d.object({ bindings: d.array(missionBinding, 500) });

/** The mission's own bindings first, then the platform-wide ones it falls back to. */
export async function fetchMissionBindings(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<readonly MissionBinding[]>> {
  const r = await request(base(missionId), missionBindings, { signal });
  return r.ok ? { ok: true, value: r.value.bindings } : r;
}

export const blastRadiusReader = d.object({
  binding: d.object({
    id: d.token,
    // free-text: a logical source key, an open set R1 lists (the key, not a vocabulary).
    logical_source: d.token,
    // free-text: see missionBinding.realm.
    realm: d.string,
    from: named,
  }),
  affected_missions: d.integer,
  live_passes: d.object({
    total: d.integer,
    first: d.array(
      d.object({
        // free-text: the spacecraft's name as the fleet names it.
        spacecraft_name: d.string,
        // free-text: the station's short code (SVA, KSAT…), an open set of the network's stations.
        station_code: d.nullable(d.token),
        aos: d.timestamp,
      }),
      3,
    ),
  }),
});
export type BlastRadius = Decoded<typeof blastRadiusReader>;
export type BindingKey = Readonly<{ missionId: MissionId; bindingId: string }>;

/** Re-read whenever the sheet opens; 503 blast_radius_unavailable when counting fails. */
export function fetchBlastRadius(k: BindingKey, signal: AbortSignal) {
  return request(
    `${base(k.missionId)}/${encodeURIComponent(k.bindingId)}/blast-radius`,
    blastRadiusReader,
    { signal },
  );
}

export const bindingEventKinds = [
  "switched",
  "registered",
  "changed",
  "enabled",
  "disabled",
  "superseded",
] as const;
const bindingEvent = d.object({
  at: d.timestamp,
  actor: orNull(sharedActor),
  kind: d.knownText(bindingEventKinds),
  from: d.nullable(eventSource),
  to: d.nullable(eventSource),
  // free-text: the reason a platform admin typed for a platform-wide switch.
  reason: d.nullable(d.string),
  affected_missions: d.nullable(d.integer),
  live_passes_total: d.nullable(d.integer),
});
export type BindingEvent = Decoded<typeof bindingEvent>;
const bindingEvents = d.object({ events: d.array(bindingEvent, 50) });

/** Newest first, 50. */
export async function fetchBindingEvents(
  k: BindingKey,
  signal: AbortSignal,
): Promise<ApiResult<readonly BindingEvent[]>> {
  const r = await request(
    `${base(k.missionId)}/${encodeURIComponent(k.bindingId)}/events`,
    bindingEvents,
    { signal },
  );
  return r.ok ? { ok: true, value: r.value.events } : r;
}
