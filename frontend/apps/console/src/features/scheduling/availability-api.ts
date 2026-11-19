import {
  decoders as d,
  request,
  stationId as stationIdReader,
  type ApiResult,
  type Decoded,
  type MissionId,
} from "@/api";

/** Contracts: docs/apogee/api/scheduling.md: station availability (S7). */

const availabilityWindow = d.object({
  id: d.token,
  ground_station_id: stationIdReader,
  kind: d.oneOf(["outage", "maintenance", "degraded"]),
  from: d.timestamp,
  to: d.nullable(d.timestamp),
  eta: d.nullable(d.timestamp),
  // free-text: who reported it, shown as the server words it (no closed list in the contract)
  source: d.string,
  reported_at: d.nullable(d.timestamp),
  // free-text: the operator's or provider's own explanation
  reason: d.nullable(d.string),
  cleared_at: d.nullable(d.timestamp),
});
export const availabilityReader = d.object({
  at: d.timestamp,
  stations: d.array(
    d.object({
      // §12C: a StationId, so it can't be confused with a code or a provider ref.
      ground_station_id: stationIdReader,
      state: d.oneOf(["up", "degraded", "down"]),
      since: d.nullable(d.timestamp),
      eta: d.nullable(d.timestamp),
      basis: d.nullable(d.string),
      windows: d.array(availabilityWindow, 500),
    }),
    500,
  ),
});
export type Availability = Decoded<typeof availabilityReader>;
export type AvailabilityWindow = Decoded<typeof availabilityWindow>;

/** S7: every station's reported state with active and upcoming windows (7 d). 'up' = nothing reported. */
export function fetchAvailability(
  missionId: MissionId,
  signal?: AbortSignal,
): Promise<ApiResult<Availability>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/station-availability`,
    availabilityReader,
    signal ? { signal } : {},
  );
}
