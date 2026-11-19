import type { MissionId } from "@/api/index.ts";
import { computed, shallowRef, watch, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchActionQueue } from "./actionQueue.ts";
import { attentionWords, short, type Attention } from "./attention.ts";

/**
 * U37 drawer block: the open contact_settlement for one pass, read from the action queue (domain
 * #71 doesn't attach it to the pass row). Matched by the pass's reservation id. Null when none.
 */
export function useSettlement(missionId: Ref<MissionId>, passId: Ref<string | null>) {
  const queue = useRemoteQuery(
    computed(() => (passId.value === null ? null : missionId.value)),
    (m, signal) => fetchActionQueue(m, signal),
  );
  useMissionInvalidation(missionId, ["attention"], queue.refetch);
  /** The item a Retry returned (ux: shown at once), until the next read. */
  const patched = shallowRef<Attention | null>(null);
  watch(
    () => queue.state.value,
    () => (patched.value = null),
  );
  const item = computed(() => {
    const s = queue.state.value;
    const id = passId.value;
    if (s.status !== "ready" || id === null) return null;
    const read = s.value.items
      .map((i) => i.attention)
      .find((x) => x?.source === "contact_settlement" && x.backlog && x.reservation_id === id);
    const a = patched.value && patched.value.id === read?.id ? patched.value : read;
    if (!a) return null;
    const last = a.last_attempt_at;
    const n = a.attempts ?? 0;
    return {
      attention: a,
      evidence: attentionWords(a).evidence,
      // ux 294e67c6: "Tried 6 times, last at 23:10Z."
      tried:
        n > 0 && last
          ? `Tried ${n === 1 ? "once" : `${n} times`}, last at ${short(last, new Date())}.`
          : null,
      // Journal off: lost, never on disk, never Retry (U37).
      lost: a.backlog?.lost === true,
      manual: a.retry === "manual" && a.backlog?.lost !== true,
    };
  });
  return { item, patch: (a: Attention) => (patched.value = a) };
}
