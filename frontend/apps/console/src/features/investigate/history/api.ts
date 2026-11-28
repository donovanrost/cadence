import type { MissionId } from "@/api/index.ts";
import {
  actor as sharedActor,
  decoders as d,
  isKnown,
  request,
  vocabularyText,
  type ApiResult,
  type Decoded,
  pointId as pointIdReader,
} from "@/api/index.ts";
import {
  conditionWords,
  engineeringValue,
  formatValue,
  sourceStates,
  withUnit,
} from "@/features/alarms/index.ts";

/**
 * Investigate › History (Investigate.md §Tab · History, api's episode reads): this spacecraft's
 * alarm episodes over 90 days, and prior occurrences of one alarm. Optional fields are ones asked
 * of api after ux's spec (counts, retention, peak, cleared_by); the UI says less without them.
 */
/** The shared entity (typing §12 A5). */
const actor = sharedActor;
const sources = ["catalog_monitoring", "ground_limit"] as const;

/** How an occurrence can end (alarms-console.md); a way this console doesn't know reads "Ended". */
const endings = ["back_in_limits", "source_stopped", "rule_retired"] as const;
const ENDED: Readonly<Record<(typeof endings)[number], string>> = {
  back_in_limits: "Back in limits",
  source_stopped: "Source stopped reporting it",
  rule_retired: "Its rule was retired",
};

export const occurrenceReader = d.object({
  id: d.token,
  source: d.knownText(sources),
  status: d.known(["new", "acknowledged", "cleared"] as const),
  severity: d.oneOf(["critical", "caution"] as const),
  peak_severity: d.nullable(d.oneOf(["critical", "caution"] as const)),
  /** ground: yellow_low | yellow_high | red_low | red_high; catalog: watch | warning | … */
  condition: d.nullable(d.knownText(sourceStates)),
  /** low | high for ground limits (the PEAK side); null for catalog alarms (no PEAK). */
  direction: d.nullable(d.oneOf(["low", "high"] as const)),
  point: d.object({ id: pointIdReader, name: d.string, unit: d.nullable(d.string) }),
  opened_at: d.timestamp,
  cleared_at: d.nullable(d.timestamp),
  duration_s: d.nullable(d.integer),
  /**
   * null while still open; an unknown way of ending reads "Ended". `rule_retired` (#451 T3b): a
   * monitoring change set retired the catalog alarm's policy while it was open, which closed it.
   */
  ended: d.nullable(d.known(endings)),
  cleared_unacknowledged: d.boolean,
  acknowledged_by: d.nullable(actor),
  first_value: d.nullable(engineeringValue),
  last_value: d.nullable(engineeringValue),
  /** U68 R5: the sample that opened it, when the read carries it (ux U71: H2 rings it). */
  trigger: d.optional(
    d.nullable(
      d.object({
        sample_id: d.nullable(d.token),
        at: d.timestamp,
        /** api D1 part A: makes the Sample aside's read exact (U80). */
        receipt_time: d.optional(d.nullable(d.timestamp)),
      }),
    ),
  ),
});
export type Occurrence = Decoded<typeof occurrenceReader>;

const counts = d.object({ d7: d.integer, d30: d.integer, d90: d.integer });

const listReader = d.object({
  counts,
  /** null = kept indefinitely (counts show normally). */
  retention_days: d.nullable(d.integer),
  items: d.array(occurrenceReader, 200),
  next_before: d.nullable(d.string),
});
export type EpisodeList = Decoded<typeof listReader>;

/** Counts include this episode; items are the ones opened before it; median over cleared ones. */
const historyReader = d.object({
  counts,
  median_duration_s: d.nullable(d.integer),
  first_opened_at: d.nullable(d.timestamp),
  retention_days: d.nullable(d.integer),
  items: d.array(occurrenceReader, 200),
  next_before: d.nullable(d.string),
});
export type EpisodeHistory = Decoded<typeof historyReader>;

const base = (m: string) => `/missions/${encodeURIComponent(m)}`;

