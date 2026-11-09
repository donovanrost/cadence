import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Requested shape: docs/apogee/plans/setup-shapes.md §G1 (final contract in api/setup.md). */
const { array, integer, nullable, object, oneOf, string, token } = decoders;

const station = object({
  id: token,
  display_name: string,
  code: nullable(string),
  provider: nullable(string),
  region: nullable(string),
  lifecycle_state: oneOf(["active", "archived"]),
  transport_count: integer,
  routing_rule_count: integer,
  health: nullable(
    object({ status: oneOf(["nominal", "degraded", "down"]), since: nullable(string) }),
  ),
});
export const stationsReader = object({ stations: array(station, 5000) });
export type Station = Decoded<typeof station>;

export async function fetchStations(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly Station[]>> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/ground-stations`,
    stationsReader,
    { signal },
  );
  return result.ok ? { ok: true, value: result.value.stations } : result;
}
