import type { MissionId } from "@/api/index.ts";
import { computed, shallowRef, watch, type Ref } from "vue";
import { decoders as d, request, useRemoteQuery, type ApiResult } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { attentionReader, attentionWords, short, type Attention } from "./attention.ts";

/**
 * `GET …/attention/contact_settlement?reservation_id=` (#847): the open settlement item for one
 * pass's booking, or null. Contract: docs/apogee/api/contacts.md.
 */
export function fetchSettlement(
  missionId: MissionId,
  reservationId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Attention | null>> {
  const q = new URLSearchParams({ reservation_id: reservationId });
  return request(
    `/missions/${encodeURIComponent(missionId)}/attention/contact_settlement?${q.toString()}`,
    d.nullable(attentionReader),
    signal ? { signal } : {},
  );
}

/**
 * U37 drawer block: the open contact_settlement for one pass, by the pass's reservation id (domain
 * #71 doesn't attach it to the pass row). Its own read, not the whole action queue (#847). Null
 * when none.
 */
export function useSettlement(missionId: Ref<MissionId>, passId: Ref<string | null>) {
  const queue = useRemoteQuery(
    computed(() => (passId.value === null ? null : { m: missionId.value, pass: passId.value })),
    (k, signal) => fetchSettlement(k.m, k.pass, signal),
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
    if (s.status !== "ready" || passId.value === null) return null;
    const read = s.value;
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
