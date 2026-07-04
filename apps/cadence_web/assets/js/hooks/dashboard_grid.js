// gridstack-all.js is a UMD bundle whose export value is the GridStack class
// itself (module.exports = GridStack), so it imports as a default, not a named
// export — `import { GridStack }` resolves to undefined.
import GridStack from "../../vendor/gridstack/gridstack-all"

const LAYOUT_PUSH_DEBOUNCE_MS = 400

// GridStack + LiveView coexistence:
// - View mode runs staticGrid, so GridStack never mutates the DOM after init
//   and LiveView freely patches widget contents (positions are pure CSS from
//   server-rendered gs-* attributes).
// - Edit mode is the only mutation window; the LiveView pauses data assigns
//   while it is active, and layout changes autosave via "layout_changed".
// - updated() reconciles after LiveView patches: adopts added items, drops
//   removed ones, and re-arms drag/resize classes morphdom may have stripped.
// - While a drag/resize gesture is in flight, updated() must not reconcile:
//   GridStack points node.el at its placeholder during the gesture, and a
//   patch that removes the placeholder from the DOM would make the node look
//   removed — dropping it from the engine and silently disabling all future
//   layout pushes (flushLayout reads engine.nodes).
const DashboardGrid = {
  mounted() {
    this.grid = GridStack.init(
      {
        column: 12,
        cellHeight: 80,
        margin: 8,
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
      this.el
    )
    this.pushTimer = null

    this.grid.on("change", () => this.scheduleLayoutPush())
    this.syncEditMode()
  },

  updated() {
    if (this.gestureActive()) return
    this.reconcileItems()
    this.syncEditMode()
  },

  destroyed() {
    clearTimeout(this.pushTimer)
    if (this.grid) this.grid.destroy(false)
  },

  editMode() {
    return this.el.dataset.editMode === "true"
  },

  gestureActive() {
    return Boolean(
      this.el.querySelector(".ui-draggable-dragging, .ui-resizable-resizing")
    )
  },

  syncEditMode() {
    const editing = this.editMode()
    // Read GridStack's own state, not the grid-stack-static class: LiveView
    // patches rewrite the container's class attribute and strip it.
    const isStatic = this.grid.opts.staticGrid === true

    if (editing && isStatic) {
      this.grid.setStatic(false)
      // Classic GridStack reflow while editing: dragging into an occupied
      // space pushes neighbors and everything compacts upward. The initial
      // compaction fires "change", so it autosaves like any other move.
      this.grid.float(false)
    } else if (!editing && !isStatic) {
      this.flushLayout()
      this.grid.float(true)
      this.grid.setStatic(true)
    }

    this.el.classList.toggle("grid-stack-static", !editing)
  },

  reconcileItems() {
    const items = Array.from(this.el.querySelectorAll(":scope > .grid-stack-item"))

    items.forEach((el) => {
      if (!el.gridstackNode) {
        this.grid.makeWidget(el)
      } else if (this.editMode() && !el.classList.contains("ui-draggable")) {
        this.grid.movable(el, true)
        this.grid.resizable(el, true)
      }
    })

    this.grid.engine.nodes
      .filter(
        (node) =>
          node.el &&
          !node.el.isConnected &&
          // node.el is the placeholder mid-gesture; never treat it as a removal
          !node.el.classList.contains("grid-stack-placeholder")
      )
      .forEach((node) => this.grid.removeWidget(node.el, false, false))
  },

  scheduleLayoutPush() {
    clearTimeout(this.pushTimer)
    this.pushTimer = setTimeout(() => this.flushLayout(), LAYOUT_PUSH_DEBOUNCE_MS)
  },

  flushLayout() {
    if (this.pushTimer) {
      clearTimeout(this.pushTimer)
      this.pushTimer = null
    }
    if (!this.editMode()) return

    const layouts = this.grid.engine.nodes
      .filter((node) => node.el && node.el.isConnected)
      .map((node) => ({
        widget_id: node.el.getAttribute("gs-id"),
        x: node.x,
        y: node.y,
        w: node.w,
        h: node.h,
      }))

    if (layouts.length > 0) {
      this.pushEvent("layout_changed", { layouts })
    }
  },
}

export default DashboardGrid
