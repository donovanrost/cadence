import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import { engineeringValue } from "@/features/alarms/index.ts";

/** M23 point search (docs/apogee/api/ops.md, 5939f15d): the mission's canonical point set. */

const point = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  unit: d.nullable(d.string),
  subsystem: d.nullable(d.string),
  type: d.oneOf(["numeric", "enum", "text"] as const),
  latest: d.optional(
    d.nullable(
      d.object({
        value: d.nullable(engineeringValue),
        received_at: d.nullable(d.timestamp),
        limit_state: d.oneOf(["critical", "caution", "nominal", "no_data"] as const),
      }),
    ),
  ),
});

export const pointsReader = d.object({ points: d.array(point, 200) });
export type TelemetryPoint = Decoded<typeof point>;

export function fetchPoints(
  missionId: string,
  query: Readonly<{ spacecraftId?: string; q: string; limit?: number }>,
  signal?: AbortSignal,
): Promise<ApiResult<Decoded<typeof pointsReader>>> {
  const params = new URLSearchParams({ q: query.q, limit: String(query.limit ?? 50) });
  if (query.spacecraftId) params.set("spacecraft_id", query.spacecraftId);
  return request(
    `/missions/${encodeURIComponent(missionId)}/telemetry/points?${params.toString()}`,
    pointsReader,
    signal ? { signal } : {},
  );
}
