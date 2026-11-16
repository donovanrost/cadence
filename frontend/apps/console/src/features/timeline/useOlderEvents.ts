import { computed, ref, shallowRef, watch, type Ref } from "vue";
import { describeApiError, type ApiResult } from "@/api/index.ts";
import type { EventsPage, MissionEvent } from "./api.ts";

/**
 * Older pages of the Timeline (§11c(C) A9d; api: `?cursor=<meta.next_cursor>`). They start from the
 * first page's cursor and append below it. A new first page (other filters, window or a refetch
 * with a new cursor) starts over. `Older events` replaces the 500-row cap note (fe-ops).
 */
export function useOlderEvents(
  first: Readonly<Ref<EventsPage | null>>,
  load: (cursor: string) => Promise<ApiResult<EventsPage>>,
) {
  const pages = shallowRef<readonly MissionEvent[]>([]);
  const cursor = ref<string | null>(null);
  const busy = ref(false);
  const error = ref<string | null>(null);
  /** A first page with a different cursor is a different list: start over. */
  watch(
    () => first.value?.nextCursor,
    (next) => {
      pages.value = [];
      cursor.value = next ?? null;
      error.value = null;
    },
    { immediate: true },
  );
  async function more() {
    const at = cursor.value;
    if (at === null || busy.value) return;
    busy.value = true;
    error.value = null;
    const r = await load(at);
    busy.value = false;
    if (cursor.value !== at) return; // the list started over meanwhile
    if (!r.ok) {
      error.value = describeApiError(r.error);
      return;
    }
    pages.value = [...pages.value, ...r.value.events];
    cursor.value = r.value.nextCursor;
  }
  return {
    older: pages,
    hasMore: computed(() => cursor.value !== null),
    busy,
    error,
    more,
  };
}
