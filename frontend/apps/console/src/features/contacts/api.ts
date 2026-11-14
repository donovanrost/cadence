import type { MissionId } from "@/api/index.ts";
import {
  stationId as stationIdReader,
  spacecraftId as spacecraftIdReader,
  scid as scidReader,
  actor,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { attentionReader, passChangeReader } from "@/features/now/index.ts";
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

/** Provider pass and delivery progress (domain `KnownAtom.provider_pass_phase!` / `_delivery_state!`). */
export const passPhases = ["scheduled", "prepass", "pass", "postpass", "closed"] as const;
export const deliveryStates = [
  "pending",
  "ready",
  "connected",
  "flowing",
  "degraded",
  "failed",
  "ended",
] as const;

/**
 * Who ended a booking (reads/pass_enders.ex): a person, a service, Cadence, or the provider itself
 * ("Canceled by Northlight"), so not the shared actor, whose kinds don't include provider.
 */
export const passEnderKinds = ["user", "service", "system", "provider"] as const;
const passEnder = d.object({
  kind: d.nullable(d.knownText(passEnderKinds)),
  id: d.nullable(d.string),
  name: d.nullable(d.string),
});
export type PassEnder = Decoded<typeof passEnder>;

const pass = d.object({
  id: d.token,
  kind: d.literal("contact"),
  state: d.oneOf(reservationStates),
  // The provider's progress (domain KnownAtom); an unknown value reads "unrecognized".
  pass_phase: d.nullable(d.known(passPhases)),
  delivery_state: d.nullable(d.known(deliveryStates)),
  spacecraft_id: d.nullable(spacecraftIdReader),
  /** Identity on the row (5f02fd3d), so names never depend on a client join. */
  // name is null for a deleted spacecraft (contacts.md; api drift sweep 11-13).
  spacecraft: d.nullable(
    d.object({ id: d.token, name: d.nullable(d.string), scid: d.nullable(scidReader) }),
  ),
  station: d.object({
    ref: d.nullable(d.string),
    id: d.nullable(d.token),
    // free-text: a station call sign (SVA), not a vocabulary
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
    synthetic: d.nullable(d.boolean),
  }),
  max_elevation_deg: d.nullable(d.number),
  /** The contact plan revision that booked it; null for direct bookings. */
  plan: d.nullable(d.object({ id: d.token, version: d.nullable(d.integer) })),
  /** qa #30: who ended a canceled/rejected/failed booking; absent on older servers. */
  ended_by: d.optional(d.nullable(passEnder)),
  /**
   * qa #30 / domain #56: what replaced this lost booking (an applied repair, or a single booking
   * with plan_id null); null while still lost.
   */
  replaced_by: d.optional(
    d.nullable(
      d.object({
        kind: d.optional(d.nullable(d.knownText(["repair", "single_booking"] as const))),
        plan_id: d.nullable(d.token),
        reservation_id: d.nullable(d.token),
      }),
    ),
  ),
  /** U32 (contacts.md d2632794): how the booking is known; optional until api-ops ships it. */
  booking_evidence: d.optional(d.nullable(d.oneOf(["provider", "operator_attested"] as const))),
  attested_by: d.optional(d.nullable(actor)),
  /** null: no uplink leg was requested (downlink only), which isn't "unconfirmed". */
  uplink_confirmed: d.optional(d.nullable(d.boolean)),
  /** The pass's open or acknowledged attention item (U31/U32), the queue's object. */
  attention: d.optional(d.nullable(attentionReader)),
  /**
   * Every open item on the pass in U45's order (priority, soonest due, contact_start on ties); the
   * first is `attention`. Optional until api ships it (U45).
   */
  attentions: d.optional(d.array(attentionReader, 50)),
  /** U33: null when the pass has no uplink to be ready; optional until api-ops ships it. */
  uplink_readiness: d.optional(d.nullable(passReadinessReader)),
  /** Release (50c5e572): the booking revision to send back, and whether the viewer may release. */
  provider_revision: d.optional(d.nullable(d.integer)),
  releasable: d.optional(d.nullable(d.boolean)),
  /**
   * L15 (plans/single-bookings.md): a booking made outside a plan, by whom and why; null for plan
   * bookings. Optional until the endpoints ship.
   */
  off_plan: d.optional(
    d.nullable(
      d.object({
        booked_by: d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) })),
        booked_at: d.timestamp,
        note: d.nullable(d.string),
      }),
    ),
  ),
  /** GET /passes/:id only (api, L14 flown passes): the pass's open changes, newest first. */
  provider_changes: d.optional(d.array(passChangeReader, 100)),
});
export const passReader = pass;

/** GET /passes/:id only (04755d23): command groups queued for this pass, and where they'd go. */
const queuedReader = d.object({
  queued_command_groups: d.optional(
    d.nullable(
      d.object({
        count: d.integer,
        next_pass: d.nullable(
          d.object({
            station: d.object({
              // free-text: a station call sign, not a vocabulary
              code: d.nullable(d.string),
              name: d.nullable(d.string),
            }),
            starts_at: d.timestamp,
          }),
        ),
      }),
    ),
  ),
});
export type QueuedGroups = NonNullable<Decoded<typeof queuedReader>["queued_command_groups"]>;

export function fetchQueuedGroups(missionId: MissionId, passId: string, signal?: AbortSignal) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}`,
    queuedReader,
    signal ? { signal } : {},
  );
}

/**
 * GET /passes/:id only (api, U50): second connections refused while the pass's own connection was
 * up. null = unknown (no realized contact, or a live count lost to a restart); 0 = none.
 */
const passTechnicalReader = d.object({
  second_connections_refused: d.optional(d.nullable(d.integer)),
});

export function fetchPassTechnical(missionId: MissionId, passId: string, signal?: AbortSignal) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}`,
    passTechnicalReader,
    signal ? { signal } : {},
  );
}

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
  missionId: MissionId,
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
  missionId: MissionId,
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
      id: stationIdReader,
      display_name: d.nullable(d.string),
      // free-text: a station call sign (SVA), not a vocabulary
      code: d.nullable(d.string),
      /** The station's provider, by name (U33: group lines name it without a new field). */
      provider: d.optional(d.nullable(d.string)),
    }),
    1_000,
  ),
});
export type GroundStation = Decoded<typeof stationsReader>["stations"][number];

export function fetchStations(missionId: MissionId, signal?: AbortSignal) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/ground-stations`,
    stationsReader,
    signal ? { signal } : {},
  );
}
