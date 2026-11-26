import type { MissionId } from "@/api/index.ts";
import { computed, watch, type Ref } from "vue";
import {
  decoders as d,
  requestPage,
  usePagedQuery,
  type Decoded,
  type PageFetcher,
} from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";

/** A craft's name and SCID; `scid` is null for a craft that has none yet. */
export type SpacecraftName = Readonly<{ name: string; scid: number | null }>;

const PAGE = 500;
const nameRow = d.object({ id: d.token, name: d.string, scid: d.nullable(d.integer) });
type NameRow = Decoded<typeof nameRow>;
const namesPage = d.object({ names: d.array(nameRow, PAGE) });

/** `GET …/spacecraft/names` (#847): a page of names, sorted by name then id. Contract: setup.md. */
const fetchNames: PageFetcher<MissionId, NameRow, undefined> = async (
  missionId,
  cursor,
  signal,
) => {
  const q = cursor ? `?cursor=${encodeURIComponent(cursor)}` : "";
  const r = await requestPage(
    `/missions/${encodeURIComponent(missionId)}/spacecraft/names${q}`,
    namesPage,
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value.names, next: r.value.nextCursor, meta: undefined },
  };
};

/**
 * Spacecraft id → name + SCID for plan rows and bars (identity on every line, CommandFlow R01),
 * from the light names read (#847), not the fleet read: no telemetry or limits for a name. A name
 * map wants every craft, so it walks the pages (two at 1,000); a failed page stops the walk, and
 * the names read again when the mission's spacecraft change.
 */
export function useSpacecraftNames(missionId: Readonly<Ref<MissionId>>) {
  const names = usePagedQuery(missionId, fetchNames, (row) => row.id);
  watch(
    names.state,
    (s) => {
      if (s.status === "ready" && s.value.next !== null && !names.moreError.value)
        void names.more();
    },
    { immediate: true },
  );
  useMissionInvalidation(missionId, ["spacecraft"], names.refetch);
  const byId = computed(() => {
    const s = names.state.value;
    const map = new Map<string, SpacecraftName>();
    if (s.status === "ready")
      for (const row of s.value.items) map.set(row.id, { name: row.name, scid: row.scid });
    return map;
  });
  return (id: string | null): SpacecraftName | null => (id ? (byId.value.get(id) ?? null) : null);
}

/**
 * #237 (U25): a craft's name from the fleet, or "Unknown spacecraft" when it can't be named.
 * Never its id: an id read as a name is meaningless to an operator and hides that the name
 * couldn't be read.
 */
export const craftLabel = (name: SpacecraftName | null): string =>
  name?.name.trim() ? name.name : "Unknown spacecraft";

/** `FRI 24 OCT` for header lines; days are UTC (U22 Q1). */
export function dayLabel(day: string): string {
  const d = new Date(`${day}T00:00:00Z`);
  return d
    .toLocaleDateString("en-GB", {
      weekday: "short",
      day: "2-digit",
      month: "short",
      timeZone: "UTC",
    })
    .replaceAll(",", "")
    .toUpperCase();
}
