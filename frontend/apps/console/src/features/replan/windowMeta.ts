import { isKnown } from "@/api/index.ts";
import type { RepairInfo } from "@/features/scheduling/index.ts";

/** §4 short time: `02:45`, with the date when it isn't today's. */
function at(iso: string, now: Date): string {
  const today = iso.slice(0, 10) === now.toISOString().slice(0, 10);
  return `${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}`;
}

/** §4 duration: "8 h", "1 h 30 min", "45 min". */
export function hoursWord(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (h && m) return `${h} h ${m} min`;
  return h ? `${h} h` : `${m} min`;
}

/** "from Northlight's change at 02:45Z" / "from the station outage at 02:45Z"; no cause, no clause. */
function causeWords(c: RepairInfo["cause"], now: Date): string | null {
  if (!c || !isKnown(c.kind)) return null;
  const when = `at ${at(c.since, now)}Z`;
  return c.kind === "provider_change"
    ? `from ${c.provider_name ? `${c.provider_name}'s` : "the provider's"} change ${when}`
    : `from the station outage ${when}`;
}

/**
 * ux U76: Re-plan's header meta (K2), "Window 02:45–10:45Z · from Northlight's change at 02:45Z ·
 * 8 h by the planning policy · attempt 2 of 3". The last attempt reads as caution; with none left,
 * the attempt part goes and `noneLeft` says why the re-plan can't start.
 */
export function windowMeta(r: RepairInfo, now: Date = new Date()) {
  const next = r.attempts.used + 1;
  const last = r.available && next >= r.attempts.max;
  const attempt = !r.available
    ? null
    : last
      ? `attempt ${next} of ${r.attempts.max}, the last the policy allows`
      : `attempt ${next} of ${r.attempts.max}`;
  const text = [
    `Window ${at(r.window.from, now)}–${at(r.window.to, now)}Z`,
    causeWords(r.cause, now),
    `${hoursWord(r.horizon_seconds)} by the planning policy`,
    attempt,
  ]
    .filter((p): p is string => p !== null)
    .join(" · ");
  return { text, last, noneLeft: r.available ? null : noneLeftLine(r.attempts) };
}

/** U76: "No re-plan attempts left (3 of 3). The planning policy sets the limit." */
export const noneLeftLine = (a: Readonly<{ used: number; max: number }>) =>
  `No re-plan attempts left (${a.used} of ${a.max}). The planning policy sets the limit.`;
