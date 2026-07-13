// Ops rail expand/collapse with localStorage persistence. The expanded state
// lives in a data attribute so Tailwind's data-[expanded] variants style both
// states; updated() re-applies it (and any dragged width) after LiveView
// patches.
//
// A rail opts into drag-resizing by rendering a [data-rail-resize] handle on
// its content-facing edge. Dragging sets an inline width (which wins over the
// data-[expanded] width class); dragging narrower than the snap threshold
// collapses the rail, dragging back out re-expands it. The dragged width is
// persisted with the expanded state.
const SNAP_WIDTH = 140
const MAX_WIDTH = 480
const MIN_CANVAS_WIDTH = 360
const COORDINATED_BREAKPOINT = 1100

const NavRail = {
  mounted() {
    this.storageKey = this.el.dataset.storageKey || "cadence-ops-rail"
    this.handle = this.el.querySelector("[data-rail-resize]")
    this.readState()
    this.apply()

    this.onViewportResize = () => this.apply()
    this.onPeerExpanded = (event) => {
      if (event.detail !== this.el && window.innerWidth < COORDINATED_BREAKPOINT && this.expanded) {
        this.expanded = false
        this.persist()
        this.apply()
      }
    }
    window.addEventListener("resize", this.onViewportResize)
    window.addEventListener("cadence:rail-expanded", this.onPeerExpanded)

    this.el.addEventListener("click", (event) => {
      if (event.target.closest("[data-rail-toggle]")) {
        this.expanded = !this.expanded
        this.persist()
        this.apply()
        if (this.expanded) {
          window.dispatchEvent(new CustomEvent("cadence:rail-expanded", {detail: this.el}))
        }
      }
    })

    if (this.handle) this.bindResize()
  },

  updated() {
    this.apply()
  },

  destroyed() {
    window.removeEventListener("resize", this.onViewportResize)
    window.removeEventListener("cadence:rail-expanded", this.onPeerExpanded)
  },

  readState() {
    const stored = localStorage.getItem(this.storageKey)
    // data-default-expanded opts a rail into starting open (the ops context
    // rail); without it rails start collapsed (the nav rail).
    const defaultExpanded = this.el.hasAttribute("data-default-expanded")
    this.width = null

    if (!stored) {
      this.expanded = defaultExpanded
      return
    }

    try {
      const parsed = JSON.parse(stored)
      this.expanded = parsed.state === "expanded"
      if (Number.isFinite(parsed.width)) this.width = parsed.width
    } catch {
      // pre-resize format: a bare "expanded" / "collapsed" string
      this.expanded = stored === "expanded"
    }
  },

  persist() {
    localStorage.setItem(
      this.storageKey,
      JSON.stringify({ state: this.expanded ? "expanded" : "collapsed", width: this.width })
    )
  },

  apply() {
    if (this.expanded) {
      this.el.setAttribute("data-expanded", "")
      const peerWidth = Array.from(document.querySelectorAll("[data-rail-role]"))
        .filter((rail) => rail !== this.el)
        .reduce((width, rail) => width + rail.getBoundingClientRect().width, 0)
      const available = Math.max(SNAP_WIDTH, window.innerWidth - peerWidth - MIN_CANVAS_WIDTH)
      const defaultWidth = this.el.dataset.railRole === "context" ? 288 : 224
      const preferredWidth = this.handle && this.width ? this.width : defaultWidth
      const width = Math.min(preferredWidth, available, MAX_WIDTH)
      this.el.style.width = width < preferredWidth || this.width ? `${width}px` : ""
    } else {
      this.el.removeAttribute("data-expanded")
      this.el.style.width = ""
    }
  },

  bindResize() {
    this.handle.addEventListener("pointerdown", (event) => {
      event.preventDefault()
      try {
        this.handle.setPointerCapture(event.pointerId)
      } catch {
        // no active pointer (synthetic events); window listeners cover it
      }

      const startX = event.clientX
      const startWidth = this.el.getBoundingClientRect().width
      const previousTransition = this.el.style.transition
      this.el.style.transition = "none"

      const move = (ev) => {
        // The handle sits on the rail's left edge: dragging left widens.
        const raw = startWidth + (startX - ev.clientX)
        this.expanded = raw >= SNAP_WIDTH
        if (this.expanded) this.width = Math.min(Math.round(raw), MAX_WIDTH)
        this.apply()
      }

      const up = () => {
        window.removeEventListener("pointermove", move)
        window.removeEventListener("pointercancel", up)
        this.el.style.transition = previousTransition
        // A drag that ends collapsed keeps the width it started from, so
        // re-expanding restores the last deliberately chosen width instead of
        // the last pixel before the snap.
        if (!this.expanded && startWidth >= SNAP_WIDTH) this.width = Math.round(startWidth)
        this.persist()
      }

      window.addEventListener("pointermove", move)
      window.addEventListener("pointerup", up, { once: true })
      window.addEventListener("pointercancel", up, { once: true })
    })
  },
}

export default NavRail
