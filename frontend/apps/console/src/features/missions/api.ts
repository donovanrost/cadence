import { decoders, request, type ApiResult, type Decoded } from "@/api";
import { fleetStates } from "@/features/fleet/index.ts";

/** Contract: docs/apogee/api/setup.md, `GET /organizations/:id/missions` (pass-2 #11). */
const { array, integer, nullable, object, oneOf, string, token } = decoders;

const summary = object({
  id: token,
  slug: token,
  name: string,
  spacecraft_count: integer,
  worst_state: nullable(oneOf(fleetStates)),
});
export type MissionSummary = Decoded<typeof summary>;

export async function fetchMissionSummaries(
  organizationId: string,
  signal: AbortSignal,
): Promise<ApiResult<ReadonlyMap<string, MissionSummary>>> {
  const result = await request(
    `/organizations/${encodeURIComponent(organizationId)}/missions`,
    object({ missions: array(summary, 1000) }),
    { signal },
  );
  return result.ok
    ? { ok: true, value: new Map(result.value.missions.map((m) => [m.id, m])) }
    : result;
}
