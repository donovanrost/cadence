<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"

type Attrs = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type IconPresentation = {
  name: string
  class: string
}

type DetailRowPresentation = {
  key: string
  order: number
  label: TextPresentation
  value: TextPresentation & {attrs: Attrs}
}

type SourcePresentation = {
  key: string
  order: number
  overlay: {
    id: string
    label: string
    class: string
    placement: string
    width: string
    attrs: Attrs
  }
  trigger: {
    id: string
    type: string
    class: string
    attrs: Attrs
  }
  badge: TextPresentation & {attrs: Attrs}
  panel: {
    id: string
    class: string
    hidden: boolean
    width: string
    attrs: Attrs
  }
  details: {
    class: string
    heading: TextPresentation
    prose: TextPresentation
    circuit: TextPresentation & {visible: boolean}
    evidence: {
      type: string
      class: string
      attrs: Attrs
      icon: IconPresentation
      label: string
    }
    rows_class: string
    rows: DetailRowPresentation[]
  }
}

type SourceHealthPresentation = {
  root: {
    id: string
    class: string
    attrs: Attrs
  }
  label: TextPresentation
  sources: SourcePresentation[]
}

defineProps<{presentation: SourceHealthPresentation}>()
const root = ref<HTMLElement | null>(null)

// SOURCE_HEALTH_CONTROLLER_START
const createSourceHealthController = ({rootElement, documentObject, windowObject}) => {
  const state = {
    rootElement,
    overlays: [],
    openIndex: null,
    wasOpen: null,
  }

  const bindElements = () => {
    state.overlays = Array.from(
      state.rootElement.querySelectorAll(":scope > [data-overlay-kind='popover']"),
    )
  }

  const overlayParts = (overlay) => ({
    trigger: overlay?.querySelector(":scope > [data-overlay-trigger]") || null,
    panel: overlay?.querySelector(":scope > [data-overlay-panel]") || null,
  })

  const activeOverlay = () =>
    state.openIndex === null ? null : state.overlays[state.openIndex] || null

  const teardown = () => {
    documentObject.removeEventListener("pointerdown", onDocumentPointerDown)
    documentObject.removeEventListener("keydown", onDocumentKeyDown)
  }

  const bindDocumentListeners = () => {
    documentObject.addEventListener("pointerdown", onDocumentPointerDown)
    documentObject.addEventListener("keydown", onDocumentKeyDown)
  }

  const sync = () => {
    for (const overlay of state.overlays) {
      const {trigger, panel} = overlayParts(overlay)
      if (!trigger || !panel) continue

      const open = overlay === activeOverlay()
      trigger.setAttribute("aria-expanded", open ? "true" : "false")
      panel.hidden = !open
      overlay.toggleAttribute("data-overlay-open", open)
    }
  }

  const positionPanel = (overlay = activeOverlay()) => {
    const {panel} = overlayParts(overlay)
    if (!panel) return

    panel.style.transform = ""
    const rect = panel.getBoundingClientRect()
    const gutter = 16
    let offset = 0
    if (rect.left < gutter) offset = gutter - rect.left
    if (rect.right + offset > windowObject.innerWidth - gutter) {
      offset -= rect.right + offset - (windowObject.innerWidth - gutter)
    }
    if (offset) panel.style.transform = `translateX(${Math.round(offset)}px)`
  }

  const close = ({restoreFocus = true} = {}) => {
    const overlay = activeOverlay()
    if (!overlay) return

    const {trigger} = overlayParts(overlay)
    state.openIndex = null
    sync()
    teardown()
    if (restoreFocus && trigger?.isConnected) trigger.focus()
  }

  const show = (overlay) => {
    windowObject.dispatchEvent(
      new windowObject.CustomEvent("cadence:overlay-opened", {detail: overlay}),
    )
    state.openIndex = state.overlays.indexOf(overlay)
    sync()
    positionPanel(overlay)
    bindDocumentListeners()
  }

  const onRootClick = (event) => {
    const trigger = event.target?.closest?.("[data-overlay-trigger]")
    if (!trigger) return

    const overlay = trigger.closest("[data-overlay-kind='popover']")
    if (!overlay || !state.rootElement.contains(overlay)) return

    event.preventDefault()
    activeOverlay() === overlay ? close() : show(overlay)
  }

  function onDocumentPointerDown(event) {
    const overlay = activeOverlay()
    if (overlay && !overlay.contains(event.target)) close({restoreFocus: false})
  }

  function onDocumentKeyDown(event) {
    if (event.key !== "Escape" || !activeOverlay()) return
    event.preventDefault()
    close()
  }

  const onOverlayOpened = (event) => {
    const overlay = activeOverlay()
    if (overlay && event.detail !== overlay) close({restoreFocus: false})
  }

  const mounted = () => {
    bindElements()
    sync()
    state.rootElement.addEventListener("click", onRootClick)
    windowObject.addEventListener("cadence:overlay-opened", onOverlayOpened)
  }

  const beforeUpdate = () => {
    const overlay = activeOverlay()

    state.wasOpen = overlay
      ? {
          id: overlay.id,
          occurrence:
            state.overlays
              .slice(0, state.openIndex + 1)
              .filter((candidate) => candidate.id === overlay.id).length - 1,
        }
      : null
    teardown()
  }

  const updated = () => {
    bindElements()

    const preservedOverlay = state.wasOpen
      ? state.overlays.filter((overlay) => overlay.id === state.wasOpen.id)[
          state.wasOpen.occurrence
        ] || null
      : null

    state.openIndex = preservedOverlay ? state.overlays.indexOf(preservedOverlay) : null

    const overlay = activeOverlay()
    const {trigger, panel} = overlayParts(overlay)
    if (!overlay || !trigger || !panel) state.openIndex = null

    sync()
    if (state.openIndex !== null) {
      positionPanel()
      bindDocumentListeners()
    }
    state.wasOpen = null
  }

  const destroyed = () => {
    teardown()
    state.rootElement.removeEventListener("click", onRootClick)
    windowObject.removeEventListener("cadence:overlay-opened", onOverlayOpened)
  }

  return {state, mounted, beforeUpdate, updated, destroyed, show, close, sync, positionPanel}
}
// SOURCE_HEALTH_CONTROLLER_END

