import { computed, onScopeDispose, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchPasses } from "./api.ts";

/**
 * Booked passes over a window that slides with now (`back` ms before, `ahead` ms after), refetched
 * on `contacts` and every 30 s until S10 covers every reservation transition (contacts.md).
 */
export function usePasses(missionId: Ref<string>, back: number, ahead: number | Ref<number>) {
  const span = computed(() => (typeof ahead === "number" ? ahead : ahead.value));
  const key = computed(() => `${missionId.value}|${span.value}`);
  const query = useRemoteQuery(key, (k, signal) => {
    const [id = "", ms = "0"] = k.split("|");
    const t = Date.now();
    return fetchPasses(id, { from: new Date(t - back), to: new Date(t + Number(ms)) }, signal);
  });
  useMissionInvalidation(missionId, ["contacts"], query.refetch);
  const poll = setInterval(query.refetch, 30_000);
  onScopeDispose(() => clearInterval(poll));
  return query;
}
