import type { OpState } from "@/ui";
import type { Alarm, Thresholds } from "@/features/alarms/index.ts";
import { fleetOpState, fleetStateWord, type FleetSpacecraft } from "@/features/fleet/index.ts";
import type { History, LimitIntervals } from "./api.ts";
import { runs, type LimitSegment, type SeriesPoint, type TimeWindow } from "@/ui";

/** Pure logic for Investigate (J2). Spec: docs/apogee/ux/screens/Investigate.md. */

export const RANGES = [
  { value: "1h", label: "1H", ms: 3_600_000 },
  { value: "6h", label: "6H", ms: 6 * 3_600_000 },
  { value: "24h", label: "24H", ms: 24 * 3_600_000 },
] as const;
export type RangeKey = (typeof RANGES)[number]["value"];
/** `6 ORB` needs an orbit period, which the backend doesn't have yet, so the default is 6H. */
export const DEFAULT_RANGE: RangeKey = "6h";

export function rangeWindow(range: RangeKey, now: Date): TimeWindow {
  const ms = RANGES.find((r) => r.value === range)?.ms ?? 6 * 3_600_000;
  return { from: now.getTime() - ms, to: now.getTime() };
}

/** ux U71 A7: the range's length centred on `at` (a sample to show), never past now. */
export function centredWindow(range: RangeKey, at: number, now: Date): TimeWindow {
  const ms = RANGES.find((r) => r.value === range)?.ms ?? 6 * 3_600_000;
  const to = Math.min(now.getTime(), at + ms / 2);
  return { from: to - ms, to };
}

/**
 * The alarm B1 shows: the one named in the URL (`?alarm=` id, or `?point=` from the episode-based
 * Alarms list) if present, else the worst (server order).
 */
export function pickAlarm(
  alarms: readonly Alarm[],
  alarmId: string | null,
  pointId: string | null = null,
): Alarm | null {
  const named =
    (alarmId !== null ? alarms.find((alarm) => alarm.id === alarmId) : undefined) ??
    (pointId !== null ? alarms.find((alarm) => alarm.point.id === pointId) : undefined);
  if (named) return named;
  return alarms.find((alarm) => alarm.active) ?? null;
}

/** §B1 no active alarm: the spacecraft's most recently cleared episode (it's shown back in limits). */
export function lastCleared<E extends Readonly<{ cleared_at: string | null }>>(
  episodes: readonly E[],
): E | null {
  let best: E | null = null;
  for (const e of episodes)
    if (
      e.cleared_at &&
      (!best?.cleared_at || Date.parse(e.cleared_at) > Date.parse(best.cleared_at))
    )
      best = e;
  return best;
}

export const toSeries = (history: History): SeriesPoint[] =>
  history.buckets.map((b) => ({ t: Date.parse(b.t), min: b.min, mean: b.mean, max: b.max }));

const BANDS = [
  { key: "red_low", kind: "crit", side: "low" },
  { key: "yellow_low", kind: "caution", side: "low" },
  { key: "yellow_high", kind: "caution", side: "high" },
  { key: "red_high", kind: "crit", side: "high" },
] as const satisfies readonly {
  key: keyof Thresholds;
  kind: LimitSegment["kind"];
  side: LimitSegment["side"];
}[];

function segmentsFor(thresholds: Thresholds, from: number, to: number): LimitSegment[] {
  return BANDS.flatMap(({ key, kind, side }) => {
    const value = thresholds[key];
    return value === null ? [] : [{ from, to, value, kind, side }];
  });
}

/**
 * Limit segments over the window from the definition intervals (bands can change mid-window).
 * Without intervals, the alarm's own thresholds span the window: some definitions have no
 * lifecycle interval but still carry bands (api M11 note).
 */
export function limitSegments(
  intervals: LimitIntervals | null,
  window: TimeWindow,
  fallback: Thresholds | null,
): LimitSegment[] {
  const list = intervals?.intervals ?? [];
  if (list.length === 0) return fallback ? segmentsFor(fallback, window.from, window.to) : [];
  return list.flatMap((interval) => {
    const from = Math.max(window.from, Date.parse(interval.from));
    const to = Math.min(window.to, interval.to === null ? window.to : Date.parse(interval.to));
    return to > from ? segmentsFor(interval.thresholds, from, to) : [];
  });
}

/** A rate over less data than this would be extrapolation, not a measurement. */
export const MIN_RATE_SPAN_MS = 15 * 60_000;

/**
 * Change per hour over the latest contiguous run (no gaps, qa #8), and only when that run spans
 * at least MIN_RATE_SPAN_MS; otherwise null (the tile shows a dash).
 */
export function ratePerHour(
  series: readonly SeriesPoint[],
  stepMs: number | null = null,
): number | null {
  const run = runs(series, stepMs).at(-1) ?? [];
  const first = run[0];
  const last = run.at(-1);
  if (!first || !last || last.t - first.t < MIN_RATE_SPAN_MS) return null;
  return ((last.mean - first.mean) / (last.t - first.t)) * 3_600_000;
}

