/**
 * The one time and number formatting module (design-language §4). Components never format
 * dates themselves. All times are UTC; negatives and countdowns use U+2212.
 */

const MINUS = "−";
const pad = (n: number, width = 2) => String(Math.trunc(n)).padStart(width, "0");

function parts(date: Date) {
  return {
    y: date.getUTCFullYear(),
    mo: pad(date.getUTCMonth() + 1),
    d: pad(date.getUTCDate()),
    h: pad(date.getUTCHours()),
    mi: pad(date.getUTCMinutes()),
    s: pad(date.getUTCSeconds()),
  };
}

/** `02:41:17` */
export function formatClock(date: Date): string {
  const p = parts(date);
  return `${p.h}:${p.mi}:${p.s}`;
}

/** `02:41Z`: a time of day in a sentence ("activated at 02:41Z"). */
export function formatHourMinute(date: Date): string {
  const p = parts(date);
  return `${p.h}:${p.mi}Z`;
}

/** `2026-10-23 02:41:17Z` */
export function formatAbsolute(date: Date): string {
  const p = parts(date);
  return `${p.y}-${p.mo}-${p.d} ${p.h}:${p.mi}:${p.s}Z`;
}

/** `10-23 02:41Z` */
export function formatShort(date: Date): string {
  const p = parts(date);
  return `${p.mo}-${p.d} ${p.h}:${p.mi}Z`;
}

/**
 * `T−00:04:12` for a future target, `T+00:06:41` for a past one; past a day `T−4d 03:28:39`
 * (§4: hours never exceed 23).
 */
export function formatCountdown(target: Date, now: Date): string {
  const delta = Math.round((target.getTime() - now.getTime()) / 1000);
  const sign = delta > 0 ? MINUS : "+";
  const total = Math.abs(delta);
  const days = Math.floor(total / 86_400);
  const rest = total % 86_400;
  const clock = `${pad(rest / 3600)}:${pad((rest % 3600) / 60)}:${pad(rest % 60)}`;
  return `T${sign}${days > 0 ? `${days}d ` : ""}${clock}`;
}

/** `9m 12s`, `5h 40m`, `45s` */
export function formatDuration(seconds: number): string {
  const total = Math.max(0, Math.round(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}h ${pad(m)}m`;
  if (m > 0) return `${m}m ${pad(s)}s`;
  return `${s}s`;
}

const counts = new Intl.NumberFormat("en-US");

/** `4,812`; negatives with U+2212. */
export function formatCount(n: number): string {
  const text = counts.format(Math.abs(n));
  return n < 0 ? `${MINUS}${text}` : text;
}

/** `1 target`, `2 targets` */
export function plural(n: number, singular: string, pluralForm = `${singular}s`): string {
  return `${formatCount(n)} ${n === 1 ? singular : pluralForm}`;
}

/** Two-letter initials for the account button. */
export function initials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  const first = words[0]?.[0] ?? "";
  const last = words.length > 1 ? (words.at(-1)?.[0] ?? "") : (words[0]?.[1] ?? "");
  return (first + last).toUpperCase() || "?";
}

/** `10-23 02:59:40Z` */
export function formatDayTime(date: Date): string {
  const p = parts(date);
  return `${p.mo}-${p.d} ${p.h}:${p.mi}:${p.s}Z`;
}

/** `T−00:38:10`, `T+1d 02:00:00`: like formatCountdown but folds whole days. */
export function formatRelative(target: Date, now: Date): string {
  const delta = Math.round((target.getTime() - now.getTime()) / 1000);
  const sign = delta > 0 ? MINUS : "+";
  const total = Math.abs(delta);
  const days = Math.floor(total / 86_400);
  const rest = total % 86_400;
  const clock = `${pad(rest / 3600)}:${pad((rest % 3600) / 60)}:${pad(rest % 60)}`;
  return `T${sign}${days > 0 ? `${days}d ` : ""}${clock}`;
}

/** `MET 412:07:14:05` from a mission epoch (only when the mission defines one, decision U7). */
export function formatMet(at: Date, epoch: Date): string {
  const total = Math.max(0, Math.floor((at.getTime() - epoch.getTime()) / 1000));
  return `MET ${Math.floor(total / 86_400)}:${pad((total % 86_400) / 3600)}:${pad((total % 3600) / 60)}:${pad(total % 60)}`;
}