let controller = null

onMounted(() => {
  if (!root.value) return
  controller = createSourceHealthController({
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
    :id="presentation.root.id"
    ref="root"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <span :class="presentation.label.class">{{ presentation.label.text }}</span>
    <div
      v-for="source in presentation.sources"
      :id="source.overlay.id"
      :key="source.key"
      :class="source.overlay.class"
      v-bind="source.overlay.attrs"
    >
      <button
        :id="source.trigger.id"
        :type="source.trigger.type"
        :class="source.trigger.class"
        v-bind="source.trigger.attrs"
      >
        <span :class="source.badge.class" v-bind="source.badge.attrs">
          {{ source.badge.text }}
        </span>
      </button>
      <section
        :id="source.panel.id"
        :class="source.panel.class"
        :hidden="source.panel.hidden"
        v-bind="source.panel.attrs"
      >
        <div :class="source.details.class">
          <div :class="source.details.heading.class">
            {{ source.details.heading.text }}
          </div>
          <p :class="source.details.prose.class">{{ source.details.prose.text }}</p>
          <p v-if="source.details.circuit.visible" :class="source.details.circuit.class">
            {{ source.details.circuit.text }}
          </p>
          <button
            :type="source.details.evidence.type"
            :class="source.details.evidence.class"
            v-bind="source.details.evidence.attrs"
          >
            <span
              :class="[
                source.details.evidence.icon.name,
                source.details.evidence.icon.class,
              ]"
            ></span>
            {{ source.details.evidence.label }}
          </button>
          <dl :class="source.details.rows_class">
            <template v-for="row in source.details.rows" :key="row.key">
              <dt :class="row.label.class">{{ row.label.text }}</dt>
              <dd :class="row.value.class" v-bind="row.value.attrs">
                {{ row.value.text }}
              </dd>
            </template>
          </dl>
        </div>
      </section>
    </div>
  </div>
</template>
