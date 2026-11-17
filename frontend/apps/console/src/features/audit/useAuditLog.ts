import { ref, shallowRef, watch, type Ref } from "vue";
import { useRemoteQuery, type Unshown } from "@/api";
import { fetchAudit, type AuditEvent, type AuditQuery } from "./api.ts";

/** First page through useRemoteQuery; "Load older" appends pages by cursor for the same query. */
export function useAuditLog(query: Ref<AuditQuery | null>) {
  const { state, refetch } = useRemoteQuery(query, fetchAudit);
  const older = shallowRef<readonly AuditEvent[]>([]);
  /** U86: events left out of the older pages (the first page carries its own). */
  const olderUnshown = shallowRef<readonly Unshown[]>([]);
  const cursor = ref<string | null>(null);
  const loading = ref(false);
  const failed = ref(false);
  watch(state, (s) => {
    if (s.status !== "ready") return;
    older.value = [];
    olderUnshown.value = [];
    cursor.value = s.value.next_cursor;
  });

  async function loadOlder() {
    const q = query.value;
    if (!q || !cursor.value || loading.value) return;
    loading.value = true;
    failed.value = false;
    try {
      const result = await fetchAudit({ ...q, cursor: cursor.value }, new AbortController().signal);
      if (!result.ok || query.value !== q) return void (failed.value = !result.ok);
      older.value = [...older.value, ...result.value.events];
      olderUnshown.value = [...olderUnshown.value, ...result.value.unshown];
      cursor.value = result.value.next_cursor;
    } finally {
      loading.value = false;
    }
  }
  return { state, refetch, older, olderUnshown, cursor, loading, failed, loadOlder };
}
