<script setup lang="ts">
import { onBeforeUnmount, onMounted, onUpdated, ref, watch } from "vue";
import { GridStack, type GridItemHTMLElement } from "gridstack";
import "../../workspace.css";
import DashboardWidget from "./DashboardWidget.vue";
import type { GridPresentation, GridOptions, LayoutChanged } from "./canvas-presentation";

const LAYOUT_PUSH_DEBOUNCE_MS = 400;

// GridStack + LiveVue coexistence:
// - View mode runs staticGrid, so GridStack never mutates the DOM after init
//   and Vue freely patches widget contents (positions are pure CSS from
//   server-rendered gs-* attributes).
// - Edit mode is the only mutation window; the LiveView pauses data assigns
//   while it is active, and layout changes autosave via "layout_changed".
// - This component renders the grid, items, widgets, and headless controller
//   marker as one Vue-owned subtree. updated() therefore runs after relevant
//   DOM patches and can adopt added items, drop removed ones, and re-arm any
//   drag/resize classes replaced by a server-presented class update.
// - GridStack owns its generated gs-id-* class, row style/attribute, item gs-*
//   attributes during edit mode, and resize-handle children. Vue patches only
//   its own prior VNodes, so those imperative additions remain in place until
//   setStatic() or destroy(false) lets GridStack clean them up itself.
// - While a drag/resize gesture is in flight, updated() must not reconcile:
//   GridStack points node.el at its placeholder during the gesture, and a
//   patch that removes the placeholder from the DOM would make the node look
//   removed — dropping it from the engine and silently disabling all future
//   layout pushes (flushLayout reads engine.nodes).
class DashboardGridController {
  private grid: GridStack;
  private pushTimer: ReturnType<typeof setTimeout> | undefined;
  private sectionResizeFrame: number | undefined;
  private disposed = false;
  constructor(
    private readonly el: HTMLElement,
    private readonly editModeValue: () => boolean,
    private readonly gridOptions: () => GridOptions,
    private readonly emit: (payload: LayoutChanged) => void,
  ) {
    this.grid = GridStack.init(
      {
        column: this.gridOptions().columns ?? 12,
        cellHeight: this.gridOptions().row_height_px ?? 80,
        margin: this.gridOptions().gap_px ?? 8,
        // Float in view mode so adopted items keep the server's exact gs-*
        // positions (no compaction fighting server-rendered attrs). Edit mode
        // switches to float(false) for classic GridStack reflow — see
        // syncEditMode().
        float: true,
        staticGrid: true,
        styleInHead: true,
        animate: false,
        // Default "mobile" autohides handles on desktop, but the vendored
        // gridstack CSS has no :hover rule to reveal them — so on desktop the
        // handles stay display:none and resizing is impossible. Force them on;
        // they only exist in edit mode (the grid is static otherwise).
        alwaysShowResizeHandle: true,
        // Widen the grab targets: the bottom-right corner plus the right and
        // bottom edges, rather than the single hard-to-hit corner handle.
        resizable: { handles: "e, se, s" },
      },
      this.el,
    );
    this.pushTimer = undefined;
    this.sectionResizeFrame = undefined;

    this.grid.on("change", () => this.scheduleLayoutPush());
    this.grid.on("dragstop resizestop", () => this.updated());
    this.syncEditMode();
  }

  updated() {
    if (this.disposed || this.gestureActive()) return;

    this.reconcileItems();
    this.syncEditMode();
  }

  destroyed() {
    if (this.disposed) return;
    this.disposed = true;
    clearTimeout(this.pushTimer);
    this.cancelSectionResize();
    this.grid.destroy(false);
  }

  editMode() {
    return this.editModeValue();
  }

  gestureActive() {
    return Boolean(this.el.querySelector(".ui-draggable-dragging, .ui-resizable-resizing"));
  }

  syncEditMode() {
    const editing = this.editMode();
    // Read GridStack's own state, not the client-owned grid-stack-static class.
    const isStatic = this.grid.opts.staticGrid === true;

    if (editing && isStatic) {
      this.grid.setStatic(false);
      // Classic GridStack reflow while editing: dragging into an occupied
      // space pushes neighbors and everything compacts upward. The initial
      // compaction fires "change", so it autosaves like any other move.
      this.grid.float(false);
    } else if (!editing && !isStatic) {
      this.flushLayout();
      this.grid.float(true);
      this.grid.setStatic(true);
    }

    this.el.classList.toggle("grid-stack-static", !editing);
  }

