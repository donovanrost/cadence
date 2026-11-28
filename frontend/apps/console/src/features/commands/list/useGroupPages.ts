import type { MissionId } from "@/api/index.ts";
import { decoders as d, requestPage, usePagedQuery, type PageFetcher } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useMissionInvalidation } from "@/live/index.ts";
import { groupRow, groupsBase, type GroupRow } from "../groups/api.ts";
import type { CommandFilters } from "./filters.ts";

/** A5c (api ccddc894b): pages of 100, newest first, with q/target/stage applied by the server. */
const PAGE = 100;
const pageReader = d.object({ groups: d.array(groupRow, PAGE) });

export function fetchGroupPage(
  missionId: MissionId,
  f: CommandFilters,
  cursor: string | null,
  signal?: AbortSignal,
) {
  const p = new URLSearchParams({ limit: String(PAGE) });
  if (f.q) p.set("q", f.q);
  if (f.target) p.set("target", f.target);
  if (f.stages.length) p.set("stage", f.stages.join(","));
  if (f.withdrawnRevision) p.set("withdrawn_revision", f.withdrawnRevision);
  if (cursor) p.set("cursor", cursor);
  return requestPage(
    `${groupsBase(missionId)}?${p.toString()}`,
    pageReader,
    signal ? { signal } : {},
  );
}

type Key = Readonly<{ missionId: MissionId; filters: CommandFilters }>;

const fetchPage: PageFetcher<Key, GroupRow, undefined> = async (key, cursor, signal) => {
  const r = await fetchGroupPage(key.missionId, key.filters, cursor, signal);
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value.groups, next: r.value.nextCursor, meta: undefined },
  };
};

/**
 * The Commands list's pages through usePagedQuery (ux U72): the first on load or a filter change,
 * Load more for the next, and on a live `commanding` change a reload from the first page up to the
 * rows shown, so a row that moved while the list was open comes back by itself.
 */
export function useGroupPages(missionId: Ref<MissionId>, filters: Ref<CommandFilters>) {
  const key = computed<Key>(() => ({ missionId: missionId.value, filters: filters.value }));
  const pages = usePagedQuery(key, fetchPage, (group) => group.id);
  useMissionInvalidation(missionId, ["commanding"], pages.refetch);
  return pages;
}
