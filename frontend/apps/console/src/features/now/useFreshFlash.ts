import { onScopeDispose, shallowRef, watch, type Ref } from "vue";
import type { QueueItem } from "./queue.ts";

/** New crit P1 keys since the last read; the first read flashes nothing (it isn't "newly arrived"). */
export function freshKeys(seen: ReadonlySet<string> | null, items: readonly QueueItem[]): string[] {
  if (seen === null) return [];
  return items
    .filter((i) => i.priority === 1 && i.state === "crit" && !seen.has(i.key))
    .map((i) => i.key);
}

/**
 * design-language §6 motion: a newly arrived crit flashes once (≤600 ms), nothing else animates;
 * with reduced motion, a 2 s `raised` wash instead. Returns the keys flashing now.
 */
export function useFreshFlash(items: Ref<readonly QueueItem[] | null>) {
  const flashing = shallowRef<ReadonlySet<string>>(new Set());
  const reduced =
    typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  let seen: ReadonlySet<string> | null = null;
  const timers = new Set<ReturnType<typeof setTimeout>>();
  watch(
    items,
    (now) => {
      if (now === null) return;
      const fresh = freshKeys(seen, now);
      seen = new Set(now.map((i) => i.key));
      if (fresh.length === 0) return;
      flashing.value = new Set([...flashing.value, ...fresh]);
      const t = setTimeout(
        () => {
          timers.delete(t);
          flashing.value = new Set([...flashing.value].filter((k) => !fresh.includes(k)));
        },
        reduced ? 2000 : 150,
      );
      timers.add(t);
    },
    { immediate: true },
  );
  onScopeDispose(() => timers.forEach(clearTimeout));
  return { flashing, reduced };
}
