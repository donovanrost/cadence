import { onBeforeUnmount, onMounted, ref, watch, type Ref } from "vue";

/**
 * Windowed rows for long tables (lead's kit, 11-15; Fleet at 1,000 craft). Fixed row height: the
 * rows in view plus `overscan` either side render, between spacers of the skipped rows' height.
 */
export type VirtualOptions = Readonly<{ rowHeight: number; overscan?: number | undefined }>;

export type RowWindow = Readonly<{
  /** First rendered row (inclusive). */
  start: number;
  /** One past the last rendered row. */
  end: number;
  /** Spacer heights in px above and below the rendered rows. */
  before: number;
  after: number;
}>;

/**
 * The rows to render. `offset` is where the first row starts inside the scroller's content (the
 * header and anything above the table). `focused`, when set, stays rendered with `overscan`
 * neighbours, so Tab from the last rendered row always has a next row to land on.
 */
export function rowWindow(
  input: Readonly<{
    count: number;
    rowHeight: number;
    overscan: number;
    scrollTop: number;
    viewport: number;
    offset: number;
    focused?: number | null | undefined;
  }>,
): RowWindow {
  const { count, rowHeight, overscan } = input;
  if (count === 0 || rowHeight <= 0) return { start: 0, end: 0, before: 0, after: 0 };
  const top = Math.max(0, input.scrollTop - input.offset);
  const first = Math.floor(top / rowHeight);
  const visible = Math.ceil(Math.max(input.viewport, 0) / rowHeight) + 1;
  let start = Math.max(0, first - overscan);
  let end = Math.min(count, first + visible + overscan);
  const f = input.focused;
  if (f !== null && f !== undefined && f >= 0 && f < count) {
    start = Math.min(start, Math.max(0, f - overscan));
    end = Math.max(end, Math.min(count, f + overscan + 1));
  }
  start = Math.min(start, Math.max(0, end - 1));
  return { start, end, before: start * rowHeight, after: (count - end) * rowHeight };
}

/**
 * The nearest ancestor of `el` (exclusive) that scrolls vertically, else null (the document). Start
 * above the table's own wrapper: its overflow-x: auto makes the computed overflow-y auto too, but
 * it never scrolls vertically.
 */
export function scrollingAncestor(el: HTMLElement | null): HTMLElement | null {
  let node = el?.parentElement ?? null;
  while (node) {
    const y = getComputedStyle(node).overflowY;
    if (y === "auto" || y === "scroll" || y === "overlay") return node;
    node = node.parentElement;
  }
  return null;
}

/**
 * The live window for a table body: listens to its scroller (given, else the nearest scrolling
 * ancestor, else the window) and resizes, once per animation frame, and to focus inside the body.
 */
export function useRowWindow(
  body: Readonly<Ref<HTMLElement | null>>,
  count: Readonly<Ref<number>>,
  options: Readonly<Ref<VirtualOptions | undefined>>,
  scroller: Readonly<Ref<HTMLElement | null | undefined>>,
  /** Where the scroller search starts (exclusive): the table's own wrapper. */
  container: Readonly<Ref<HTMLElement | null>> = body,
): Readonly<Ref<RowWindow | null>> {
  const win = ref<RowWindow | null>(null);
  const focused = ref<number | null>(null);
  let target: HTMLElement | Window | null = null;
  let frame = 0;
  let resize: ResizeObserver | null = null;

  const measure = () => {
    frame = 0;
    const o = options.value;
    const b = body.value;
    if (!o || !b) {
      win.value = null;
      return;
    }
    const el = target instanceof HTMLElement ? target : null;
    const scrollTop = el ? el.scrollTop : window.scrollY;
    const viewport = el ? el.clientHeight : window.innerHeight;
    const topOf = el ? el.getBoundingClientRect().top : 0;
    // The body's top (= row 0, since the top spacer is inside it) in the scroller's content.
    const offset = b.getBoundingClientRect().top - topOf + scrollTop;
    win.value = rowWindow({
      count: count.value,
      rowHeight: o.rowHeight,
      overscan: o.overscan ?? 10,
      scrollTop,
      viewport,
      offset,
      focused: focused.value,
    });
  };
  const schedule = () => {
    if (frame) return;
    frame = typeof requestAnimationFrame === "function" ? requestAnimationFrame(measure) : 0;
    if (!frame) measure();
  };
  const onFocus = (e: FocusEvent) => {
    const row = e.target instanceof Element ? e.target.closest("tr[aria-rowindex]") : null;
    const index = row ? Number(row.getAttribute("aria-rowindex")) - 2 : NaN;
    focused.value = Number.isFinite(index) ? index : null;
    measure();
  };
  const detach = () => {
    target?.removeEventListener("scroll", schedule);
    if (target === window) window.removeEventListener("resize", schedule);
    resize?.disconnect();
    resize = null;
    target = null;
  };
  const attach = () => {
    detach();
    if (!options.value || !body.value) {
      win.value = null;
      return;
    }
    target = scroller.value ?? scrollingAncestor(container.value ?? body.value) ?? window;
    target.addEventListener("scroll", schedule, { passive: true });
    if (target === window) window.addEventListener("resize", schedule);
    else if (typeof ResizeObserver !== "undefined") {
      resize = new ResizeObserver(schedule);
      if (target instanceof HTMLElement) resize.observe(target);
    }
    measure();
  };
  onMounted(() => {
    body.value?.addEventListener("focusin", onFocus);
    attach();
  });
  watch([options, scroller, body], attach);
  watch(count, measure);
  onBeforeUnmount(() => {
    body.value?.removeEventListener("focusin", onFocus);
    if (frame && typeof cancelAnimationFrame === "function") cancelAnimationFrame(frame);
    detach();
  });
  return win;
}
