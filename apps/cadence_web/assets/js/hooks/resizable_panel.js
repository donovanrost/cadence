/**
 * ResizablePanel — LiveView hook for drag-to-resize split panels.
 *
 * Attach to the drag handle element between two flex children. The handle
 * reads configuration from data attributes:
 *
 *   data-panel-id      — ID of the panel whose width is being controlled
 *   data-storage-key   — localStorage key for persisting the width
 *   data-min-width     — minimum width in pixels (default: 150)
 *   data-max-width-pct — maximum width as % of container (default: 60)
 *
 * The controlled panel uses `flex: 0 0 {width}` and the other panel uses
 * `flex: 1` to fill the remaining space.
 */
const ResizablePanel = {
  mounted() {
    this.panelId = this.el.dataset.panelId
    this.storageKey = this.el.dataset.storageKey
    this.minWidth = parseInt(this.el.dataset.minWidth || "150")
    this.maxWidthPct = parseInt(this.el.dataset.maxWidthPct || "60")
    this.panel = document.getElementById(this.panelId)
    this.container = this.el.parentElement
    this.grip = this.el.firstElementChild
    this.isDragging = false

    // Restore saved width from localStorage
    const saved = localStorage.getItem(this.storageKey)
    if (saved && this.panel) {
      this.panel.style.flex = `0 0 ${saved}%`
    }

    this._onMouseDown = (e) => this._startDrag(e)
    this._onMouseMove = (e) => this._onDrag(e)
    this._onMouseUp = () => this._endDrag()
    this._onTouchStart = (e) => this._startDrag(e.touches[0])
    this._onTouchMove = (e) => { if (this.isDragging) { e.preventDefault(); this._onDrag(e.touches[0]) } }
    this._onTouchEnd = () => this._endDrag()

    this.el.addEventListener("mousedown", this._onMouseDown)
    this.el.addEventListener("touchstart", this._onTouchStart, { passive: false })
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
    document.addEventListener("touchmove", this._onTouchMove, { passive: false })
    document.addEventListener("touchend", this._onTouchEnd)
  },

  _startDrag(e) {
    if (!this.panel) return
    this.isDragging = true
    this.startX = e.clientX
    this.startWidth = this.panel.offsetWidth
    document.body.style.cursor = "col-resize"
    document.body.style.userSelect = "none"

    if (this.grip) {
      this.grip.style.background = "oklch(from var(--color-primary) l c h / 0.8)"
      this.grip.style.height = "5rem"
      this.grip.style.boxShadow = "0 0 12px oklch(from var(--color-primary) l c h / 0.5)"
    }
  },

  _onDrag(e) {
    if (!this.isDragging || !this.panel || !this.container) return
    const diff = e.clientX - this.startX
    const containerWidth = this.container.offsetWidth
    const maxWidth = containerWidth * (this.maxWidthPct / 100)
    const newWidth = Math.max(this.minWidth, Math.min(maxWidth, this.startWidth + diff))
    this.panel.style.flex = `0 0 ${newWidth}px`
  },

  _endDrag() {
    if (!this.isDragging) return
    this.isDragging = false
    document.body.style.cursor = ""
    document.body.style.userSelect = ""

    if (this.grip) {
      this.grip.style.background = ""
      this.grip.style.height = ""
      this.grip.style.boxShadow = ""
    }

    // Persist as percentage
    if (this.panel && this.container && this.storageKey) {
      const pct = (this.panel.offsetWidth / this.container.offsetWidth) * 100
      localStorage.setItem(this.storageKey, pct.toFixed(1))
    }
  },

  destroyed() {
    this.el.removeEventListener("mousedown", this._onMouseDown)
    this.el.removeEventListener("touchstart", this._onTouchStart)
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
    document.removeEventListener("touchmove", this._onTouchMove)
    document.removeEventListener("touchend", this._onTouchEnd)
  }
}

export default ResizablePanel