const num = (v: number) => (Math.abs(v) >= 100 ? v.toFixed(0) : v.toFixed(2).replace(/\.?0+$/, ""));

/** Chart sentence from first/last/min and crossings (spec B1 aria-label); never a finding. */
export function trendSentence(
  pointName: string,
  rangeLabel: string,
  series: readonly SeriesPoint[],
  limits: readonly LimitSegment[],
): string {
  const first = series[0];
  const last = series.at(-1);
  if (!first || !last) return `${pointName} over ${rangeLabel}: no data in this window.`;
  const direction = last.mean > first.mean ? "rising" : last.mean < first.mean ? "falling" : "flat";
  const lo = Math.min(...series.map((p) => p.min));
  const hi = Math.max(...series.map((p) => p.max));
  const crit = limits.filter((l) => l.kind === "crit");
  const crossed = crit.find((l) => (l.side === "low" ? lo < l.value : hi > l.value));
  return `${pointName} over ${rangeLabel}, ${direction} from ${num(first.mean)} to ${num(last.mean)}, range ${num(lo)} to ${num(hi)}${
    crossed ? `, crossing the ${num(crossed.value)} red limit` : ""
  }.`;
}

/** Previous/next spacecraft for `[` `]`: same plane by slot, else the whole fleet by SCID. */
export function neighbours(
  fleet: readonly FleetSpacecraft[],
  sc: FleetSpacecraft,
): { prev: FleetSpacecraft | null; next: FleetSpacecraft | null } {
  const peers =
    sc.plane === null
      ? [...fleet].sort((a, b) => a.scid - b.scid)
      : fleet
          .filter((other) => other.plane === sc.plane)
          .sort((a, b) => (a.slot ?? a.scid) - (b.slot ?? b.scid) || a.scid - b.scid);
  const i = peers.findIndex((other) => other.id === sc.id);
  return { prev: peers[i - 1] ?? null, next: peers[i + 1] ?? null };
}

/** B4 v1: same plane, same point, currently caution or critical (U10 naming: "same point in limits"). */
export function sisters(
  alarms: readonly Alarm[],
  fleet: readonly FleetSpacecraft[],
  sc: FleetSpacecraft,
  pointId: string,
): { sc: FleetSpacecraft; alarm: Alarm }[] {
  if (sc.plane === null) return [];
  const inPlane = new Map(
    fleet.filter((o) => o.plane === sc.plane && o.id !== sc.id).map((o) => [o.id, o]),
  );
  return alarms.flatMap((alarm) => {
    const other = alarm.spacecraft_id ? inPlane.get(alarm.spacecraft_id) : undefined;
    return other && alarm.active && alarm.point.id === pointId ? [{ sc: other, alarm }] : [];
  });
}

/**
 * Hero status (ux review fix 1): the worst *active* alarm outranks the fleet state, including
 * `never_heard` (alarm + never heard is a data race, not a state). Label: word · subsystem.
 */
export function heroStatus(
  sc: FleetSpacecraft,
  alarms: readonly Alarm[] | null,
): { state: OpState; label: string } {
  const active = (alarms ?? []).filter((a) => a.active);
  const worst =
    active.find((a) => a.severity === "critical") ?? active.find((a) => a.severity === "caution");
  if (worst) {
    const what = worst.point.subsystem ?? worst.point.name;
    return worst.severity === "critical"
      ? { state: "crit", label: `Critical · ${what}` }
      : { state: "caution", label: `Caution · ${what}` };
  }
  const point = sc.worst_point;
  const word = fleetStateWord(sc.state);
  return { state: fleetOpState(sc.state), label: point ? `${word} · ${point.point_name}` : word };
}

/** `−0.43` per hour: two decimals, U+2212 for negatives. */
export const formatRate = (perHour: number) =>
  `${perHour < 0 ? "−" : perHour > 0 ? "+" : ""}${Math.abs(perHour).toFixed(2)}`;

/**
 * §11c(D) D11 (ux): a capped history read keeps the EARLIEST samples (api, M10 fallback), so the
 * plot is whole from the read's start to its last bucket's end. Null when the read wasn't cut.
 * Times per §4: HH:MMZ, with MM-DD on both ends when the shown span crosses days.
 */
export function truncatedLine(
  h: Readonly<{ truncated: boolean; from: string; buckets: readonly { t_end: string }[] }>,
): string | null {
  if (!h.truncated) return null;
  const from = h.from;
  const to = h.buckets.at(-1)?.t_end ?? h.from;
  const days = from.slice(0, 10) !== to.slice(0, 10);
  const at = (iso: string) => `${days ? `${iso.slice(5, 10)} ` : ""}${iso.slice(11, 16)}Z`;
  return (
    `This range has more samples than one read returns (20,000). The plot shows ${at(from)} to ` +
    `${at(to)}; samples after ${at(to)} weren't read. Pick a shorter or later range to see the rest.`
  );
}
