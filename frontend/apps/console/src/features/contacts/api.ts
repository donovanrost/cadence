import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import { attentionReader } from "@/features/now/index.ts";
import { passReadinessReader } from "./readiness.ts";

/** Contract: docs/apogee/api/contacts.md, `GET /missions/:mission_id/passes` (M7 / S1). */

export const reservationStates = [
  "requesting",
  "pending",
  "confirmed",
  "active",
  "completed",
  "unknown",
  "rejected",
  "canceling",
  "canceled",
  "failed",
] as const;

const pass = d.object({
  id: d.token,
  kind: d.literal("contact"),
  state: d.oneOf(reservationStates),
  pass_phase: d.nullable(d.token),
  delivery_state: d.nullable(d.token),
  spacecraft_id: d.nullable(d.token),
  /** Identity on the row (5f02fd3d), so names never depend on a client join. */
  spacecraft: d.nullable(d.object({ id: d.token, name: d.string, scid: d.nullable(d.integer) })),
  station: d.object({
    ref: d.nullable(d.string),
    id: d.nullable(d.token),
    code: d.nullable(d.string),
    name: d.nullable(d.string),
  }),
  antenna: d.nullable(d.object({ id: d.nullable(d.string), label: d.nullable(d.string) })),
  starts_at: d.timestamp,
  ends_at: d.timestamp,
  uplink_capable: d.nullable(d.boolean),
  source: d.object({
    provider: d.nullable(d.string),
    provider_name: d.nullable(d.string),
    synthetic: d.boolean,
  }),
  max_elevation_deg: d.nullable(d.number),
  /** The contact plan revision that booked it; null for direct bookings. */
  plan: d.nullable(d.object({ id: d.token, version: d.nullable(d.integer) })),
  /** qa #30: who ended a canceled/rejected/failed booking; absent on older servers. */
  ended_by: d.optional(
    d.nullable(d.object({ kind: d.string, id: d.nullable(d.string), name: d.nullable(d.string) })),
  ),
  /**
   * qa #30 / domain #56: what replaced this lost booking (an applied repair, or a single booking
   * with plan_id null); null while still lost.
   */
  replaced_by: d.optional(
    d.nullable(
      d.object({
        kind: d.optional(d.nullable(d.string)),
        plan_id: d.nullable(d.token),
        reservation_id: d.nullable(d.token),
      }),
    ),
  ),
  /** U32 (contacts.md d2632794): how the booking is known; optional until api-ops ships it. */
  booking_evidence: d.optional(d.nullable(d.oneOf(["provider", "operator_attested"] as const))),
  attested_by: d.optional(
    d.nullable(d.object({ kind: d.string, id: d.nullable(d.string), name: d.nullable(d.string) })),
  ),
  /** null: no uplink leg was requested (downlink only), which isn't "unconfirmed". */
  uplink_confirmed: d.optional(d.nullable(d.boolean)),
  /** The pass's open or acknowledged attention item (U31/U32), the queue's object. */
  attention: d.optional(d.nullable(attentionReader)),
  /** U33: null when the pass has no uplink to be ready; optional until api-ops ships it. */
  uplink_readiness: d.optional(d.nullable(passReadinessReader)),
  /** Release (50c5e572): the booking revision to send back, and whether the viewer may release. */
  provider_revision: d.optional(d.nullable(d.integer)),
  releasable: d.optional(d.nullable(d.boolean)),
});
export const passReader = pass;

export const passesReader = d.object({
  from: d.timestamp,
  to: d.timestamp,
  truncated: d.boolean,
  passes: d.array(pass, 500),
});
export type Passes = Decoded<typeof passesReader>;
export type Pass = Passes["passes"][number];

/** One pass in any window (8329ec68): Review from Now can name a pass days out. 404 pass_not_found. */
export function fetchPass(
  missionId: string,
  passId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Pass>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}`,
    pass,
    signal ? { signal } : {},
  );
}

export function fetchPasses(
  missionId: string,
  query: Readonly<{ from: Date; to: Date; spacecraftId?: string; station?: string }>,
  signal?: AbortSignal,
): Promise<ApiResult<Passes>> {
  const params = new URLSearchParams({
    from: query.from.toISOString(),
    to: query.to.toISOString(),
  });
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  if (query.station) params.set("station", query.station);
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes?${params.toString()}`,
    passesReader,
    signal ? { signal } : {},
  );
}

/** Active ground stations (api setup.md G1); only what Contacts needs: id, name, code. */
const stationsReader = d.object({
  stations: d.array(
    d.object({
      id: d.token,
      display_name: d.nullable(d.string),
      code: d.nullable(d.string),
      /** The station's provider, by name (U33: group lines name it without a new field). */
      provider: d.optional(d.nullable(d.string)),
    }),
    1_000,
  ),
});
export type GroundStation = Decoded<typeof stationsReader>["stations"][number];

export function fetchStations(missionId: string, signal?: AbortSignal) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/ground-stations`,
    stationsReader,
    signal ? { signal } : {},
  );
}
