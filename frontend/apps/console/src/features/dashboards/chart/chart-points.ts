export type PointMetadata = Record<string, unknown>;
export type ChartPoint = [timestampMs: number, value: number | null, metadata: PointMetadata];
export type EnvelopePoint = [
  timestampMs: number,
  min: number,
  max: number,
  metadata: PointMetadata,
];
export type ChartEnvelope = {
  kind: string;
  lower_field: string | null;
  upper_field: string | null;
  sample_count_field: string | null;
  points: EnvelopePoint[];
};

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
const finite = (value: unknown): value is number =>
  typeof value === "number" && Number.isFinite(value);
const text = (value: unknown) => (typeof value === "string" && value ? value : null);

export function normalizePoints(value: unknown): ChartPoint[] {
  if (!Array.isArray(value)) return [];
  const points: ChartPoint[] = [];
  for (const point of value) {
    if (!Array.isArray(point) || !finite(point[0]) || !(point[1] === null || finite(point[1])))
      continue;
    points.push([point[0], point[1], record(point[2]) ? point[2] : {}]);
  }
  return points;
}

export function normalizeEnvelope(value: unknown): ChartEnvelope | null {
  if (!record(value) || !Array.isArray(value.points)) return null;
  const points: EnvelopePoint[] = [];
  for (const point of value.points) {
    if (
      !Array.isArray(point) ||
      !finite(point[0]) ||
      !finite(point[1]) ||
      !finite(point[2]) ||
      point[1] > point[2]
    )
      continue;
    points.push([point[0], point[1], point[2], record(point[3]) ? point[3] : {}]);
  }
  if (!points.length) return null;
  return {
    kind: text(value.kind) ?? "min_max",
    lower_field: text(value.lower_field),
    upper_field: text(value.upper_field),
    sample_count_field: text(value.sample_count_field),
    points,
  };
}
