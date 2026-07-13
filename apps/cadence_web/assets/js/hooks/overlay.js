const Overlay = {
  mounted() {
    this.bindElements()
    if (!this.trigger || !this.panel) return

    this.open = false
    this.onTriggerClick = (event) => {
      event.preventDefault()
      this.open ? this.close() : this.show()
    }
    this.onDocumentPointerDown = (event) => {
      if (!this.el.contains(event.target)) this.close({restoreFocus: false})
    }
    this.onDocumentKeyDown = (event) => this.handleKeyDown(event)
    this.onOverlayOpened = (event) => {
      if (event.detail !== this.el) this.close({restoreFocus: false})
    }
    this.onPanelClick = (event) => {
      if (this.el.dataset.overlayKind === "menu" && event.target.closest("a, button, [role='menuitem']")) {
        this.close({restoreFocus: false})
      }
    }

    this.bindElementListeners()
    window.addEventListener("cadence:overlay-opened", this.onOverlayOpened)
  },

  beforeUpdate() {
    this.wasOpen = this.open
    this.teardown()
  },

  updated() {
    this.bindElements()
    this.bindElementListeners()
    this.open = this.wasOpen && Boolean(this.trigger && this.panel)
    this.sync()
    if (this.open) {
      this.positionPanel()
      this.bindDocumentListeners()
    }
    this.wasOpen = false
  },

  destroyed() {
    this.teardown()
    this.unbindElementListeners()
    window.removeEventListener("cadence:overlay-opened", this.onOverlayOpened)
  },

  bindElements() {
    this.trigger = this.el.querySelector(":scope > [data-overlay-trigger]")
    this.panel = this.el.querySelector(":scope > [data-overlay-panel]")
  },

  bindElementListeners() {
    if (this.boundTrigger !== this.trigger) {
      this.boundTrigger?.removeEventListener("click", this.onTriggerClick)
      this.trigger?.addEventListener("click", this.onTriggerClick)
      this.boundTrigger = this.trigger
    }
    if (this.boundPanel !== this.panel) {
      this.boundPanel?.removeEventListener("click", this.onPanelClick)
      this.panel?.addEventListener("click", this.onPanelClick)
      this.boundPanel = this.panel
    }
  },

  unbindElementListeners() {
    this.boundTrigger?.removeEventListener("click", this.onTriggerClick)
    this.boundPanel?.removeEventListener("click", this.onPanelClick)
    this.boundTrigger = null
    this.boundPanel = null
  },

  show() {
    window.dispatchEvent(new CustomEvent("cadence:overlay-opened", {detail: this.el}))
    this.open = true
    this.sync()
    this.positionPanel()
    this.bindDocumentListeners()
    if (this.el.dataset.overlayKind === "menu") this.items()[0]?.focus()
  },

  bindDocumentListeners() {
    document.addEventListener("pointerdown", this.onDocumentPointerDown)
    document.addEventListener("keydown", this.onDocumentKeyDown)
  },

  close({restoreFocus = true} = {}) {
    if (!this.open) return
    this.open = false
    this.sync()
    this.teardown()
    if (restoreFocus && this.trigger?.isConnected) this.trigger.focus()
  },

  sync() {
    if (!this.trigger || !this.panel) return
    this.trigger.setAttribute("aria-expanded", this.open ? "true" : "false")
    this.panel.hidden = !this.open
    this.el.toggleAttribute("data-overlay-open", this.open)
  },

  positionPanel() {
    this.panel.style.transform = ""
    const rect = this.panel.getBoundingClientRect()
    const gutter = 16
    let offset = 0
    if (rect.left < gutter) offset = gutter - rect.left
    if (rect.right + offset > window.innerWidth - gutter) {
      offset -= rect.right + offset - (window.innerWidth - gutter)
    }
    if (offset) this.panel.style.transform = `translateX(${Math.round(offset)}px)`
  },

  teardown() {
    document.removeEventListener("pointerdown", this.onDocumentPointerDown)
    document.removeEventListener("keydown", this.onDocumentKeyDown)
  },

  items() {
    return Array.from(this.panel.querySelectorAll("[role='menuitem'], a, button")).filter((item) => !item.disabled)
  },

  handleKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (this.el.dataset.overlayKind !== "menu") return
    const items = this.items()
    const index = items.indexOf(document.activeElement)
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const delta = event.key === "ArrowDown" ? 1 : -1
      items[(index + delta + items.length) % items.length]?.focus()
    } else if (event.key === "Home") {
      event.preventDefault()
      items[0]?.focus()
    } else if (event.key === "End") {
      event.preventDefault()
      items[items.length - 1]?.focus()
    } else if (event.key === "Tab") {
      this.close({restoreFocus: false})
    }
  },
}

export default Overlay
