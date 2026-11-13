import { formatDuration } from "@/ui";
import { stationCode, type PlanDetail } from "./api.ts";

/**
 * K1 C · the focused spacecraft's day (ScheduleFlow C): its drafted passes on a 24 h strip and
 * the gaps between them. Positions are fractions of the window (0..1). Gaps are measured only
 * between passes inside the window: the day's edges border another day's plan, which this
 * read doesn't have. The server sends no gap limit yet (scheduling.md S4), so a gap is a
 * measure here, not a verdict.
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
}>;
export type FocusDay = Readonly<{
  ruleMet: boolean | null;
  contacts: Readonly<{ have: number; need: number | null }> | null;
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
  const raw = own.slice(1).flatMap((cur, i) => {
    const prevEnd = Math.max(...own.slice(0, i + 1).map((o) => o.to));
    const seconds = (cur.from - prevEnd) / 1000;
    return seconds > 0 ? [{ fromMs: prevEnd, toMs: cur.from, seconds }] : [];
  });
  const longestGapSeconds = raw.length ? Math.max(...raw.map((g) => g.seconds)) : null;
  const gaps = raw.map((g) => ({
    from: at(g.fromMs),
    to: at(g.toMs),
    seconds: g.seconds,
    text: gapText(g.seconds),
    longest: g.seconds === longestGapSeconds,
  }));
  const demand = plan.demand.spacecraft.find((s) => s.spacecraft_id === spacecraftId);
  return {
    ruleMet: demand?.rule_met ?? null,
    contacts: demand?.contacts ?? null,
    passes,
    gaps,
    longestGapSeconds,
  };
}
