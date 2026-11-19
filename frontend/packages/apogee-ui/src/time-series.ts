/**
 * Scale and path math for TrendChart. Plain data in, SVG path strings out; no Vue, no domain
 * types (so the chart can move to @cadence/apogee-ui as ApTimeSeries unchanged).
 */

export type SeriesPoint = Readonly<{ t: number; min: number; mean: number; max: number }>;
export type LimitSegment = Readonly<{
  from: number;
  to: number;
  value: number;
  kind: "caution" | "crit";
  side: "low" | "high";
}>;
export type TimeWindow = Readonly<{ from: number; to: number }>;

/**
 * Extra series drawn as lines without a band. Tones are grays (never status hues) and dashes
 * tell series apart without color (OpsLists §Telemetry).
 */
export type ComparisonSeries = Readonly<{
  points: readonly SeriesPoint[];
  tone: "readout" | "text-2" | "text-3" | "text-4";
  dash: "solid" | "dashed" | "dotted";
  /** Name in the hover readout. */
  name?: string | undefined;
}>;

/**
 * A labelled span behind the plot (ux: pass spans AOS–LOS with the station code; outages;
 * an alarm episode). `pass` is a faint wash, `outage` the outage hatch, `episode` the severity's
 * wash (`severity`, default caution); the label sits at the top edge.
 */
export type TimeBand = Readonly<{
  from: number;
  to: number;
  kind: "pass" | "outage" | "episode";
  severity?: "caution" | "crit" | undefined;
  label?: string | undefined;
}>;
/**
 * A marked moment (a sample to point at): a ring on the series at `t` plus a dashed vertical, or
 * the vertical alone when the series has no value there. `series` names a comparison series (its
 * `name`); omitted = the main series. `label` is read out (the shape and the text carry it, not
 * colour alone).
 */
export type TimeMark = Readonly<{ t: number; label: string; series?: string | undefined }>;
export type Domain = readonly [number, number];

const f = (n: number) => (Math.round(n * 10) / 10).toString();

/** y-domain covering the data and every limit drawn, padded so lines don't touch the frame. */
export function yDomain(
  series: readonly (readonly SeriesPoint[])[],
  limits: readonly LimitSegment[],
  pad = 0.08,
): Domain {
  const values = [
    ...series.flatMap((points) => points.flatMap((p) => [p.min, p.max])),
    ...limits.map((l) => l.value),
  ];
  if (values.length === 0) return [0, 1];
  let lo = Math.min(...values);
  let hi = Math.max(...values);
  if (lo === hi) {
    const spread = Math.abs(lo) * 0.05 || 1;
    lo -= spread;
    hi += spread;
  }
  const margin = (hi - lo) * pad;
  return [lo - margin, hi + margin];
}

/**
 * The point a crosshair at `t` reads: the nearest one, and only within half a bucket (or
 * `maxGapMs`) of `t`, so a readout never claims a value inside a gap.
 */
export function pointAt(
  points: readonly SeriesPoint[],
  t: number,
  maxGapMs: number,
): SeriesPoint | null {
  let best: SeriesPoint | null = null;
  for (const p of points) if (!best || Math.abs(p.t - t) < Math.abs(best.t - t)) best = p;
  return best && Math.abs(best.t - t) <= maxGapMs ? best : null;
}

export const scale =
  (domainFrom: number, domainTo: number, rangeFrom: number, rangeTo: number) => (value: number) =>
    rangeFrom + ((value - domainFrom) / (domainTo - domainFrom || 1)) * (rangeTo - rangeFrom);

/**
 * Splits the series where consecutive points are further apart than a bucket allows: the
 * server omits empty buckets, and a line across a gap would claim data that doesn't exist.
 * With `stepMs` (the server's bucket width) a gap is > 1.5 buckets; without it, > 2.5× the
 * median spacing (which can't detect a gap in a 3-point series, hence prefer `stepMs`).
 */
export function runs(
  points: readonly SeriesPoint[],
  stepMs: number | null = null,
): SeriesPoint[][] {
  if (points.length < 2) return points.length ? [[...points]] : [];
  let limit: number;
  if (stepMs !== null && stepMs > 0) {
    limit = stepMs * 1.5;
  } else {
    const steps = points.slice(1).map((p, i) => p.t - (points[i]?.t ?? p.t));
    const sorted = [...steps].sort((a, b) => a - b);
    limit = (sorted[Math.floor(sorted.length / 2)] ?? 0) * 2.5;
  }
  const out: SeriesPoint[][] = [[]];
  points.forEach((p, i) => {
    const prev = points[i - 1];
    if (prev && limit > 0 && p.t - prev.t > limit) out.push([]);
    out.at(-1)?.push(p);
  });
  return out;
}

/** Half-width (viewBox units) of the mark drawn for an isolated bucket, which has no line. */
const LONE = 3;

export function linePath(
  points: readonly SeriesPoint[],
  x: (t: number) => number,
  y: (v: number) => number,
  stepMs: number | null = null,
): string {
  return runs(points, stepMs)
    .map((run) => {
      const only = run.length === 1 ? run[0] : undefined;
      if (only) return `M${f(x(only.t) - LONE)} ${f(y(only.mean))}H${f(x(only.t) + LONE)}`;
      return run.map((p, i) => `${i ? "L" : "M"}${f(x(p.t))} ${f(y(p.mean))}`).join("");
    })
    .join("");
}

/** Closed min–max band per run; an isolated bucket becomes a thin min–max bar. */
export function envelopePath(
  points: readonly SeriesPoint[],
  x: (t: number) => number,
  y: (v: number) => number,
  stepMs: number | null = null,
): string {
  return runs(points, stepMs)
    .map((run) => {
      const only = run.length === 1 ? run[0] : undefined;
      if (only) {
        const cx = x(only.t);
        return `M${f(cx - LONE / 2)} ${f(y(only.max))}H${f(cx + LONE / 2)}V${f(y(only.min))}H${f(cx - LONE / 2)}Z`;
      }
      const top = run.map((p, i) => `${i ? "L" : "M"}${f(x(p.t))} ${f(y(p.max))}`).join("");
      const bottom = [...run]
        .reverse()
        .map((p) => `L${f(x(p.t))} ${f(y(p.min))}`)
        .join("");
      return `${top}${bottom}Z`;
    })
    .join("");
}

const STEPS_MS = [1, 2, 5, 10, 15, 30]
  .map((m) => m * 60_000)
  .concat([1, 2, 3, 6, 12, 24].map((h) => h * 3_600_000));

/** Round-time ticks (UTC-aligned) giving at most `max` labels across the window. */
export function timeTicks(window: TimeWindow, max = 6): number[] {
  const span = window.to - window.from;
  const step = STEPS_MS.find((s) => span / s <= max) ?? 86_400_000;
  const first = Math.ceil(window.from / step) * step;
  const ticks: number[] = [];
  for (let t = first; t <= window.to; t += step) ticks.push(t);
  return ticks;
}

/** Up to `count` evenly spaced value ticks, rounded to a readable step. */
export function valueTicks(domain: Domain, count = 3): number[] {
  const [lo, hi] = domain;
  const raw = (hi - lo) / (count + 1);
  const magnitude = 10 ** Math.floor(Math.log10(raw || 1));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * magnitude).find((s) => s >= raw) ?? raw;
  const ticks: number[] = [];
  for (let v = Math.ceil(lo / step) * step; v <= hi; v += step)
    ticks.push(Number(v.toPrecision(12)));
  return ticks;
}
