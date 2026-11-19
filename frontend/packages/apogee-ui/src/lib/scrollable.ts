import { onBeforeUnmount, onMounted, ref, type Ref } from "vue";

/**
 * True while `el` overflows (its content scrolls). A scrolling region needs to be keyboard
 * reachable (axe scrollable-region-focusable, ux U30 #3), so bind `tabindex` to it; a region that
 * doesn't scroll stays out of the tab order.
 */
export function useScrollable(el: Readonly<Ref<HTMLElement | null>>): Readonly<Ref<boolean>> {
  const scrollable = ref(false);
  let observer: ResizeObserver | null = null;
  let children: MutationObserver | null = null;
  const measure = () => {
    const node = el.value;
    scrollable.value =
      !!node && (node.scrollHeight > node.clientHeight || node.scrollWidth > node.clientWidth);
  };
  onMounted(() => {
    const node = el.value;
    if (!node || typeof ResizeObserver === "undefined") return;
    const resize = new ResizeObserver(measure);
    observer = resize;
    const watchChildren = () => {
      for (const child of Array.from(node.children)) resize.observe(child);
      measure();
    };
    resize.observe(node);
    watchChildren();
    // Route views swap children (the shell's main): keep observing what's there now.
    children = new MutationObserver(watchChildren);
    children.observe(node, { childList: true });
  });
  onBeforeUnmount(() => {
    observer?.disconnect();
    children?.disconnect();
  });
  return scrollable;
}
