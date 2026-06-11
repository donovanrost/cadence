// Accessible dropdown menu behavior for daisyUI .dropdown wrappers.
//
// Markup contract (see CadenceWeb.CoreComponents.action_menu):
//   hook element  — the .dropdown wrapper (id required)
//   trigger       — <button data-dropdown-trigger aria-haspopup="menu"
//                    aria-expanded="false" aria-controls="{id}-menu">
//   menu          — the dropdown-content element with role="menu";
//                    items carry role="menuitem"
//
// Behavior: click or ArrowDown opens (focusing the first item); Escape
// closes and returns focus to the trigger; Arrow/Home/End rove focus with
// wrap; Tab and click-outside close; activating an item closes. Visibility
// is toggled via daisyUI's own `dropdown-open` class so existing styling
// applies unchanged.
const DropdownMenu = {
  mounted() {
    this.trigger = this.el.querySelector("[data-dropdown-trigger]")
    this.menu = this.el.querySelector("[role='menu']")
    if (!this.trigger || !this.menu) return

    this.onPointerDown = (event) => {
      if (!this.el.contains(event.target)) this.close()
    }
    this.onKeyDown = (event) => this.handleKey(event)

    this.trigger.addEventListener("click", (event) => {
      event.preventDefault()
      this.isOpen() ? this.close() : this.open()
    })
    this.trigger.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown" && !this.isOpen()) {
        event.preventDefault()
        this.open()
      }
    })
    this.menu.addEventListener("click", (event) => {
      if (event.target.closest("a, button, [role='menuitem']")) {
        this.close({refocus: false})
      }
    })
  },

  destroyed() {
    this.teardown()
  },

  isOpen() {
    return this.el.classList.contains("dropdown-open")
  },

  open() {
    this.el.classList.add("dropdown-open")
    this.trigger.setAttribute("aria-expanded", "true")
    document.addEventListener("pointerdown", this.onPointerDown)
    document.addEventListener("keydown", this.onKeyDown)
    const [first] = this.items()
    if (first) first.focus()
  },

  close({refocus = true} = {}) {
    if (!this.isOpen()) return
    this.el.classList.remove("dropdown-open")
    this.trigger.setAttribute("aria-expanded", "false")
    this.teardown()
    if (refocus) this.trigger.focus()
  },

  teardown() {
    document.removeEventListener("pointerdown", this.onPointerDown)
    document.removeEventListener("keydown", this.onKeyDown)
  },

  // Menu items are whatever interactive elements the slots rendered —
  // links, buttons, or explicitly-annotated role="menuitem" elements.
  items() {
    return Array.from(this.menu.querySelectorAll("[role='menuitem'], a, button"))
  },

  handleKey(event) {
    switch (event.key) {
      case "Escape":
        event.preventDefault()
        this.close()
        break
      case "ArrowDown":
        event.preventDefault()
        this.moveFocus(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.moveFocus(-1)
        break
      case "Home":
        event.preventDefault()
        this.focusItem(0)
        break
      case "End":
        event.preventDefault()
        this.focusItem(this.items().length - 1)
        break
      case "Tab":
        this.close({refocus: false})
        break
    }
  },

  moveFocus(delta) {
    const items = this.items()
    if (items.length === 0) return
    const index = items.indexOf(document.activeElement)
    const next = index === -1 ? 0 : (index + delta + items.length) % items.length
    items[next].focus()
  },

  focusItem(index) {
    const items = this.items()
    if (items[index]) items[index].focus()
  },
}

export default DropdownMenu
