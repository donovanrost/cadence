/**
 * Plain data for ApGantt (design-language ApPassStrip/ApGantt): time runs left→right, stations
 * top→bottom. Callers map their contact model onto `kind`; the component only draws.
 */
export type GanttRow = Readonly<{
  id: string;
  /** Mono code, e.g. `SVB-1`. */
  label: string;
  /** Full name for the accessible label and tooltip, e.g. `Svalbard`. */
  name?: string | undefined;
  /** Small capability tag after the label, e.g. `UP`. */
  tag?: string | undefined;
  degraded?: boolean | undefined;
}>;

export type GanttBarKind =
  /** Drafted / scheduled contact: solid white. */
  | "own"
  /** Drafted and belongs to the focused spacecraft: white + ring. */
  | "focused"
  /** Newly added ("now covered"): white + green ring. The only nominal green on the Gantt. */
  | "new"
  /** Live / in contact: white, dark label. */
  | "live"
  /** A window not in the plan (opportunity): dashed white. */
  | "window"
  /** A window that clashes: dashed caution. */
  | "clash"
  /** Problem contact (rejected, conflict): caution fill. */
  | "problem"
  /** Scheduled, not ours to edit (live Contacts view): outline + wash. */
  | "scheduled"
  /** Ended / past: drawn dimmer than scheduled. */
  | "done"
  /** Drafted but at risk (e.g. a degraded station): white with a caution outline. */
  | "risk"
  /** Placed, provider silent past its window: truth unknown, stale-hatched (ux U30). */
  | "unconfirmed";

export type GanttBar = Readonly<{
  id: string;
  rowId: string;
  from: number;
  to: number;
  kind: GanttBarKind;
  /** Short mono label inside the bar when it fits, e.g. spacecraft number `118`. */
  label?: string | undefined;
  /** Full sentence for assistive tech and the tooltip. */
  description: string;
  /** Not the current filter's match (Contacts `sc any`): drawn faint, still focusable and named. */
  dim?: boolean | undefined;
  /** A queued uplink rides this pass (Contacts 'highlight queued uplinks', `.cb.up`): a dark notch at the top. */
  notch?: boolean | undefined;
  /**
   * An open attention item on this pass (ux U45): a status mark at the bar's leading edge, never a
   * fill. Decorative: the `description` must say it in words.
   */
  attention?: "caution" | "crit" | undefined;
}>;

export type GanttBand = Readonly<{
  /** null = every row. */
  rowId: string | null;
  from: number;
  to: number;
  kind: "outage" | "maintenance" | "degraded" | "unusable";
  label?: string | undefined;
}>;

export type GanttWindow = Readonly<{ from: number; to: number }>;

/** Percent position of `t` in the window, clamped to 0..100. */
export function position(window: GanttWindow, t: number): number {
  const span = window.to - window.from;
  if (span <= 0) return 0;
  return Math.max(0, Math.min(100, ((t - window.from) / span) * 100));
}

/** Left/width percentages for an interval, with a minimum visible width. */
export function extent(window: GanttWindow, from: number, to: number, minPct = 0.25) {
  const left = position(window, from);
  return { left, width: Math.max(minPct, position(window, to) - left) };
}

/** Hour ticks: a label every `every` hours, choosing 1/2/3/6/12 so there are at most ~12 labels. */
export function hourTicks(window: GanttWindow): { t: number; major: boolean }[] {
  const hour = 3_600_000;
  const hours = (window.to - window.from) / hour;
  const every = [1, 2, 3, 6, 12].find((n) => hours / n <= 12) ?? 24;
  const first = Math.ceil(window.from / hour) * hour;
  const ticks: { t: number; major: boolean }[] = [];
  for (let t = first; t <= window.to; t += hour)
    ticks.push({ t, major: Math.round((t / hour) % every) === 0 });
  return ticks;
}

/**
 * Keyboard navigation between bars: ←/→ previous/next bar in the same row by time; ↑/↓ the bar in
 * the adjacent row closest in time. Returns the target bar id or null.
 */
export function neighbour(
  rows: readonly GanttRow[],
  bars: readonly GanttBar[],
  currentId: string,
  key: "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown",
): string | null {
  const current = bars.find((b) => b.id === currentId);
  if (!current) return null;
  const inRow = (rowId: string) =>
    bars.filter((b) => b.rowId === rowId).sort((a, b) => a.from - b.from);
  if (key === "ArrowLeft" || key === "ArrowRight") {
    const row = inRow(current.rowId);
    const i = row.findIndex((b) => b.id === currentId);
    return row[i + (key === "ArrowRight" ? 1 : -1)]?.id ?? null;
  }
  const r = rows.findIndex((row) => row.id === current.rowId);
  const step = key === "ArrowDown" ? 1 : -1;
  for (let k = r + step; k >= 0 && k < rows.length; k += step) {
    const candidates = inRow(rows[k]?.id ?? "");
    if (candidates.length === 0) continue;
    const mid = (current.from + current.to) / 2;
    return candidates.reduce((best, b) =>
      Math.abs((b.from + b.to) / 2 - mid) < Math.abs((best.from + best.to) / 2 - mid) ? b : best,
    ).id;
  }
  return null;
}
