import { decode, decoders as d, scid as scidReader, type Scid } from "@/api";
import { computed, ref, watch, type Ref } from "vue";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { seriesOf, type Selection } from "./selection.ts";

/**
 * OpsLists §Telemetry empty state: "Pick a point to plot" with three suggested points, the most
 * recently plotted by you. Kept per viewer and mission in localStorage (a convenience: a private
 * window or cleared storage simply has none).
 */
export type RecentPlot = Readonly<{ scid: Scid; name: string; point: string }>;
const MAX = 10;
const keyOf = (missionId: string) => `apogee:recent-plots:${missionId}`;

const recentReader = d.object({ scid: scidReader, name: d.string, point: d.string });
/** One stored entry, or none when it no longer reads (an older shape, hand-edited storage). */
const recentOf = (v: unknown): RecentPlot[] => {
  const r = decode(recentReader, v);
  return r.ok ? [r.value] : [];
};

export function readRecent(missionId: string): RecentPlot[] {
  try {
    const raw: unknown = JSON.parse(localStorage.getItem(keyOf(missionId)) ?? "[]");
    return Array.isArray(raw) ? raw.flatMap(recentOf).slice(0, MAX) : [];
  } catch {
    return [];
  }
}

function writeRecent(missionId: string, list: readonly RecentPlot[]) {
  try {
    localStorage.setItem(keyOf(missionId), JSON.stringify(list));
  } catch {
    // storage blocked or full: suggestions just don't persist
  }
}

/** Newest first, one entry per spacecraft × point, at most MAX. */
export function remember(prev: readonly RecentPlot[], added: readonly RecentPlot[]): RecentPlot[] {
  const id = (r: RecentPlot) => `${r.scid}|${r.point}`;
  const fresh = new Set(added.map(id));
  return [...added, ...prev.filter((r) => !fresh.has(id(r)))].slice(0, MAX);
}

/** Up to three not plotted right now. */
export function suggest(recent: readonly RecentPlot[], selection: Selection): RecentPlot[] {
  return recent
    .filter((r) => !(selection.scids.includes(r.scid) && selection.points.includes(r.point)))
    .slice(0, 3);
}

export function useRecentPlots(
  missionId: Ref<string>,
  selection: Ref<Selection>,
  fleet: Ref<readonly FleetSpacecraft[]>,
) {
  const recent = ref<RecentPlot[]>(readRecent(missionId.value));
  watch(missionId, (m) => (recent.value = readRecent(m)));
  watch(
    () => [selection.value, fleet.value] as const,
    ([sel, rows]) => {
      const added = seriesOf(sel).series.flatMap(({ scid, pointId }) => {
        const sc = rows.find((r) => r.scid === scid);
        return sc ? [{ scid, name: sc.name, point: pointId }] : [];
      });
      if (added.length === 0) return;
      recent.value = remember(recent.value, added);
      writeRecent(missionId.value, recent.value);
    },
  );
  return { suggested: computed(() => suggest(recent.value, selection.value)) };
}
