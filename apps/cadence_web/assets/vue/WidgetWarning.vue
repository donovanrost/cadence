<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"

type Attrs = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type FieldPresentation = {
  key: string
  label: TextPresentation
  value: TextPresentation
}

type WidgetWarningPresentation = {
  component_id: string
  overlay: {id: string; class: string; attrs: Attrs}
  trigger: {
    id: string
    type: string
    class: string
    attrs: Attrs
    badge: {class: string; attrs: Attrs; text: string}
  }
  panel: {id: string; class: string; hidden: boolean; attrs: Attrs}
  body: {
    class: string
    heading: TextPresentation
    message: TextPresentation
    evidence_button: {
      type: string
      class: string
      attrs: Attrs
      icon: {name: string; class: string}
      text: string
    }
    details: {
      visible: boolean
      class: string
      rows: Array<{
        key: string
        label: TextPresentation
        value: TextPresentation & {attrs: Attrs}
      }>
    }
    evidence: {
      visible: boolean
      class: string
      attrs: Attrs
      heading: TextPresentation
      rows: Array<{key: string; class: string; attrs: Attrs; fields: FieldPresentation[]}>
    }
    links: {
      visible: boolean
      class: string
      attrs: Attrs
      heading: TextPresentation
      rows: Array<{
        key: string
        type: string
        class: string
        attrs: Attrs
        fields: FieldPresentation[]
      }>
    }
  }
}

defineProps<{presentation: WidgetWarningPresentation}>()
const root = ref<HTMLElement | null>(null)

// WIDGET_WARNING_CONTROLLER_START
const createWidgetWarningController = ({rootElement, documentObject, windowObject}) => {
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

  const sync = () => {
    state.rootElement.toggleAttribute("data-overlay-open", state.open)
    if (!state.trigger || !state.panel) return
    state.trigger.setAttribute("aria-expanded", state.open ? "true" : "false")
    state.panel.hidden = !state.open
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
    state.preservedOverlayIdentity = state.open ? state.rootElement.id : null
    teardown()
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
    unbindElementListeners()
    windowObject.removeEventListener("cadence:overlay-opened", onOverlayOpened)
  }

  return {state, mounted, beforeUpdate, updated, destroyed, show, close, sync, positionPanel}
}
// WIDGET_WARNING_CONTROLLER_END

let controller = null

onMounted(() => {
  if (!root.value) return
  controller = createWidgetWarningController({
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
        :class="presentation.trigger.badge.class"
        v-bind="presentation.trigger.badge.attrs"
      >{{ presentation.trigger.badge.text }}</span>
    </button>
    <section
      :id="presentation.panel.id"
      :class="presentation.panel.class"
      :hidden="presentation.panel.hidden"
      v-bind="presentation.panel.attrs"
    >
      <div :class="presentation.body.class">
        <div :class="presentation.body.heading.class">
          {{ presentation.body.heading.text }}
        </div>
        <p :class="presentation.body.message.class">
          {{ presentation.body.message.text }}
        </p>
        <button
          :type="presentation.body.evidence_button.type"
          :class="presentation.body.evidence_button.class"
          v-bind="presentation.body.evidence_button.attrs"
        >
          <span
            :class="[
              presentation.body.evidence_button.icon.name,
              presentation.body.evidence_button.icon.class,
            ]"
          ></span>
          {{ presentation.body.evidence_button.text }}
        </button>
        <dl
          v-if="presentation.body.details.visible"
          :class="presentation.body.details.class"
        >
          <template v-for="row in presentation.body.details.rows" :key="row.key">
            <dt :class="row.label.class">{{ row.label.text }}</dt>
            <dd :class="row.value.class" v-bind="row.value.attrs">
              {{ row.value.text }}
            </dd>
          </template>
        </dl>
        <div
          v-if="presentation.body.evidence.visible"
          :class="presentation.body.evidence.class"
          v-bind="presentation.body.evidence.attrs"
        >
          <div :class="presentation.body.evidence.heading.class">
            {{ presentation.body.evidence.heading.text }}
          </div>
          <div
            v-for="row in presentation.body.evidence.rows"
            :key="row.key"
            :class="row.class"
            v-bind="row.attrs"
          >
            <template v-for="field in row.fields" :key="field.key">
              <span :class="field.label.class">{{ field.label.text }}</span>
              <span :class="field.value.class">{{ field.value.text }}</span>
            </template>
          </div>
        </div>
        <div
          v-if="presentation.body.links.visible"
          :class="presentation.body.links.class"
          v-bind="presentation.body.links.attrs"
        >
          <div :class="presentation.body.links.heading.class">
            {{ presentation.body.links.heading.text }}
          </div>
          <button
            v-for="row in presentation.body.links.rows"
            :key="row.key"
            :type="row.type"
            :class="row.class"
            v-bind="row.attrs"
          >
            <template v-for="field in row.fields" :key="field.key">
              <span :class="field.label.class">{{ field.label.text }}</span>
              <span :class="field.value.class">{{ field.value.text }}</span>
            </template>
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
