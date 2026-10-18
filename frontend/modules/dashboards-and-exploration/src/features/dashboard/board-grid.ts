import { GridStack, type GridItemHTMLElement } from "gridstack";
import type { LayoutEdit } from "./contracts";

export type GridGeometry = { columns: number; row_height_px: number; gap_px: number };
const LAYOUT_DEBOUNCE_MS = 400;

/**
 * GridStack + Vue coexistence for one dashboard section.
 *
 * - View mode is a static grid: GridStack never mutates the DOM after init, so
 *   live data patches widget contents freely. Positions come from gs-* attrs.
 * - Edit mode unlocks drag/resize with classic reflow. GridStack owns item gs-*
 *   attributes and resize handles during edit; layout changes are debounced and
 *   reported for every item in this grid.
 * - `reconcile()` runs after Vue patches: it adopts added items and drops
 *   removed ones, but never mid-gesture, when GridStack points a node at its
 *   placeholder and a removal would silently drop the node from the engine.
 */
export class BoardGrid {
  private readonly grid: GridStack;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private frame: number | undefined;
  private disposed = false;

  constructor(
    private readonly el: HTMLElement,
    geometry: GridGeometry,
    private readonly editing: boolean,
    private readonly report: (layouts: LayoutEdit[]) => void,
  ) {
    this.grid = GridStack.init(
      {
        column: geometry.columns,
        cellHeight: geometry.row_height_px,
        margin: geometry.gap_px,
        float: !editing,
        staticGrid: !editing,
        styleInHead: true,
        animate: false,
        // The vendored stylesheet has no hover reveal; keep handles visible while editing.
        alwaysShowResizeHandle: true,
        resizable: { handles: "e, se, s" },
        draggable: { handle: "[data-drag-handle]" },
      },
      el,
    );
    this.grid.on("change", () => this.schedule());
    this.grid.on("dragstop resizestop", () => this.reconcile());
  }

  reconcile() {
    if (this.disposed || this.gesturing()) return;
    const items = Array.from(
      this.el.querySelectorAll<GridItemHTMLElement>(":scope > .grid-stack-item"),
    );
    for (const item of items) if (!item.gridstackNode) this.grid.makeWidget(item);
    // oxlint-disable-next-line unicorn/no-useless-spread -- removeWidget mutates engine.nodes while iterating.
    for (const node of [...this.grid.engine.nodes]) {
      const element = node.el;
      if (element && !element.isConnected && !element.classList.contains("grid-stack-placeholder"))
        this.grid.removeWidget(element, false, false);
    }
  }

  /** A collapsed section measured zero width; remeasure once it opens. */
  remeasure() {
    if (this.frame !== undefined) cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(() => {
      this.frame = undefined;
      if (this.disposed) return;
      // GridStack 10 caches its previous width without a force-resize API.
      Reflect.deleteProperty(this.grid, "prevWidth");
      this.grid.onResize();
    });
  }

  destroy() {
    if (this.disposed) return;
    this.flush();
    this.disposed = true;
    clearTimeout(this.timer);
    if (this.frame !== undefined) cancelAnimationFrame(this.frame);
    this.grid.destroy(false);
  }

  private gesturing() {
    return Boolean(this.el.querySelector(".ui-draggable-dragging, .ui-resizable-resizing"));
  }

  private schedule() {
    if (!this.editing) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), LAYOUT_DEBOUNCE_MS);
  }

  private flush() {
    if (this.timer === undefined || this.disposed) return;
    clearTimeout(this.timer);
    this.timer = undefined;
    // Repeated instances share their authored placement; its first instance decides.
    const layouts = new Map<string, LayoutEdit>();
    for (const node of this.grid.engine.nodes) {
      const id = node.el?.isConnected ? node.el.getAttribute("gs-id") : null;
      if (
        id &&
        !layouts.has(id) &&
        node.x !== undefined &&
        node.y !== undefined &&
        node.w &&
        node.h
      )
        layouts.set(id, { placement_id: id, x: node.x, y: node.y, w: node.w, h: node.h });
    }
    if (layouts.size) this.report([...layouts.values()]);
  }
}
