import { formatDuration } from "@/ui";
import { stationCode, type PlanDetail } from "./api.ts";

/**
 * K1 C · the focused spacecraft's day (ScheduleFlow C): its drafted passes on a 24 h strip and
 * the gaps between them. Positions are fractions of the window (0..1). Gaps follow the
 * server's measure (domain c38bb5de): LOS → next AOS, the day's edges included. The server's
 * `longest_gap` wins when present; with no limit yet (`limit_seconds` null) it's a measure, not
 * a verdict.
 */
export type StripPass = Readonly<{
  id: string;
  from: number;
  to: number;
  station: string;
  text: string;
}>;
export type StripGap = Readonly<{
  from: number;
  to: number;
  seconds: number;
  text: string;
  longest: boolean;
  /** The longest gap past the rule's limit (#74): caution + 2px on the strip (ux). */
  over: boolean;
}>;
export type FocusDay = Readonly<{
  ruleMet: boolean | null;
  contacts: Readonly<{ have: number; need: number | null }> | null;
  /** Passes whose booking will request an uplink leg (requested, not confirmed). */
  uplink: Readonly<{ have: number; need: number | null }> | null;
  /** The server's limit when a rule carries one (max_gap_seconds, pending); null today. */
  gapLimitSeconds: number | null;
  passes: readonly StripPass[];
  gaps: readonly StripGap[];
  longestGapSeconds: number | null;
}>;

const hm = (iso: string) => iso.slice(11, 16);
/** `11h20` on the strip (ux board), `45m` under an hour. */
export function gapText(seconds: number): string {
  const total = Math.round(seconds / 60);
  const h = Math.floor(total / 60);
  const m = total % 60;
  return h > 0 ? `${h}h${String(m).padStart(2, "0")}` : formatDuration(m * 60).replace(" 00s", "");
}

export function focusDay(
  plan: Pick<PlanDetail, "passes" | "demand">,
  spacecraftId: string,
  window: Readonly<{ from: number; to: number }>,
): FocusDay {
  const span = window.to - window.from;
  const at = (ms: number) => Math.min(1, Math.max(0, (ms - window.from) / span));
  const own = plan.passes
    .filter((p) => p.spacecraft_id === spacecraftId)
    .map((p) => ({ p, from: Date.parse(p.starts_at), to: Date.parse(p.ends_at) }))
    .filter(({ from, to }) => to > window.from && from < window.to)
    .sort((a, b) => a.from - b.from);
  const passes = own.map(({ p, from, to }) => ({
    id: p.snapshot_id,
    from: at(from),
    to: at(to),
    station: stationCode(p.station),
    text: `${stationCode(p.station)} ${hm(p.starts_at)}–${hm(p.ends_at)}Z`,
  }));
  // Covered stretches end at the latest LOS so far; each gap runs to the next AOS.
  const raw: { fromMs: number; toMs: number; seconds: number }[] = [];
  let coveredTo = window.from;
  for (const o of own) {
    if (o.from > coveredTo)
      raw.push({ fromMs: coveredTo, toMs: o.from, seconds: (o.from - coveredTo) / 1000 });
    coveredTo = Math.max(coveredTo, o.to);
  }
  if (own.length && window.to > coveredTo)
    raw.push({ fromMs: coveredTo, toMs: window.to, seconds: (window.to - coveredTo) / 1000 });
  const demand = plan.demand.spacecraft.find((s) => s.spacecraft_id === spacecraftId);
  const server = demand?.longest_gap ?? null;
  const clientMax = raw.length ? Math.max(...raw.map((g) => g.seconds)) : null;
  const serverFrom = server?.from ? Date.parse(server.from) : null;
  const isLongest = (g: { fromMs: number; seconds: number }) =>
    serverFrom !== null ? Math.abs(g.fromMs - serverFrom) < 1000 : g.seconds === clientMax;
  const gaps = raw.map((g) => ({
    from: at(g.fromMs),
    to: at(g.toMs),
    seconds: g.seconds,
    text: gapText(g.seconds),
    longest: isLongest(g),
    over: isLongest(g) && server?.limit_seconds != null && g.seconds > server.limit_seconds,
  }));
  return {
    ruleMet: demand?.rule_met ?? null,
    contacts: demand?.contacts ?? null,
    uplink: demand?.uplink_passes ?? null,
    gapLimitSeconds: server?.limit_seconds ?? null,
    passes,
    gaps,
    longestGapSeconds: server ? server.seconds : clientMax,
  };
}

/**
 * S4 effect on the focused spacecraft's longest gap: "Longest gap 6h10 → 3h05" (domain c38bb5de).
 * Null unless both numbers are known and the pass shortens it; a measure, not a verdict.
 */
export function gapEffect(
  before: number | null | undefined,
  after: number | null | undefined,
): string | null {
  if (before === null || before === undefined || after === null || after === undefined) return null;
  return after < before ? `Longest gap ${gapText(before)} → ${gapText(after)}` : null;
}

/** `03:10Z`, or `11-14 03:10Z` when not on the plan's day (§4 date prefix). */
function stamp(iso: string, day: string): string {
  const time = `${iso.slice(11, 16)}Z`;
  return iso.slice(0, 10) === day ? time : `${iso.slice(5, 10)} ${time}`;
}

/**
 * #74 Demand why (ux, ScheduleFlow K1): "No contact for 11h20, 03:10Z–14:30Z. The rule allows
 * 10h00." Null unless the server sent the gap, its span and the limit.
 */
export function gapSentence(
  gap:
    | Readonly<{
        seconds: number;
        limit_seconds: number | null;
        from: string | null;
        to: string | null;
      }>
    | null
    | undefined,
  day: string,
): string | null {
  if (!gap || gap.limit_seconds === null || !gap.from || !gap.to) return null;
  return `No contact for ${gapText(gap.seconds)}, ${stamp(gap.from, day)}–${stamp(gap.to, day)}. The rule allows ${gapText(gap.limit_seconds)}.`;
}
