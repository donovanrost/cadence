<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"

type Attrs = Record<string, string>

type IconPresentation = {
  name: string
  class: string
}

type TextPresentation = {
  class: string
  text: string
}

type RowPresentation = {
  key: string
  order: number
  label: TextPresentation & {attrs: Attrs}
  value: TextPresentation & {attrs: Attrs}
}

type WidgetQueryDiagnosticsPresentation = {
  component_id: string
  overlay: {id: string; class: string; attrs: Attrs}
  trigger: {
    id: string
    type: string
    class: string
    attrs: Attrs
    content: {class: string; attrs: Attrs; icon: IconPresentation}
  }
  panel: {id: string; class: string; hidden: boolean; attrs: Attrs}
  body: {
    class: string
    heading: TextPresentation
    rows_class: string
    rows: RowPresentation[]
    evidence_button: {
      type: string
      class: string
      attrs: Attrs
      icon: IconPresentation
      text: string
    }
  }
}

const props = defineProps<{presentation: WidgetQueryDiagnosticsPresentation}>()
const root = ref<HTMLElement | null>(null)

// WIDGET_QUERY_DIAGNOSTICS_CONTROLLER_START
const createWidgetQueryDiagnosticsController = ({rootElement, documentObject, windowObject}) => {
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
    state.preservedOverlayIdentity = state.open ? state.rootElement.id : null
    teardown()
    clearPanelPosition()
  }

  const updated = () => {
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
// WIDGET_QUERY_DIAGNOSTICS_CONTROLLER_END

let controller = null

onMounted(() => {
  if (!root.value) return
  controller = createWidgetQueryDiagnosticsController({
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
    :id="props.presentation.overlay.id"
    ref="root"
    :class="props.presentation.overlay.class"
    v-bind="props.presentation.overlay.attrs"
  >
    <button
      :id="props.presentation.trigger.id"
      :type="props.presentation.trigger.type"
      :class="props.presentation.trigger.class"
      v-bind="props.presentation.trigger.attrs"
    >
      <span
        :class="props.presentation.trigger.content.class"
        v-bind="props.presentation.trigger.content.attrs"
      >
        <span
          :class="[
            props.presentation.trigger.content.icon.name,
            props.presentation.trigger.content.icon.class,
          ]"
        ></span>
      </span>
    </button>
    <section
      :id="props.presentation.panel.id"
      :class="props.presentation.panel.class"
      :hidden="props.presentation.panel.hidden"
      v-bind="props.presentation.panel.attrs"
    >
      <div :class="props.presentation.body.class">
        <div :class="props.presentation.body.heading.class">
          {{ props.presentation.body.heading.text }}
        </div>
        <dl :class="props.presentation.body.rows_class">
          <template v-for="row in props.presentation.body.rows" :key="row.key">
            <dt :class="row.label.class" v-bind="row.label.attrs">
              {{ row.label.text }}
            </dt>
            <dd :class="row.value.class" v-bind="row.value.attrs">
              {{ row.value.text }}
            </dd>
          </template>
        </dl>
        <button
          :type="props.presentation.body.evidence_button.type"
          :class="props.presentation.body.evidence_button.class"
          v-bind="props.presentation.body.evidence_button.attrs"
        >
          <span
            :class="[
              props.presentation.body.evidence_button.icon.name,
              props.presentation.body.evidence_button.icon.class,
            ]"
          ></span>
          {{ props.presentation.body.evidence_button.text }}
        </button>
      </div>
    </section>
  </div>
</template>
