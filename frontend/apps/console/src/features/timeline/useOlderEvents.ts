import { computed, ref, shallowRef, watch, type Ref } from "vue";
import { describeApiError, type ApiResult } from "@/api/index.ts";
import type { EventsPage, MissionEvent } from "./api.ts";

/**
 * Older pages of the Timeline (§11c(C) A9d; api: `?cursor=<meta.next_cursor>`), appended below the
 * first page. `Older events` replaces the 500-row cap note (fe-ops).
 * - Other filters or another window (`listKey`) start over.
 * - A live refetch of the first page keeps what's loaded: older pages reload from the new first
 *   page's cursor up to the count already shown, so nothing vanishes and no gap opens when new
 *   events push the first page's tail down (fe-ops' review; Commands' useGroupPages, ux U72).
 */
export function useOlderEvents(
  listKey: Readonly<Ref<unknown>>,
  first: Readonly<Ref<EventsPage | null>>,
  load: (cursor: string) => Promise<ApiResult<EventsPage>>,
) {
  const pages = shallowRef<readonly MissionEvent[]>([]);
  const cursor = ref<string | null>(null);
  const busy = ref(false);
  const error = ref<string | null>(null);
  /** Bumped on every start-over or reload, so a late page from before is dropped. */
  let generation = 0;

  /** Follow the cursor from `start` until `count` events are collected (or nothing's older). */
  async function collect(start: string | null, count: number, mine: number) {
    const collected: MissionEvent[] = [];
    let next = start;
    while (next !== null && collected.length < count) {
      const r = await load(next);
      if (mine !== generation) return null;
      if (!r.ok) {
        error.value = describeApiError(r.error);
        break;
      }
      collected.push(...r.value.events);
      next = r.value.nextCursor;
    }
    return { collected, next };
  }

  watch(
    () => JSON.stringify(listKey.value),
    () => {
      generation += 1;
      busy.value = false;
      pages.value = [];
      cursor.value = first.value?.nextCursor ?? null;
      error.value = null;
    },
  );
  watch(
    first,
    async (page) => {
      if (!page) return;
      const shown = pages.value.length;
      const mine = ++generation;
      if (shown === 0) {
        busy.value = false;
        cursor.value = page.nextCursor;
        return;
      }
      busy.value = true;
      try {
        const got = await collect(page.nextCursor, shown, mine);
        if (!got) return;
        pages.value = got.collected;
        cursor.value = got.next;
      } finally {
        if (mine === generation) busy.value = false;
      }
    },
    { immediate: true },
  );

  /** Loads the next page; returns the new events' ids (the screen focuses the first one, ux U72). */
  async function more(): Promise<readonly string[]> {
    const at = cursor.value;
    if (at === null || busy.value) return [];
    const mine = ++generation;
    busy.value = true;
    error.value = null;
    try {
      const got = await collect(at, 1, mine);
      if (!got) return [];
      pages.value = [...pages.value, ...got.collected];
      cursor.value = got.next;
      return got.collected.map((e) => e.id);
    } finally {
      if (mine === generation) busy.value = false;
    }
  }
  return { older: pages, hasMore: computed(() => cursor.value !== null), busy, error, more };
}