export function fetchEpisodeList(
  missionId: MissionId,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<EpisodeList>> {
  return request(
    `${base(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/alarm-episodes?limit=200`,
    listReader,
    signal ? { signal } : {},
  );
}

export function fetchEpisodeHistory(
  missionId: MissionId,
  episodeId: string,
  scope: "alarm" | "point",
  signal?: AbortSignal,
): Promise<ApiResult<EpisodeHistory>> {
  return request(
    `${base(missionId)}/alarm-episodes/${encodeURIComponent(episodeId)}/history?scope=${scope}&limit=200`,
    historyReader,
    signal ? { signal } : {},
  );
}

const SOURCE_TAG: Readonly<Record<(typeof sources)[number], string>> = {
  catalog_monitoring: "Catalog",
  ground_limit: "Ground limits",
};

/** "Catalog" / "Ground limits"; the server's text for a source this console doesn't know. */
export const sourceTag = (o: Occurrence) => vocabularyText(o.source, SOURCE_TAG);

/** "VBAT below red low" (U16 words; the raw state when unknown). */
export function conditionLine(o: Occurrence): string {
  const raw =
    o.condition === null ? null : isKnown(o.condition) ? o.condition : o.condition.unrecognized;
  return `${o.point.name} ${conditionWords(raw) ?? raw?.replaceAll("_", " ") ?? "out of limits"}`;
}

/** "38m", "2h 14m", "<1m" (minutes are enough for episode durations; ux). */
export function minutes(seconds: number): string {
  const m = Math.round(seconds / 60);
  if (m < 1) return "<1m";
  const h = Math.floor(m / 60);
  return h ? `${h}h ${m % 60}m` : `${m}m`;
}

const hhmm = (iso: string) => `${iso.slice(5, 10)} ${iso.slice(11, 16)}Z`;
export const shortTime = hhmm;

/** "2h 14m", or null while open (the row shows a live T+ instead). */
export const durationWords = (o: Occurrence) =>
  o.duration_s === null ? null : minutes(o.duration_s);

/** How it ended (ux 7631176e). Acknowledgement is its own column. */
export function howItEnded(o: Occurrence): string {
  if (o.ended === "unrecognized") return "Ended"; // U20: plainly, never a guess
  if (o.ended !== null) return ENDED[o.ended];
  return o.cleared_at === null ? "Still open" : "Cleared";
}

export const valueWords = (v: number | string | boolean | null, unit: string | null) =>
  v === null ? "—" : (withUnit(formatValue(v), unit) ?? "—");

/** "4th time in 30 days · median 38m" (counts include this episode). */
export function occurrenceSummary(h: EpisodeHistory | null): string | null {
  if (!h) return null;
  const n = h.counts.d30;
  const nth = n % 100 >= 11 && n % 100 <= 13 ? "th" : (["th", "st", "nd", "rd"][n % 10] ?? "th");
  const median = h.median_duration_s;
  return `${n <= 1 ? "First time" : `${n}${nth} time`} in 30 days${median !== null ? ` · median ${minutes(median)}` : ""}`;
}

/**
 * PEAK from the chart's own buckets (ux 7631176e): the lowest bucket min for a low condition, the
 * highest max for a high one, over the episode's span. M10 buckets carry min/max, so it's exact to
 * bucket resolution. Catalog alarms (no direction) get none.
 */
export function peakFrom(
  o: Occurrence,
  buckets: readonly Readonly<{ t: number; min: number; max: number }>[],
  now: number,
): Readonly<{ value: number; t: number }> | null {
  if (o.direction === null) return null;
  const from = Date.parse(o.opened_at);
  const to = o.cleared_at ? Date.parse(o.cleared_at) : now;
  let best: { value: number; t: number } | null = null;
  for (const b of buckets) {
    if (b.t < from || b.t > to) continue;
    const v = o.direction === "low" ? b.min : b.max;
    if (!best || (o.direction === "low" ? v < best.value : v > best.value))
      best = { value: v, t: b.t };
  }
  return best;
}
