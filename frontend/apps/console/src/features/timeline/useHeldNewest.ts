import { computed, onScopeDispose, ref, shallowRef, watch, type Ref } from "vue";

/**
 * Timeline live prepend (lead 79ec6dc6): new events refetched on `invalidate events` land at
 * once while the reader is at the top. Scrolled away, the list holds still and offers
 * "N new events ↑", which shows them and scrolls back to the top.
 */
export function useHeldNewest<T extends { id: string }>(
  incoming: Ref<readonly T[] | null>,
  scroller: Ref<HTMLElement | null>,
) {
  const shown = shallowRef<readonly T[] | null>(null);
  const atTop = ref(true);
  const onScroll = () => {
    atTop.value = (scroller.value?.scrollTop ?? 0) < 24;
    if (atTop.value) shown.value = incoming.value;
  };
  watch(
    scroller,
    (el, old) => {
      old?.removeEventListener("scroll", onScroll);
      el?.addEventListener("scroll", onScroll, { passive: true });
    },
    { immediate: true },
  );
  onScopeDispose(() => scroller.value?.removeEventListener("scroll", onScroll));
  watch(
    incoming,
    (next) => {
      // A new window or filter (or the first read) always shows; only live additions hold.
      if (shown.value === null || atTop.value || next === null) shown.value = next;
    },
    { immediate: true },
  );
  const pending = computed(() => {
    const now = incoming.value;
    const seen = new Set((shown.value ?? []).map((e) => e.id));
    return now ? now.filter((e) => !seen.has(e.id)).length : 0;
  });
  function showNew() {
    shown.value = incoming.value;
    scroller.value?.scrollTo({ top: 0, behavior: "smooth" });
  }
  /** A filter or window change resets the hold (the reader asked for a different list). */
  function reset() {
    shown.value = null;
  }
  return { shown, pending, showNew, reset };
}
