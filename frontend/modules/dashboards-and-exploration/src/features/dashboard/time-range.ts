import type { WorkspaceSnapshot } from "../workspace/contracts";

type Context = WorkspaceSnapshot["context"];

/** Mirrors Cadence.Dashboards.TimeRange quick ranges; sliding windows cap at 24 hours. */
export const quickRanges = [
  { from: "now-5m", label: "Last 5 minutes", seconds: 300 },
  { from: "now-15m", label: "Last 15 minutes", seconds: 900 },
  { from: "now-30m", label: "Last 30 minutes", seconds: 1_800 },
  { from: "now-1h", label: "Last 1 hour", seconds: 3_600 },
  { from: "now-3h", label: "Last 3 hours", seconds: 10_800 },
  { from: "now-6h", label: "Last 6 hours", seconds: 21_600 },
  { from: "now-12h", label: "Last 12 hours", seconds: 43_200 },
  { from: "now-24h", label: "Last 24 hours", seconds: 86_400 },
] as const;
export const maxSlidingSeconds = 86_400;
const maxRangeMs = 31 * 86_400_000;

export type TimeSelection =
  | { kind: "default" }
  | { kind: "sliding"; seconds: number }
  | { kind: "absolute"; from: string; to: string };

const spans = [
  [604_800, "w", "week"],
  [86_400, "d", "day"],
  [3_600, "h", "hour"],
  [60, "m", "minute"],
  [1, "s", "second"],
] as const;

/** The largest whole unit for a window: 7200 → [2, "h", "hour"]. */
function span(seconds: number) {
  const [size, short, name] = spans.find(([size]) => seconds % size === 0) ?? spans[4];
  return { count: seconds / size, short, name };
}

/** A relative bound for a window ending now, e.g. 3600 → "now-1h". */
export function relativeBound(seconds: number): string {
  const { count, short } = span(seconds);
  return `now-${count}${short}`;
}

function humanize(seconds: number): string {
  const { count, name } = span(seconds);
  return `${count} ${name}${count === 1 ? "" : "s"}`;
}

export function slidingLabel(seconds: number): string {
  return quickRanges.find((r) => r.seconds === seconds)?.label ?? `Last ${humanize(seconds)}`;
}

/** The selection a resolved snapshot actually used. */
export function currentSelection(context: Context): TimeSelection {
  if (context.time_mode === "live")
    return context.window_seconds
      ? { kind: "sliding", seconds: context.window_seconds }
      : { kind: "default" };
  if (context.from && context.to) return { kind: "absolute", from: context.from, to: context.to };
  return { kind: "default" };
}

const formatter = new Intl.DateTimeFormat("en-GB", {
  timeZone: "UTC",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
});
export function formatUtc(value: string | number): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Invalid time";
  const parts = Object.fromEntries(formatter.formatToParts(date).map((p) => [p.type, p.value]));
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second}`;
}

export function selectionLabel(selection: TimeSelection): string {
  switch (selection.kind) {
    case "default":
      return "Live · widget windows";
    case "sliding":
      return slidingLabel(selection.seconds);
    case "absolute":
      return `${formatUtc(selection.from)} → ${formatUtc(selection.to)} UTC`;
  }
}

/** Absolute bounds for a selection, frozen at `now`. */
export function frozenBounds(selection: TimeSelection, now: number, fallbackSeconds = 3_600) {
  if (selection.kind === "absolute")
    return { from: Date.parse(selection.from), to: Date.parse(selection.to) };
  const seconds = selection.kind === "sliding" ? selection.seconds : fallbackSeconds;
  return { from: now - seconds * 1000, to: now };
}

const iso = (ms: number) => new Date(ms).toISOString().replace(/\.000Z$/, "Z");

/** Shifts by half the span; a live window freezes into an absolute range first. */
export function shift(selection: TimeSelection, direction: -1 | 1, now: number): TimeSelection {
  const { from, to } = frozenBounds(selection, now);
  const offset = Math.max(Math.floor((to - from) / 2), 1000) * direction;
  const next = { from: from + offset, to: to + offset };
  if (next.to > now) return { kind: "sliding", seconds: Math.round((next.to - next.from) / 1000) };
  return { kind: "absolute", from: iso(next.from), to: iso(next.to) };
}

/** Doubles the span; live windows stay live, capped at 24 hours. */
export function zoomOut(selection: TimeSelection, now: number): TimeSelection {
  if (selection.kind !== "absolute") {
    const seconds = selection.kind === "sliding" ? selection.seconds : 1_800;
    return { kind: "sliding", seconds: Math.min(seconds * 2, maxSlidingSeconds) };
  }
  const { from, to } = frozenBounds(selection, now);
  const center = (from + to) / 2;
  const width = Math.min((to - from) * 2, maxRangeMs);
  return {
    kind: "absolute",
    from: iso(center - width / 2),
    to: iso(Math.min(center + width / 2, now)),
  };
}

/** A picked absolute range, validated against the viewer's 31-day bound. */
export function absoluteSelection(range: { start: string; end: string }): TimeSelection | string {
  const start = Date.parse(range.start),
    end = Date.parse(range.end);
  if (Number.isNaN(start) || Number.isNaN(end)) return "Choose a start and end.";
  if (end <= start) return "The end must be after the start.";
  if (end - start > maxRangeMs) return "Ranges can span up to 31 days.";
  return { kind: "absolute", from: iso(start), to: iso(end) };
}

/** The selection as an absolute UTC range to seed the range field. */
export function frozenRange(selection: TimeSelection, now: number) {
  const { from, to } = frozenBounds(selection, now);
  return { start: iso(Math.floor(from / 1000) * 1000), end: iso(Math.floor(to / 1000) * 1000) };
}

export function selectionParams(selection: TimeSelection): Record<string, string | null> {
  switch (selection.kind) {
    case "default":
      return { from: null, to: null, time_mode: null };
    case "sliding":
      return { from: relativeBound(selection.seconds), to: "now", time_mode: null };
    case "absolute":
      return { from: selection.from, to: selection.to, time_mode: null };
  }
}

/** Applies parameter changes to a query string; null removes a parameter. */
export function withParams(search: string, changes: Record<string, string | null>): string {
  const params = new URLSearchParams(search);
  for (const [key, value] of Object.entries(changes)) {
    if (value === null) params.delete(key);
    else params.set(key, value);
  }
  const query = params.toString();
  return query ? `?${query}` : "";
}
