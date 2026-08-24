const menuItemSelector = "[role='menuitem'], a, button"

export const createDropdownController = ({
  rootElement,
  documentObject = document,
}) => {
  let trigger = null
  let menu = null
  let mounted = false
  let documentListenersAttached = false

  const items = () =>
    menu ? Array.from(menu.querySelectorAll(menuItemSelector)) : []

  const isOpen = () => rootElement.classList.contains("dropdown-open")

  const focusItem = (index) => {
    const focusableItems = items()
    if (focusableItems[index]) focusableItems[index].focus()
  }

  const moveFocus = (delta) => {
    const focusableItems = items()
    if (focusableItems.length === 0) return

    const index = focusableItems.indexOf(documentObject.activeElement)
    const next =
      index === -1
        ? 0
        : (index + delta + focusableItems.length) % focusableItems.length

    focusableItems[next].focus()
  }

  const detachDocumentListeners = () => {
    if (!documentListenersAttached) return

    documentObject.removeEventListener("pointerdown", onPointerDown)
    documentObject.removeEventListener("keydown", onDocumentKeyDown)
    documentListenersAttached = false
  }

  const attachDocumentListeners = () => {
    if (documentListenersAttached) return

    documentObject.addEventListener("pointerdown", onPointerDown)
    documentObject.addEventListener("keydown", onDocumentKeyDown)
    documentListenersAttached = true
  }

  const open = () => {
    if (!trigger || !menu || isOpen()) return

    rootElement.classList.add("dropdown-open")
    trigger.setAttribute("aria-expanded", "true")
    attachDocumentListeners()
    focusItem(0)
  }

  const close = ({refocus = true} = {}) => {
    if (!trigger || !isOpen()) return

    rootElement.classList.remove("dropdown-open")
    trigger.setAttribute("aria-expanded", "false")
    detachDocumentListeners()
    if (refocus) trigger.focus()
  }

  function onPointerDown(event) {
    if (!rootElement.contains(event.target)) close()
  }

  function onDocumentKeyDown(event) {
    switch (event.key) {
      case "Escape":
        event.preventDefault()
        close()
        break
      case "ArrowDown":
        event.preventDefault()
        moveFocus(1)
        break
      case "ArrowUp":
        event.preventDefault()
        moveFocus(-1)
        break
      case "Home":
        event.preventDefault()
        focusItem(0)
        break
      case "End":
        event.preventDefault()
        focusItem(items().length - 1)
        break
      case "Tab":
        close({refocus: false})
        break
    }
  }

  const onTriggerClick = (event) => {
    event.preventDefault()
    isOpen() ? close() : open()
  }

  const onTriggerKeyDown = (event) => {
    if (event.key === "ArrowDown" && !isOpen()) {
      event.preventDefault()
      open()
    }
  }

  const onMenuClick = (event) => {
    if (event.target?.closest?.("a, button, [role='menuitem']")) {
      close({refocus: false})
    }
  }

  const mount = () => {
    if (mounted) return

    trigger = rootElement.querySelector("[data-dropdown-trigger]")
    menu = rootElement.querySelector("[role='menu']")
    if (!trigger || !menu) return

    trigger.setAttribute("aria-expanded", "false")
    trigger.addEventListener("click", onTriggerClick)
    trigger.addEventListener("keydown", onTriggerKeyDown)
    menu.addEventListener("click", onMenuClick)
    mounted = true
  }

  const destroy = () => {
    detachDocumentListeners()

    if (trigger) {
      trigger.removeEventListener("click", onTriggerClick)
      trigger.removeEventListener("keydown", onTriggerKeyDown)
      trigger.setAttribute("aria-expanded", "false")
    }

    if (menu) menu.removeEventListener("click", onMenuClick)

    rootElement.classList.remove("dropdown-open")
    trigger = null
    menu = null
    mounted = false
  }

  return {
    close,
    destroy,
    isOpen,
    items,
    mount,
    open,
  }
}
