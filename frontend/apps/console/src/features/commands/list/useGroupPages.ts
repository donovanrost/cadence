import type { MissionId } from "@/api/index.ts";
import { decoders as d, describeApiError, requestPage, type RemoteState } from "@/api/index.ts";
import { shallowRef, watch, type Ref } from "vue";
import { useMissionInvalidation } from "@/live/index.ts";
import { groupRow, groupsBase, type GroupRow } from "../groups/api.ts";
import type { CommandFilters } from "./filters.ts";

/** A5c (api ccddc894b): pages of 100, newest first, with q/target/stage applied by the server. */
const PAGE = 100;
const MAX_LIMIT = 200;
const pageReader = d.object({ groups: d.array(groupRow, MAX_LIMIT) });

export function fetchGroupPage(
  missionId: MissionId,
  f: CommandFilters,
  cursor: string | null,
  limit = PAGE,
  signal?: AbortSignal,
) {
  const p = new URLSearchParams({ limit: String(limit) });
  if (f.q) p.set("q", f.q);
  if (f.target) p.set("target", f.target);
  if (f.stages.length) p.set("stage", f.stages.join(","));
  if (cursor) p.set("cursor", cursor);
  return requestPage(
    `${groupsBase(missionId)}?${p.toString()}`,
    pageReader,
    signal ? { signal } : {},
  );
}

export type GroupPage = Readonly<{ rows: readonly GroupRow[]; next: string | null }>;

/** Rows by id, first seen wins (a row that moves between pages shows once; ux U72). */
const dedupe = (rows: readonly GroupRow[]) => [...new Map(rows.map((r) => [r.id, r])).values()];

/**
 * The Commands list's pages: the first on load or a filter change, 'Load more' for the next, and on
 * a live change a reload from the first page up to the count already shown, so a row that was
 * skipped while it moved comes back by itself (ux U72).
 */
export function useGroupPages(missionId: Ref<MissionId>, filters: Ref<CommandFilters>) {
  const state = shallowRef<RemoteState<GroupPage>>({ status: "loading" });
  const busy = shallowRef(false);
  const moreError = shallowRef<string | null>(null);
  let generation = 0;

  /** One page, or (a live refresh) pages from the first until `upTo` rows are back. */
  async function load(upTo = 0) {
    const mine = ++generation;
    const rows: GroupRow[] = [];
    let cursor: string | null = null;
    do {
      const r = await fetchGroupPage(
        missionId.value,
        filters.value,
        cursor,
        Math.min(MAX_LIMIT, Math.max(PAGE, upTo - rows.length)),
      );
      if (mine !== generation) return;
      if (!r.ok) {
        // A failed refresh keeps what's shown; a failed first load says so.
        if (state.value.status !== "ready" || upTo === 0)
          state.value = { status: "failed", error: r.error };
        return;
      }
      rows.push(...r.value.value.groups);
      cursor = r.value.nextCursor;
    } while (cursor && rows.length < upTo);
    state.value = {
      status: "ready",
      value: { rows: dedupe(rows), next: cursor },
      receivedAt: new Date(),
    };
  }

  /** Appends the next page; returns the id of the first new row (focus goes to its link). */
  async function more(): Promise<string | null> {
    const s = state.value;
    if (s.status !== "ready" || !s.value.next || busy.value) return null;
    busy.value = true;
    moreError.value = null;
    const mine = generation;
    try {
      const r = await fetchGroupPage(missionId.value, filters.value, s.value.next);
      if (mine !== generation) return null;
      if (!r.ok) {
        moreError.value = `Couldn't load more: ${describeApiError(r.error)}`;
        return null;
      }
      const known = new Set(s.value.rows.map((x) => x.id));
      const fresh = r.value.value.groups.filter((x) => !known.has(x.id));
      state.value = {
        status: "ready",
        value: { rows: [...s.value.rows, ...fresh], next: r.value.nextCursor },
        receivedAt: new Date(),
      };
      return fresh[0]?.id ?? null;
    } finally {
      busy.value = false;
    }
  }

  const run = (p: Promise<unknown>): void => {
    p.catch((e: unknown) => console.error("Commands failed", e));
  };
  watch(
    () => JSON.stringify([missionId.value, filters.value]),
    () => {
      state.value = { status: "loading" };
      run(load());
    },
    { immediate: true },
  );
  useMissionInvalidation(missionId, ["commanding"], () => {
    const s = state.value;
    run(load(s.status === "ready" ? s.value.rows.length : 0));
  });

  return {
    state,
    busy,
    moreError,
    more,
    retry: () => run(load()),
  };
}
