import { computed, type ComputedRef } from "vue";
import { useNow } from "@/ui";

/**
 * A clock that moves every `stepMs` (default 10 s), off the shared 1 Hz one. It's a number, so
 * the computed only notifies when the step changes: a 500-row table reading it re-renders every
 * 10 s, not every second (lead: Fleet past 200 rows, no virtualization).
 */
export function floorTo(ms: number, stepMs: number): number {
  return Math.floor(ms / stepMs) * stepMs;
}

export function useCoarseNow(stepMs = 10_000): ComputedRef<number> {
  const now = useNow();
  return computed(() => floorTo(now.value.getTime(), stepMs));
}
