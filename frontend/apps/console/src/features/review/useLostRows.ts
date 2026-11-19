import { ref, shallowRef, watch, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchLost, type ReviewKey, type ReviewRow } from "./api.ts";

/** R4: first page through useRemoteQuery; "Load more" appends pages by cursor for the same window. */
export function useLostRows(key: Ref<ReviewKey>) {
  const { state, refetch } = useRemoteQuery(key, fetchLost);
  const more = shallowRef<readonly ReviewRow[]>([]);
  const cursor = ref<string | null>(null);
  const loading = ref(false);
  const failed = ref(false);
  watch(state, (s) => {
    if (s.status !== "ready") return;
    more.value = [];
    cursor.value = s.value.next_cursor ?? null;
  });

  async function loadMore() {
    const k = key.value;
    if (!cursor.value || loading.value) return;
    loading.value = true;
    failed.value = false;
    try {
      const r = await fetchLost({ ...k, cursor: cursor.value }, new AbortController().signal);
      if (key.value !== k) return;
      if (!r.ok) return void (failed.value = true);
      more.value = [...more.value, ...r.value.rows];
      cursor.value = r.value.next_cursor ?? null;
    } finally {
      loading.value = false;
    }
  }
  return { state, refetch, more, cursor, loading, failed, loadMore };
}
