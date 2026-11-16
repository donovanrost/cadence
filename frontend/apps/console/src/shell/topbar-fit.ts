import {
  computed,
  inject,
  nextTick,
  onBeforeUnmount,
  onMounted,
  provide,
  ref,
  watch,
  type InjectionKey,
  type Ref,
} from "vue";

/**
 * The top bar's give-way ladder (ux information-architecture.md §Top bar, f144e8fab, 660a1d06d).
 * Each step happens only while the bar still overflows, in this order; the query trigger has
 * already shrunk to its 160px floor before step 1 (it's the bar's one flexible item).
 */
export const TopBarLevel = {
  /** The fleet posture: marks and counts, short words for count-less chips. */
  postureCompact: 1,
  /** The brand keeps its mark (still named "Cadence"). */
  brandMark: 2,
  /** The scope crumb drops the org ('EARENDIL ⌄'); the org stays in its accessible name. */
  crumbMission: 3,
  /** The query becomes the '⌕ ⌘K' icon button, named "Search". */
  queryIcon: 4,
  /** The clock cluster keeps only UTC. */
  utcOnly: 5,
  /** Last resort: a second row, never a clip (the account menu is always reachable). */
  wrap: 6,
} as const;
const MAX = TopBarLevel.wrap;

/**
 * One step of the fit. Overflowing: give way one more step. Fitting: step back only when the
 * bar is at least as wide as the content was when that step was taken (`need`), so a step can't
 * flap back and forth.
 */
export function nextLevel(
  s: Readonly<{ level: number; overflow: boolean; width: number; need: readonly number[] }>,
): number {
  if (s.overflow) return Math.min(s.level + 1, MAX);
  const need = s.level > 0 ? s.need[s.level - 1] : undefined;
  return need !== undefined && s.width >= need ? s.level - 1 : s.level;
}

const key: InjectionKey<Readonly<Ref<number>>> = Symbol("apogee.topbar-level");

/** The current give-way level, for the bar's items (0 outside the top bar). */
export function useTopBarLevel(): Readonly<Ref<number>> {
  return inject(
    key,
    computed(() => 0),
  );
}

/**
 * Fits the bar from 768 up (`enabled`): watches the header and its items' sizes, steps the level
 * with nextLevel until it settles, and provides it to the items.
 */
export function useTopBarFit(
  header: Readonly<Ref<HTMLElement | null>>,
  enabled: Readonly<Ref<boolean>>,
) {
  const level = ref(0);
  provide(key, level);
  /** need[L]: the content width that overflowed at level L. */
  const need: number[] = [];
  let running = false;
  const overflows = (h: HTMLElement) => h.scrollWidth > h.clientWidth + 1;

  async function fit() {
    if (running) return;
    running = true;
    try {
      for (let i = 0; i < 2 * MAX + 2; i++) {
        const h = header.value;
        if (!h || !enabled.value) {
          level.value = 0;
          return;
        }
        const now = level.value;
        const next = nextLevel({ level: now, overflow: overflows(h), width: h.clientWidth, need });
        if (next === now) return;
        if (next > now) need[now] = h.scrollWidth;
        level.value = next;
        await nextTick();
        // A step back that overflows again goes up and stays (the content grew meanwhile).
        if (next < now && overflows(h)) {
          need[next] = h.scrollWidth;
          level.value = now;
          await nextTick();
          return;
        }
      }
    } finally {
      running = false;
    }
  }

  let resize: ResizeObserver | null = null;
  let mutation: MutationObserver | null = null;
  function observe() {
    const h = header.value;
    if (!h || !resize) return;
    resize.disconnect();
    resize.observe(h);
    for (const child of h.children) resize.observe(child);
  }
  onMounted(() => {
    if (typeof ResizeObserver === "undefined") return;
    resize = new ResizeObserver(() => void fit());
    // Items come and go with the mode and scope: observe the new ones, then fit.
    if (typeof MutationObserver !== "undefined") {
      mutation = new MutationObserver(() => {
        observe();
        void fit();
      });
      if (header.value) mutation.observe(header.value, { childList: true });
    }
    observe();
    void fit();
  });
  watch(enabled, () => void fit());
  onBeforeUnmount(() => {
    resize?.disconnect();
    mutation?.disconnect();
  });
  return { level };
}
