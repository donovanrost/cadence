import type { TimeSelection } from "./time-range";

const key = "cadence.dashboards.time-recents.v1";
const limit = 5;

/** Per-browser convenience only; unreadable storage simply means no recents. */
export function readRecents(): TimeSelection[] {
  try {
    const value: unknown = JSON.parse(window.localStorage.getItem(key) ?? "[]");
    if (!Array.isArray(value)) return [];
    return value.flatMap((item: unknown): TimeSelection[] => {
      if (typeof item !== "object" || item === null) return [];
      const r = item as Record<string, unknown>;
      if (r.kind === "sliding" && typeof r.seconds === "number" && r.seconds > 0)
        return [{ kind: "sliding", seconds: r.seconds }];
      if (r.kind === "absolute" && typeof r.from === "string" && typeof r.to === "string")
        return [{ kind: "absolute", from: r.from, to: r.to }];
      return [];
    });
  } catch {
    return [];
  }
}

export function rememberRecent(selection: TimeSelection) {
  if (selection.kind === "default") return;
  try {
    const same = (other: TimeSelection) => JSON.stringify(other) === JSON.stringify(selection);
    const next = [selection, ...readRecents().filter((r) => !same(r))].slice(0, limit);
    window.localStorage.setItem(key, JSON.stringify(next));
  } catch {
    /* storage unavailable */
  }
}