  reconcileItems() {
    const items = Array.from(
      this.el.querySelectorAll<GridItemHTMLElement>(":scope > .grid-stack-item"),
    );

    items.forEach((el) => {
      if (!el.gridstackNode) {
        this.grid.makeWidget(el);
      } else if (this.editMode() && !el.classList.contains("ui-draggable")) {
        this.grid.movable(el, true);
        this.grid.resizable(el, true);
      }
    });

    // oxlint-disable-next-line unicorn/no-useless-spread -- removeWidget mutates engine.nodes during reconciliation.
    for (const node of [...this.grid.engine.nodes]) {
      const element = node.el;
      // GridStack uses a temporary placeholder during gestures; retain it until the gesture ends.
      if (element && !element.isConnected && !element.classList.contains("grid-stack-placeholder"))
        this.grid.removeWidget(element, false, false);
    }
  }

  scheduleLayoutPush() {
    clearTimeout(this.pushTimer);
    this.pushTimer = setTimeout(() => this.flushLayout(), LAYOUT_PUSH_DEBOUNCE_MS);
  }

  cancelSectionResize() {
    if (this.sectionResizeFrame !== undefined) {
      cancelAnimationFrame(this.sectionResizeFrame);
      this.sectionResizeFrame = undefined;
    }
  }

  scheduleSectionResize() {
    this.cancelSectionResize();

    this.sectionResizeFrame = requestAnimationFrame(() => {
      this.sectionResizeFrame = undefined;
      if (this.disposed) return;
      // GridStack 10 caches the previous width without exposing a force-resize API.
      // Disclosure changes need one fresh measurement even at the same width.
      Reflect.deleteProperty(this.grid, "prevWidth");
      this.grid.onResize();
    });
  }

  flushLayout() {
    if (this.pushTimer) {
      clearTimeout(this.pushTimer);
      this.pushTimer = undefined;
    }
    if (this.disposed || !this.editMode()) return;

    const layouts: LayoutChanged["layouts"] = [];
    for (const node of this.grid.engine.nodes) {
      const element = node.el;
      if (element?.isConnected)
        layouts.push({
          widget_id: element.getAttribute("gs-id"),
          x: node.x,
          y: node.y,
          w: node.w,
          h: node.h,
        });
    }

    if (layouts.length > 0) {
      this.emit({ layouts });
    }
  }
}

const props = withDefaults(
  defineProps<{ presentation: GridPresentation; sectionOpen?: boolean }>(),
  { sectionOpen: true },
);
const emit = defineEmits<{ layout_changed: [payload: LayoutChanged] }>();
const gridElement = ref<HTMLElement | null>(null);
let controller: DashboardGridController | null = null;
onMounted(() => {
  if (!gridElement.value) return;
  controller = new DashboardGridController(
    gridElement.value,
    () => props.presentation.controller.props.edit_mode,
    () => props.presentation.controller.props,
    (payload) => emit("layout_changed", payload),
  );
});

onUpdated(() => controller?.updated());

watch(
  () => props.sectionOpen,
  (open, previousOpen) => {
    if (!controller || open === previousOpen) return;
    if (open && previousOpen === false) {
      controller.scheduleSectionResize();
    } else if (!open) {
      controller.cancelSectionResize();
    }
  },
  { flush: "post" },
);

onBeforeUnmount(() => {
  controller?.destroyed();
  controller = null;
});
</script>

<template>
  <div ref="gridElement" v-bind="props.presentation.root.attrs">
    <div v-for="widget in props.presentation.widgets" :key="widget.key" v-bind="widget.shell.attrs">
      <div v-bind="widget.content.attrs">
        <div v-bind="widget.host.attrs">
          <DashboardWidget :presentation="widget.presentation" />
        </div>
      </div>
    </div>
  </div>
  <div v-bind="props.presentation.controller.host.attrs">
    <span
      data-dashboard-grid-controller
      :data-dashboard-grid-target="props.presentation.controller.props.target_id"
      :data-edit-mode="String(props.presentation.controller.props.edit_mode)"
      :data-dashboard-grid-item-count="String(props.presentation.controller.props.item_ids.length)"
      aria-hidden="true"
      hidden
    ></span>
  </div>
</template>
