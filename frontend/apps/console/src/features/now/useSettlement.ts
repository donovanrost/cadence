import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchActionQueue } from "./actionQueue.ts";
import { attentionWords } from "./attention.ts";

/**
 * U37 drawer block: the open contact_settlement for one pass, read from the action queue (domain
 * #71 doesn't attach it to the pass row). Matched by the pass's reservation id. Null when none.
 */
export function useSettlement(missionId: Ref<string>, passId: Ref<string | null>) {
  const queue = useRemoteQuery(
    computed(() => (passId.value === null ? null : missionId.value)),
    (m, signal) => fetchActionQueue(m, signal),
  );
  useMissionInvalidation(missionId, ["attention"], queue.refetch);
  return computed(() => {
    const s = queue.state.value;
    const id = passId.value;
    if (s.status !== "ready" || id === null) return null;
    const a = s.value.items
      .map((i) => i.attention)
      .find((x) => x?.source === "contact_settlement" && x.backlog && x.reservation_id === id);
    return a ? { evidence: attentionWords(a).evidence } : null;
  });
}
