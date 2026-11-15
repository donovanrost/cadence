import {
  computed,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
  type ComponentPublicInstance,
  type Ref,
} from "vue";

/** OpsLists.md › Fleet (option A): below this much room for the table, the page scrolls instead. */
export const MIN_TABLE_BOX = 360;

/** Room from the panel's top to the bottom of the screen's area, in px. */
export function tableRoom(screen: HTMLElement, panel: HTMLElement): number {
  const top = panel.getBoundingClientRect().top - screen.getBoundingClientRect().top;
  return screen.clientHeight - (top + screen.scrollTop);
}

/**
 * Whether the table panel can be the one vertical scroller: `enabled` (the table view on a screen
 * wide enough for the table) and at least MIN_TABLE_BOX px from the panel's top to the bottom.
 * The panel's top is measured in the screen's content, so it reads the same in either layout.
 */
export function useTableBox(
  screen: Readonly<Ref<HTMLElement | null>>,
  panel: Readonly<Ref<ComponentPublicInstance | null>>,
  enabled: Readonly<Ref<boolean>>,
): Readonly<Ref<boolean>> {
  const fits = ref(true);
  let observer: ResizeObserver | null = null;
  const panelEl = () => {
    const el: unknown = panel.value?.$el;
    return el instanceof HTMLElement ? el : null;
  };
  const measure = () => {
    const s = screen.value;
    const p = panelEl();
    if (s && p) fits.value = tableRoom(s, p) >= MIN_TABLE_BOX;
  };
  const observe = () => {
    observer?.disconnect();
    if (typeof ResizeObserver === "undefined") return;
    observer = new ResizeObserver(measure);
    const s = screen.value;
    const p = panelEl();
    if (s) observer.observe(s);
    if (p) observer.observe(p);
    measure();
  };
  onMounted(observe);
  watch([screen, panel], observe);
  onBeforeUnmount(() => observer?.disconnect());
  return computed(() => enabled.value && fits.value);
}
