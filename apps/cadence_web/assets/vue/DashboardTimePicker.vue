<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"

import DashboardAbsoluteRangePane from "./DashboardAbsoluteRangePane.vue"
import DashboardQuickRangeList from "./DashboardQuickRangeList.vue"
import DashboardSelectedDatumActions from "./DashboardSelectedDatumActions.vue"
import DashboardTimeReplay from "./DashboardTimeReplay.vue"

type AttrValue = string | boolean | null
type Attrs = Record<string, AttrValue>

type ButtonPresentation = {
  attrs: Attrs
  icon_class: string
}

type DashboardTimePickerPresentation = {
  shift_back: ButtonPresentation | false
  overlay: {
    root: {attrs: Attrs}
    trigger: {
      attrs: Attrs
      live_indicator: {attrs: Attrs}
      active_range: {attrs: Attrs; text: string}
      icon_class: string
    }
    panel: {
      attrs: Attrs
      header: {
        class: string
        icon_class: string
        title: {class: string; text: string}
        description: {class: string; text: string}
      }
      body: {
        class: string
        controls: {attrs: Attrs}
      }
    }
  }
  time_picker: {
    class: string
    absolute_range_host: {attrs: Attrs}
    absolute_range: Record<string, unknown>
    quick_ranges_host: {attrs: Attrs}
    quick_ranges: Record<string, unknown>
  }
  replay_host: {attrs: Attrs}
  replay: Record<string, unknown>
  selected_datum_host: {attrs: Attrs}
  selected_datum: Record<string, unknown>
  shift_forward: ButtonPresentation | false
  zoom_out: ButtonPresentation | false
}

const props = defineProps<{presentation: DashboardTimePickerPresentation}>()
const emit = defineEmits(["recents-loaded", "select-range"])
const root = ref<HTMLElement | null>(null)

const forwardRecentsLoaded = (payload: unknown) => emit("recents-loaded", payload)
const forwardSelectRange = (payload: unknown) => emit("select-range", payload)

// DASHBOARD_TIME_PICKER_CONTROLLER_START
const createDashboardTimePickerController = ({rootElement, documentObject, windowObject}) => {
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
// DASHBOARD_TIME_PICKER_CONTROLLER_END

let controller = null

onMounted(() => {
  if (!root.value) return
  controller = createDashboardTimePickerController({
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
  <button v-if="props.presentation.shift_back" v-bind="props.presentation.shift_back.attrs">
    <span :class="props.presentation.shift_back.icon_class"></span>
  </button>

  <div v-bind="props.presentation.overlay.root.attrs" ref="root">
    <button v-bind="props.presentation.overlay.trigger.attrs">
      <span v-bind="props.presentation.overlay.trigger.live_indicator.attrs"></span>
      <span v-bind="props.presentation.overlay.trigger.active_range.attrs">
        {{ props.presentation.overlay.trigger.active_range.text }}
      </span>
      <span :class="props.presentation.overlay.trigger.icon_class"></span>
    </button>

    <section v-bind="props.presentation.overlay.panel.attrs">
      <div :class="props.presentation.overlay.panel.header.class">
        <span :class="props.presentation.overlay.panel.header.icon_class"></span>
        <div>
          <p :class="props.presentation.overlay.panel.header.title.class">
            {{ props.presentation.overlay.panel.header.title.text }}
          </p>
          <p :class="props.presentation.overlay.panel.header.description.class">
            {{ props.presentation.overlay.panel.header.description.text }}
          </p>
        </div>
      </div>

      <div :class="props.presentation.overlay.panel.body.class">
        <div v-bind="props.presentation.overlay.panel.body.controls.attrs">
          <div :class="props.presentation.time_picker.class">
            <div v-bind="props.presentation.time_picker.absolute_range_host.attrs">
              <DashboardAbsoluteRangePane
                v-bind="props.presentation.time_picker.absolute_range"
                @recents-loaded="forwardRecentsLoaded"
                @select-range="forwardSelectRange"
              />
            </div>
            <div v-bind="props.presentation.time_picker.quick_ranges_host.attrs">
              <DashboardQuickRangeList :presentation="props.presentation.time_picker.quick_ranges" />
            </div>
          </div>
          <div v-bind="props.presentation.replay_host.attrs">
            <DashboardTimeReplay :presentation="props.presentation.replay" />
          </div>
          <div v-bind="props.presentation.selected_datum_host.attrs">
            <DashboardSelectedDatumActions :presentation="props.presentation.selected_datum" />
          </div>
        </div>
      </div>
    </section>
  </div>

  <button v-if="props.presentation.shift_forward" v-bind="props.presentation.shift_forward.attrs">
    <span :class="props.presentation.shift_forward.icon_class"></span>
  </button>

  <button v-if="props.presentation.zoom_out" v-bind="props.presentation.zoom_out.attrs">
    <span :class="props.presentation.zoom_out.icon_class"></span>
  </button>
</template>
