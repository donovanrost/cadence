import type { MissionId } from "@/api/index.ts";
import {
  spacecraftId as spacecraftIdReader,
  scid as scidReader,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
  pointId as pointIdReader,
} from "@/api/index.ts";

/** Contract: docs/apogee/api/ops.md, `GET /api/v1/missions/:mission_id/fleet`. */

export const fleetStates = ["critical", "caution", "stale", "nominal", "never_heard"] as const;
export type FleetState = (typeof fleetStates)[number];

const limitState = d.oneOf(["critical", "caution", "nominal", "no_data"] as const);
/** The evaluator's own state (Cadence.Limits.Evaluator), before normalising to limit_state. */
export const rawLimitStates = [
  "green",
  "yellow_low",
  "yellow_high",
  "red_low",
  "red_high",
  "blue",
] as const;
export type RawLimitState = (typeof rawLimitStates)[number];

const worstPoint = d.object({
  point_id: pointIdReader,
  point_name: d.string,
  // Exact server value: numbers stay numbers, enum/text values stay text.
  value: d.nullable((value, path) => (typeof value === "string" ? value : d.number(value, path))),
  limit_state: limitState,
  raw_limit_state: d.nullable(d.known(rawLimitStates)),
  received_at: d.nullable(d.timestamp),
});

const profile = d.object({
  id: d.token,
  name: d.nullable(d.string),
  version: d.nullable(d.integer),
});

const spacecraft = d.object({
  id: spacecraftIdReader,
  name: d.string,
  scid: scidReader,
  profile: d.nullable(profile),
  plane: d.nullable(d.integer),
  slot: d.nullable(d.integer),
  phase_deg: d.nullable(d.number),
  // free-text: spacecraft metadata an operator sets (FleetStatus reads it as any string).
  operational_phase: d.nullable(d.token),
  state: d.oneOf(fleetStates),
  limit_state: limitState,
  violating_points: d.integer,
  worst_point: d.nullable(worstPoint),
  last_received_at: d.nullable(d.timestamp),
  stale: d.boolean,
  in_contact: d.nullable(d.boolean),
  /** Planned times from booked reservations (M7); null = not tracked / none booked. */
  next_aos_at: d.nullable(d.timestamp),
  last_los_at: d.nullable(d.timestamp),
});

const count = d.integer;

const counts = d.object({
  total: count,
  critical: count,
  caution: count,
  stale: count,
  nominal: count,
  never_heard: count,
  fresh: count,
  in_contact: d.nullable(count),
  passes_next_2h: d.nullable(count),
  critical_delta_1h: d.nullable(d.integer),
});

const commands = d.object({
  queued: count,
  in_flight: count,
  failed: count,
  approval_pending: count,
  awaiting_viewer: count,
});

/** GET /fleet's fields; the `fleet` channel push reuses them (live.ts). */
export const fleetFields = {
  observed_at: d.timestamp,
  stale_after_s: d.integer,
  last_received_at: d.nullable(d.timestamp),
  counts,
  commands,
  limits: d.object({ configured: d.boolean }),
  spacecraft: d.array(spacecraft, 20_000),
} as const;

const fleetShape = d.object({
  ...fleetFields,
  /** 17deb3c1: 'degraded' when the TSDB lookup timed out (live values and limits only). */
  telemetry: d.optional(d.oneOf(["ok", "degraded"] as const)),
});

/** True when the state counts partition the rows (the invariant fleetReader enforces). */
export function countsPartition(fleet: Decoded<typeof fleetShape>): boolean {
  const c = fleet.counts;
  return (
    c.total === fleet.spacecraft.length &&
    c.critical + c.caution + c.stale + c.nominal + c.never_heard === c.total
  );
}

/** Validates relationships a structural schema can't: the state counts partition the fleet. */
export const fleetReader: d.Reader<Decoded<typeof fleetShape>> = (value, path = "") => {
  const fleet = fleetShape(value, path);
  if (!countsPartition(fleet))
    throw new d.DecodeError(`${path}counts`, "state counts that partition the spacecraft rows");
  return fleet;
};

export type Fleet = Decoded<typeof fleetReader>;
export type FleetSpacecraft = Fleet["spacecraft"][number];
export type FleetWorstPoint = NonNullable<FleetSpacecraft["worst_point"]>;

/** A fleet read that hasn't answered by now is reported, not waited on (qa: a hung TSDB held it 2 min). */
export const FLEET_TIMEOUT_MS = 20_000;

export async function fetchFleet(
  missionId: MissionId,
  signal?: AbortSignal,
): Promise<ApiResult<Fleet>> {
  const timeout = AbortSignal.timeout(FLEET_TIMEOUT_MS);
  const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;
  const result = await request(`/missions/${encodeURIComponent(missionId)}/fleet`, fleetReader, {
    signal: combined,
  });
  // request() reports a timed-out fetch as unreachable; say what actually happened.
  return !result.ok && timeout.aborted && !signal?.aborted
    ? {
        ok: false,
        error: {
          kind: "unavailable",
          status: 0,
          message: `The fleet read didn't answer within ${FLEET_TIMEOUT_MS / 1000} s. The telemetry store may be slow.`,
        },
      }
    : result;
}
