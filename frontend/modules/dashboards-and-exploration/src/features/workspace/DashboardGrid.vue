<script setup>
import { onBeforeUnmount, onMounted, onUpdated, ref, watch } from "vue";
import { GridStack } from "gridstack";
import "../../workspace.css";
import DashboardWidget from "./DashboardWidget.vue";

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
const DashboardGridController = {
  mounted() {
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
    this.pushTimer = null;
    this.sectionResizeFrame = null;

    this.grid.on("change", () => this.scheduleLayoutPush());
    this.grid.on("dragstop resizestop", () => this.updated());
    this.syncEditMode();
  },

  updated() {
    if (this.gestureActive()) return;

    this.reconcileItems();
    this.syncEditMode();
  },

  destroyed() {
    clearTimeout(this.pushTimer);
    this.cancelSectionResize();
    if (this.grid) {
      this.grid.destroy(false);
      this.grid = null;
    }
  },

  editMode() {
    return this.editModeValue();
  },

  gestureActive() {
    return Boolean(this.el.querySelector(".ui-draggable-dragging, .ui-resizable-resizing"));
  },

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
  },

  reconcileItems() {
    const items = Array.from(this.el.querySelectorAll(":scope > .grid-stack-item"));

    items.forEach((el) => {
      if (!el.gridstackNode) {
        this.grid.makeWidget(el);
      } else if (this.editMode() && !el.classList.contains("ui-draggable")) {
        this.grid.movable(el, true);
        this.grid.resizable(el, true);
      }
    });

    this.grid.engine.nodes
      .filter(
        (node) =>
          node.el &&
          !node.el.isConnected &&
          // node.el is the placeholder mid-gesture; never treat it as a removal
          !node.el.classList.contains("grid-stack-placeholder"),
      )
      .forEach((node) => this.grid.removeWidget(node.el, false, false));
  },

  scheduleLayoutPush() {
    clearTimeout(this.pushTimer);
    this.pushTimer = setTimeout(() => this.flushLayout(), LAYOUT_PUSH_DEBOUNCE_MS);
  },

  cancelSectionResize() {
    if (this.sectionResizeFrame !== null) {
      cancelAnimationFrame(this.sectionResizeFrame);
      this.sectionResizeFrame = null;
    }
  },

  scheduleSectionResize() {
    this.cancelSectionResize();

    this.sectionResizeFrame = requestAnimationFrame(() => {
      this.sectionResizeFrame = null;
      this.grid.prevWidth = undefined;
      this.grid.onResize();
    });
  },

  flushLayout() {
    if (this.pushTimer) {
      clearTimeout(this.pushTimer);
      this.pushTimer = null;
    }
    if (!this.editMode()) return;

    const layouts = this.grid.engine.nodes
      .filter((node) => node.el && node.el.isConnected)
      .map((node) => ({
        widget_id: node.el.getAttribute("gs-id"),
        x: node.x,
        y: node.y,
        w: node.w,
        h: node.h,
      }));

    if (layouts.length > 0) {
      this.emit("layout_changed", { layouts });
    }
  },
};

const props = defineProps({
  presentation: { type: Object, required: true },
  sectionOpen: { type: Boolean, default: true },
});

const emit = defineEmits(["layout_changed"]);
const gridElement = ref(null);
let controller = null;

onMounted(() => {
  if (!gridElement.value) return;

  controller = Object.create(DashboardGridController);
  controller.el = gridElement.value;
  controller.editModeValue = () => props.presentation.controller.props.edit_mode;
  controller.gridOptions = () => props.presentation.controller.props;
  controller.emit = emit;
  controller.mounted();
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
