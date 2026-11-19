import { ref, watch, type Ref, type WatchSource } from "vue";
import type { FailureOutcome } from "./actions.ts";

/**
 * A refused or unclear Stage, shown as its own callout beside the editor's Check outcome (ux 11-16,
 * cf20dfca9). It clears on the next edit of any of `edits`; the editor also clears it when Check or
 * Stage starts. So an old refusal never sits beside a fresh Check, and Stage stays retryable.
 */
export function useStageFailure(edits: readonly WatchSource[]): Ref<FailureOutcome | null> {
  const failure = ref<FailureOutcome | null>(null);
  watch([...edits], () => (failure.value = null), { deep: true });
  return failure;
}
