<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"

type AttrValue = string | boolean | null
type Attrs = Record<string, AttrValue>

type MenuPresentation = {
  root: {attrs: Attrs}
  trigger: {attrs: Attrs; icon_class: string}
  panel: {
    attrs: Attrs
    items: Array<{
      key: string
      wrapper: {attrs: Attrs}
      link: {
        attrs: Attrs
        icon_class: string
        text: string
        badge: {class: string; attrs: Attrs; text: string} | null
      }
    }>
  }
}

defineProps<{presentation: MenuPresentation}>()
const root = ref<HTMLElement | null>(null)

// DASHBOARD_TOOLBAR_MENU_CONTROLLER_START
const createDashboardToolbarMenuController = ({rootElement, documentObject, windowObject}) => {
  const state = {
    rootElement,
    trigger: null,
    panel: null,
    boundTrigger: null,
    boundPanel: null,
    open: false,
    wasOpen: false,
    preservedOverlayIdentity: null,
  }

  const bindElements = () => {
    state.trigger = state.rootElement.querySelector(":scope > [data-overlay-trigger]")
    state.panel = state.rootElement.querySelector(":scope > [data-overlay-panel]")
  }

  const teardown = () => {
    documentObject.removeEventListener("pointerdown", onDocumentPointerDown)
    documentObject.removeEventListener("keydown", onDocumentKeyDown)
  }

  const bindDocumentListeners = () => {
    documentObject.addEventListener("pointerdown", onDocumentPointerDown)
    documentObject.addEventListener("keydown", onDocumentKeyDown)
  }

  const clearPanelPosition = (panel = state.panel) => {
    if (panel) panel.style.transform = ""
  }

  const sync = () => {
    state.rootElement.toggleAttribute("data-overlay-open", state.open)
    if (!state.trigger || !state.panel) return
    state.trigger.setAttribute("aria-expanded", state.open ? "true" : "false")
    state.panel.hidden = !state.open
  }

  const positionPanel = () => {
    if (!state.panel) return
    clearPanelPosition()
    const rect = state.panel.getBoundingClientRect()
    const gutter = 16
    let offset = 0
    if (rect.left < gutter) offset = gutter - rect.left
    if (rect.right + offset > windowObject.innerWidth - gutter) {
      offset -= rect.right + offset - (windowObject.innerWidth - gutter)
    }
    if (offset) state.panel.style.transform = `translateX(${Math.round(offset)}px)`
  }

  const items = () =>
    Array.from(state.panel?.querySelectorAll("[role='menuitem'], a, button") || []).filter(
      (item) => !item.disabled,
    )

  const close = ({restoreFocus = true} = {}) => {
    if (!state.open) return
    state.open = false
    sync()
    teardown()
    if (restoreFocus && state.trigger?.isConnected) state.trigger.focus()
  }

  const show = () => {
    windowObject.dispatchEvent(
      new windowObject.CustomEvent("cadence:overlay-opened", {detail: state.rootElement}),
    )
    state.open = true
    sync()
    positionPanel()
    bindDocumentListeners()
    items()[0]?.focus()
  }

  const onTriggerClick = (event) => {
    event.preventDefault()
    state.open ? close() : show()
  }

  function onDocumentPointerDown(event) {
    if (!state.rootElement.contains(event.target)) close({restoreFocus: false})
  }

  function onDocumentKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      close()
      return
    }

    const menuItems = items()
    const index = menuItems.indexOf(documentObject.activeElement)
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const delta = event.key === "ArrowDown" ? 1 : -1
      menuItems[(index + delta + menuItems.length) % menuItems.length]?.focus()
    } else if (event.key === "Home") {
      event.preventDefault()
      menuItems[0]?.focus()
    } else if (event.key === "End") {
      event.preventDefault()
      menuItems[menuItems.length - 1]?.focus()
    } else if (event.key === "Tab") {
      close({restoreFocus: false})
    }
  }

  const onOverlayOpened = (event) => {
    if (event.detail !== state.rootElement) close({restoreFocus: false})
  }

  const onPanelClick = (event) => {
    if (event.target.closest("a, button, [role='menuitem']")) close({restoreFocus: false})
  }

  const bindElementListeners = () => {
    if (state.boundTrigger !== state.trigger) {
      state.boundTrigger?.removeEventListener("click", onTriggerClick)
      state.trigger?.addEventListener("click", onTriggerClick)
      state.boundTrigger = state.trigger
    }
    if (state.boundPanel !== state.panel) {
      state.boundPanel?.removeEventListener("click", onPanelClick)
      state.panel?.addEventListener("click", onPanelClick)
      state.boundPanel = state.panel
    }
  }

  const unbindElementListeners = () => {
    state.boundTrigger?.removeEventListener("click", onTriggerClick)
    state.boundPanel?.removeEventListener("click", onPanelClick)
    state.boundTrigger = null
    state.boundPanel = null
  }

  const mounted = () => {
    bindElements()
    if (!state.trigger || !state.panel) return
    bindElementListeners()
    windowObject.addEventListener("cadence:overlay-opened", onOverlayOpened)
  }

  const beforeUpdate = () => {
    state.wasOpen = state.open
    state.preservedOverlayIdentity = state.open ? state.rootElement.id : null
    teardown()
    clearPanelPosition()
  }

  const updated = (root = state.rootElement) => {
    state.rootElement = root
    bindElements()
    bindElementListeners()
    state.open =
      state.wasOpen &&
      state.preservedOverlayIdentity === state.rootElement.id &&
      Boolean(state.trigger && state.panel)
    sync()
    if (state.open) {
      positionPanel()
      bindDocumentListeners()
    }
    state.wasOpen = false
    state.preservedOverlayIdentity = null
  }

  const destroyed = () => {
    teardown()
    state.open = false
    sync()
    clearPanelPosition()
    unbindElementListeners()
    windowObject.removeEventListener("cadence:overlay-opened", onOverlayOpened)
  }

  return {state, mounted, beforeUpdate, updated, destroyed, show, close, sync, positionPanel}
}
// DASHBOARD_TOOLBAR_MENU_CONTROLLER_END

let controller = null

onMounted(() => {
  if (!root.value) return
  controller = createDashboardToolbarMenuController({
    rootElement: root.value,
    documentObject: document,
    windowObject: window,
  })
  controller.mounted()
})

onBeforeUpdate(() => controller?.beforeUpdate())
onUpdated(() => {
  if (root.value) controller?.updated(root.value)
})

onBeforeUnmount(() => {
  controller?.destroyed()
  controller = null
})
</script>

<template>
  <div v-bind="presentation.root.attrs" ref="root">
    <button v-bind="presentation.trigger.attrs">
      <span :class="presentation.trigger.icon_class"></span>
    </button>
    <div v-bind="presentation.panel.attrs">
      <div v-for="item in presentation.panel.items" :key="item.key" v-bind="item.wrapper.attrs">
        <a v-bind="item.link.attrs">
          <span :class="item.link.icon_class"></span>
          {{ item.link.text }}
          <span v-if="item.link.badge" :class="item.link.badge.class" v-bind="item.link.badge.attrs">
            {{ item.link.badge.text }}
          </span>
        </a>
      </div>
    </div>
  </div>
</template>
