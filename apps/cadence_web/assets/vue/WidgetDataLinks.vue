<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"

type Attrs = Record<string, string | null>

type IconPresentation = {
  name: string
  class: string
}

type ItemPresentation = {
  key: string
  kind: "data_link" | "evidence"
  type: string
  class: string
  attrs: Attrs
  label: {text: string; class: string | null}
  secondary: {text: string; class: string} | null
  icon: IconPresentation | null
}

type WidgetDataLinksPresentation = {
  kind:
    | "widget"
    | "status_matrix_row"
    | "data_table_row"
    | "state_timeline_row"
    | "event_timeline_row"
  component_id: string
  overlay: {id: string; class: string; attrs: Attrs}
  trigger: {
    id: string
    type: string
    class: string
    attrs: Attrs
    content: {
      class: string
      title: string
      attrs: Attrs
      icon: IconPresentation
    }
  }
  panel: {id: string; class: string; hidden: boolean; attrs: Attrs}
  body: {class: string}
  items: ItemPresentation[]
}

const props = defineProps<{presentation: WidgetDataLinksPresentation}>()
const root = ref<HTMLElement | null>(null)

// WIDGET_DATA_LINKS_CONTROLLER_START
const createWidgetDataLinksController = ({rootElement, documentObject, windowObject}) => {
  const state = {
    rootElement,
    trigger: null,
    panel: null,
    boundTrigger: null,
    boundPanel: null,
    open: false,
    wasOpen: false,
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

  const sync = () => {
    if (!state.trigger || !state.panel) return
    state.trigger.setAttribute("aria-expanded", state.open ? "true" : "false")
    state.panel.hidden = !state.open
    state.rootElement.toggleAttribute("data-overlay-open", state.open)
  }

  const positionPanel = () => {
    if (!state.panel) return
    state.panel.style.transform = ""
    const rect = state.panel.getBoundingClientRect()
    const gutter = 16
    let offset = 0
    if (rect.left < gutter) offset = gutter - rect.left
    if (rect.right + offset > windowObject.innerWidth - gutter) {
      offset -= rect.right + offset - (windowObject.innerWidth - gutter)
    }
    if (offset) state.panel.style.transform = `translateX(${Math.round(offset)}px)`
  }

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
  }

  const onTriggerClick = (event) => {
    event.preventDefault()
    state.open ? close() : show()
  }

  function onDocumentPointerDown(event) {
    if (!state.rootElement.contains(event.target)) close({restoreFocus: false})
  }

  function onDocumentKeyDown(event) {
    if (event.key !== "Escape") return
    event.preventDefault()
    close()
  }

  const onOverlayOpened = (event) => {
    if (event.detail !== state.rootElement) close({restoreFocus: false})
  }

  const onPanelClick = () => {}

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
    teardown()
  }

  const updated = () => {
    bindElements()
    bindElementListeners()
    state.open = state.wasOpen && Boolean(state.trigger && state.panel)
    sync()
    if (state.open) {
      positionPanel()
      bindDocumentListeners()
    }
    state.wasOpen = false
  }

  const destroyed = () => {
    teardown()
    unbindElementListeners()
    windowObject.removeEventListener("cadence:overlay-opened", onOverlayOpened)
  }

  return {state, mounted, beforeUpdate, updated, destroyed, show, close, sync, positionPanel}
}
// WIDGET_DATA_LINKS_CONTROLLER_END

let controller = null

onMounted(() => {
  if (!root.value) return
  controller = createWidgetDataLinksController({
    rootElement: root.value,
    documentObject: document,
    windowObject: window,
  })
  controller.mounted()
})

onBeforeUpdate(() => controller?.beforeUpdate())
onUpdated(() => controller?.updated())

onBeforeUnmount(() => {
  controller?.destroyed()
  controller = null
})
</script>

<template>
  <div
    :id="presentation.overlay.id"
    ref="root"
    :class="presentation.overlay.class"
    v-bind="presentation.overlay.attrs"
  >
    <button
      :id="presentation.trigger.id"
      :type="presentation.trigger.type"
      :class="presentation.trigger.class"
      v-bind="presentation.trigger.attrs"
    >
      <span
        :class="presentation.trigger.content.class"
        :title="presentation.trigger.content.title"
        v-bind="presentation.trigger.content.attrs"
      >
        <span
          :class="[
            presentation.trigger.content.icon.name,
            presentation.trigger.content.icon.class,
          ]"
        ></span>
      </span>
    </button>
    <section
      :id="presentation.panel.id"
      :class="presentation.panel.class"
      :hidden="presentation.panel.hidden"
      v-bind="presentation.panel.attrs"
    >
      <div :class="presentation.body.class">
        <button
          v-for="item in presentation.items"
          :key="item.key"
          :type="item.type"
          :class="item.class"
          v-bind="item.attrs"
        >
          <span :class="item.label.class">{{ item.label.text }}</span>
          <span v-if="item.secondary" :class="item.secondary.class">
            {{ item.secondary.text }}
          </span>
          <span
            v-if="item.icon"
            :class="[item.icon.name, item.icon.class]"
          ></span>
        </button>
      </div>
    </section>
  </div>
</template>
