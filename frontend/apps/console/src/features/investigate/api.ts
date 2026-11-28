import type { PointId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import {
  spacecraftId as spacecraftIdReader,
  type SpacecraftId,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
  pointId as pointIdReader,
} from "@/api/index.ts";
import { thresholdsReader } from "@/features/alarms/index.ts";

/** Contracts: docs/apogee/api/ops.md, M10 (history) and M11 (limit intervals). */

export type HistoryWindow = Readonly<{ from: Date; to: Date }>;

const bucket = d.object({
  t: d.timestamp,
  t_end: d.timestamp,
  min: d.number,
  max: d.number,
  mean: d.number,
  count: d.integer,
});

const historyShape = d.object({
  point_id: pointIdReader,
  unit: d.nullable(d.string),
  description: d.nullable(d.string),
  spacecraft_id: d.nullable(spacecraftIdReader),
  from: d.timestamp,
  to: d.timestamp,
  bucket_width_ms: d.integer,
  truncated: d.boolean,
  buckets: d.array(bucket, 2_000),
});

/** Validates what the chart relies on: min ≤ mean ≤ max and buckets in time order. */
export const historyReader: d.Reader<Decoded<typeof historyShape>> = (value, path = "") => {
  const history = historyShape(value, path);
  let previous = -Infinity;
  history.buckets.forEach((b, i) => {
    if (!(b.min <= b.mean && b.mean <= b.max))
      throw new d.DecodeError(`buckets[${i}]`, "min ≤ mean ≤ max");
    const t = Date.parse(b.t);
    if (t < previous) throw new d.DecodeError(`buckets[${i}].t`, "ascending time");
    previous = t;
  });
  return history;
};
export type History = Decoded<typeof historyReader>;

const interval = d.object({
  from: d.timestamp,
  to: d.nullable(d.timestamp),
  limit_set_name: d.nullable(d.string),
  limit_definition_id: d.nullable(d.token),
  limit_definition_version: d.nullable(d.integer),
  // A limit definition's scope_type is an open string column; these are the ones in use.
  scope: d.object({
    type: d.knownText(["mission", "spacecraft", "link", "transport"] as const),
    ref: d.nullable(d.token),
  }),
  thresholds: thresholdsReader,
});

export const intervalsReader = d.object({
  point_id: pointIdReader,
  spacecraft_id: d.nullable(spacecraftIdReader),
  from: d.timestamp,
  to: d.timestamp,
  intervals: d.array(interval, 1_000),
});
export type LimitIntervals = Decoded<typeof intervalsReader>;

const pointPath = (missionId: MissionId, prefix: string, pointId: PointId) =>
  `/missions/${encodeURIComponent(missionId)}/${prefix}/points/${encodeURIComponent(pointId)}`;

function windowQuery(
  window: HistoryWindow,
  spacecraftId: SpacecraftId,
  extra: Record<string, string>,
) {
  return new URLSearchParams({
    spacecraft_id: spacecraftId,
    from: window.from.toISOString(),
    to: window.to.toISOString(),
    ...extra,
  }).toString();
}

export function fetchHistory(
  missionId: MissionId,
  pointId: PointId,
  spacecraftId: SpacecraftId,
  window: HistoryWindow,
  signal?: AbortSignal,
): Promise<ApiResult<History>> {
  const query = windowQuery(window, spacecraftId, { max_points: "400" });
  return request(
    `${pointPath(missionId, "telemetry", pointId)}/history?${query}`,
    historyReader,
    signal ? { signal } : {},
  );
}

export function fetchLimitIntervals(
  missionId: MissionId,
  pointId: PointId,
  spacecraftId: SpacecraftId,
  window: HistoryWindow,
  signal?: AbortSignal,
): Promise<ApiResult<LimitIntervals>> {
  const query = windowQuery(window, spacecraftId, {});
  return request(
    `${pointPath(missionId, "limits", pointId)}/intervals?${query}`,
    intervalsReader,
    signal ? { signal } : {},
  );
}
