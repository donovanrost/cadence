import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";

/** Contract: docs/apogee/api/ops.md, `GET /api/console/v1/missions/:mission_id/fleet`. */

export const fleetStates = ["critical", "caution", "stale", "nominal", "never_heard"] as const;
export type FleetState = (typeof fleetStates)[number];

const limitState = d.oneOf(["critical", "caution", "nominal", "no_data"] as const);

const worstPoint = d.object({
  point_id: d.token,
  point_name: d.string,
  // Exact server value: numbers stay numbers, enum/text values stay text.
  value: d.nullable((value, path) => (typeof value === "string" ? value : d.number(value, path))),
  limit_state: limitState,
  raw_limit_state: d.nullable(d.token),
  received_at: d.nullable(d.timestamp),
});

const profile = d.object({
  id: d.token,
  name: d.nullable(d.string),
  version: d.nullable(d.integer),
});

const spacecraft = d.object({
  id: d.token,
  name: d.string,
  scid: d.integer,
  profile: d.nullable(profile),
  plane: d.nullable(d.integer),
  slot: d.nullable(d.integer),
  phase_deg: d.nullable(d.number),
  operational_phase: d.nullable(d.token),
  state: d.oneOf(fleetStates),
  limit_state: limitState,
  violating_points: d.integer,
  worst_point: d.nullable(worstPoint),
  last_received_at: d.nullable(d.timestamp),
  stale: d.boolean,
  in_contact: d.nullable(d.boolean),
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

const fleetShape = d.object({
  observed_at: d.timestamp,
  stale_after_s: d.integer,
  last_received_at: d.nullable(d.timestamp),
  counts,
  commands,
  limits: d.object({ configured: d.boolean }),
  spacecraft: d.array(spacecraft, 20_000),
});

/** Validates relationships a structural schema can't: the state counts partition the fleet. */
export const fleetReader: d.Reader<Decoded<typeof fleetShape>> = (value, path = "") => {
  const fleet = fleetShape(value, path);
  const c = fleet.counts;
  if (c.total !== fleet.spacecraft.length)
    throw new d.DecodeError(`${path}counts.total`, "the number of spacecraft rows");
  if (c.critical + c.caution + c.stale + c.nominal + c.never_heard !== c.total)
    throw new d.DecodeError(`${path}counts`, "state counts that sum to total");
  return fleet;
};

export type Fleet = Decoded<typeof fleetReader>;
export type FleetSpacecraft = Fleet["spacecraft"][number];
export type FleetWorstPoint = NonNullable<FleetSpacecraft["worst_point"]>;

export function fetchFleet(missionId: string, signal?: AbortSignal): Promise<ApiResult<Fleet>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/fleet`,
    fleetReader,
    signal ? { signal } : {},
  );
}
