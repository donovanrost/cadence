import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Requested shape: docs/apogee/plans/setup-shapes.md §G1 (final contract in api/setup.md). */
const { array, integer, known, nullable, object, oneOf, string, token } = decoders;

const station = object({
  id: token,
  display_name: string,
  // free-text: the station's short code, an identifier.
  code: nullable(string),
  /** U25: a name stem the operator confirms; present only when `code` is null, never stored. */
  suggested_code: decoders.optional(nullable(string)),
  provider: nullable(string),
  region: nullable(string),
  lifecycle_state: oneOf(["active", "archived"]),
  // null: the model has no station↔transport link yet (api); the columns are hidden then.
  transport_count: nullable(integer),
  routing_rule_count: nullable(integer),
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

const provider = object({
  id: token,
  name: string,
  // free-text: an open vocabulary (provider adapter keys).
  provider_type: token,
  account: object({ id: token, name: nullable(string) }),
  status: object({
    lifecycle_state: known(["active", "archived"] as const),
    last_validated_at: nullable(decoders.timestamp),
    last_synced_at: nullable(decoders.timestamp),
  }),
  station_count: integer,
});
export type MissionProvider = Decoded<typeof provider>;

export async function fetchProviders(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly MissionProvider[]>> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/providers`,
    array(provider, 500),
    { signal },
  );
  return result;
}
