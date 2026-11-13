import type { RouteLocationRaw } from "vue-router";
import type { PaletteItem } from "./results.ts";

/**
 * ⌘K Recent (Palette.md): the last 5 rows this viewer opened in this mission, first on an empty
 * query. Kept in this browser only (a convenience); unreadable storage means no Recent group.
 */
export const RECENT_MAX = 5;
/** `palette` (⌘K) and `phone` (the phone search sheet keeps its own, phone kinds only). */
export type RecentList = "palette" | "phone";
const key = (missionId: string, list: RecentList) =>
  list === "palette" ? `apogee.palette.recent.${missionId}` : `apogee.phone.recent.${missionId}`;

type Stored = Readonly<{
  key: string;
  title: string;
  subtitle: string;
  hint: string;
  to: RouteLocationRaw;
}>;

const isText = (v: unknown): v is string => typeof v === "string";
function isStored(v: unknown): v is Stored {
  if (typeof v !== "object" || v === null) return false;
  const r: Record<string, unknown> = { ...v };
  return (
    isText(r.key) &&
    isText(r.title) &&
    isText(r.subtitle) &&
    isText(r.hint) &&
    (isText(r.to) || (typeof r.to === "object" && r.to !== null))
  );
}

function read(missionId: string, list: RecentList): Stored[] {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(key(missionId, list)) ?? "[]");
    return Array.isArray(parsed) ? parsed.filter(isStored).slice(0, RECENT_MAX) : [];
  } catch {
    return [];
  }
}

export function rememberOpened(missionId: string, item: PaletteItem, list: RecentList = "palette") {
  const base = item.key.startsWith("recent-") ? item.key.slice("recent-".length) : item.key;
  const entry: Stored = {
    key: base,
    title: item.title,
    subtitle: item.subtitle,
    hint: item.hint,
    to: item.to,
  };
  const next = [entry, ...read(missionId, list).filter((r) => r.key !== base)].slice(0, RECENT_MAX);
  try {
    localStorage.setItem(key(missionId, list), JSON.stringify(next));
  } catch {
    // Storage unavailable: Recent is a convenience only.
  }
}

/** Recent rows, newest first; `resolves` drops routes this console no longer has. */
export function recentItems(
  missionId: string,
  resolves: (to: RouteLocationRaw) => boolean,
  list: RecentList = "palette",
): PaletteItem[] {
  return read(missionId, list)
    .filter((r) => resolves(r.to))
    .map((r, rank) => ({
      key: `recent-${r.key}`,
      group: "Recent" as const,
      title: r.title,
      subtitle: r.subtitle,
      hint: r.hint,
      state: null,
      to: r.to,
      commandTo: null,
      rank,
    }));
}
