import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Requested shape: docs/apogee/plans/setup-shapes.md §D1. */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

const source = object({
  id: token,
  display_name: string,
  kind: token,
  owner: token,
  status: token,
  health: nullable(
    object({ status: oneOf(["healthy", "degraded", "unknown"]), checked_at: nullable(timestamp) }),
  ),
  last_received_at: nullable(timestamp),
  expected_interval_s: nullable(integer),
  stale: nullable(boolean),
  credentials: nullable(
    object({
      status: oneOf(["valid", "expiring", "expired", "none"]),
      rotated_at: nullable(timestamp),
    }),
  ),
});
export type DataSource = Decoded<typeof source>;

export async function fetchSources(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly DataSource[]>> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/data-sources`,
    object({ sources: array(source, 1000) }),
    { signal },
  );
  return result.ok ? { ok: true, value: result.value.sources } : result;
}
