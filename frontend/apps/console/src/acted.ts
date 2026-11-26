import { computed, ref, watch, type WatchSource } from "vue";

/**
 * a11y B6 (#276, ux): whether the load on screen follows the person's own act (Retry, a typed
 * search, a filter or day change). A load that fails after such an act is an alert; the screen's
 * first load, or a background refetch, is read politely. `settled` is true once a load succeeds,
 * which clears the flag.
 */
export function useActed(settled: WatchSource<boolean>) {
  const acted = ref(false);
  watch(settled, (ok) => {
    if (ok) acted.value = false;
  });
  return {
    /** Call when the person acts; the next failure is an alert. */
    mark: () => {
      acted.value = true;
    },
    /** `fn`, marking the act first: `@click="after(refetch)"`. */
    after:
      <A extends unknown[], R>(fn: (...args: A) => R) =>
      (...args: A): R => {
        acted.value = true;
        return fn(...args);
      },
    /** The failure callout's role. */
    role: computed(() => (acted.value ? ("alert" as const) : ("status" as const))),
  };
}
