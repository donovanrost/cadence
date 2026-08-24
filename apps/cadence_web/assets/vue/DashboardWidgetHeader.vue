<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"
import WidgetDataLinks from "./WidgetDataLinks.vue"
import WidgetQueryDiagnostics from "./WidgetQueryDiagnostics.vue"
import WidgetWarning from "./WidgetWarning.vue"

type Attrs = Record<string, string>
type Classes = string | string[]

type IconPresentation = {
  name: string
  class: string
}

type BadgePresentation = {
  class: Classes
  text: string
}

type ButtonPresentation = {
  key?: string
  type: string
  class: string
  attrs: Attrs
  icon: IconPresentation
}

type ChildPresentation = {
  component_id: string
  [key: string]: unknown
}

type SourceBadgePresentation = {
  wrapper: {tag: string; class: string} | null
  badge: {
    tag: string
    class: string
    attrs: Attrs
    icon: IconPresentation
    text: string
  }
  inventory_link: {
    tag: string
    class: string
    attrs: Attrs
    icon: IconPresentation
  } | null
}

type DashboardWidgetHeaderPresentation = {
  component_id: string
  root: {class: Classes; attrs: Attrs}
  title: {class: Classes; text: string}
  status_indicators: {
    class: string
    attrs: Attrs
    limit: {
      class: Classes
      dot_class: string
      label_class: string
      text: string
    } | null
    comparison: ({attrs: Attrs} & BadgePresentation) | null
    quality: BadgePresentation | null
    lifecycle: {
      class: Classes
      attrs: Attrs
      icon: IconPresentation
    } | null
  }
  actions: {
    class: Classes
    details: {
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
        heading: {
          class: string
          title: {class: string; text: string}
          binding: {class: string; text: string}
        }
        indicators: {
          class: string
          attrs: Attrs
          lifecycle: BadgePresentation | null
          source: SourceBadgePresentation | null
          data_management: Array<{tag: string; class: string; attrs: Attrs; text: string}>
          warnings: ChildPresentation[]
        }
        actions: {
          class: string
          attrs: Attrs
          query: ChildPresentation | null
          frame_evidence: ButtonPresentation | null
          data_links: ChildPresentation | null
          inspector: ButtonPresentation | null
        }
      }
    }
    edit: ButtonPresentation[]
  }
}

const props = defineProps<{presentation: DashboardWidgetHeaderPresentation}>()
const detailsRoot = ref<HTMLElement | null>(null)

// DASHBOARD_WIDGET_HEADER_CONTROLLER_START
const createDashboardWidgetHeaderController = ({rootElement, documentObject, windowObject}) => {
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
// DASHBOARD_WIDGET_HEADER_CONTROLLER_END

let controller = null

onMounted(() => {
  if (!detailsRoot.value) return
  controller = createDashboardWidgetHeaderController({
    rootElement: detailsRoot.value,
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
  <div :class="props.presentation.root.class" v-bind="props.presentation.root.attrs">
    <h3 :class="props.presentation.title.class">{{ props.presentation.title.text }}</h3>
    <div
      :class="props.presentation.status_indicators.class"
      v-bind="props.presentation.status_indicators.attrs"
    >
      <span
        v-if="props.presentation.status_indicators.limit"
        :class="props.presentation.status_indicators.limit.class"
      >
        <span :class="props.presentation.status_indicators.limit.dot_class"></span>
        <span :class="props.presentation.status_indicators.limit.label_class">
          {{ props.presentation.status_indicators.limit.text }}
        </span>
      </span>
      <span
        v-if="props.presentation.status_indicators.comparison"
        :class="props.presentation.status_indicators.comparison.class"
        v-bind="props.presentation.status_indicators.comparison.attrs"
      >
        {{ props.presentation.status_indicators.comparison.text }}
      </span>
      <span
        v-if="props.presentation.status_indicators.quality"
        :class="props.presentation.status_indicators.quality.class"
      >
        {{ props.presentation.status_indicators.quality.text }}
      </span>
      <span
        v-if="props.presentation.status_indicators.lifecycle"
        :class="props.presentation.status_indicators.lifecycle.class"
        v-bind="props.presentation.status_indicators.lifecycle.attrs"
      >
        <span
          :class="[
            props.presentation.status_indicators.lifecycle.icon.name,
            props.presentation.status_indicators.lifecycle.icon.class,
          ]"
        ></span>
      </span>
    </div>
    <div :class="props.presentation.actions.class">
      <div
        :id="props.presentation.actions.details.overlay.id"
        ref="detailsRoot"
        :class="props.presentation.actions.details.overlay.class"
        v-bind="props.presentation.actions.details.overlay.attrs"
      >
        <button
          :id="props.presentation.actions.details.trigger.id"
          :type="props.presentation.actions.details.trigger.type"
          :class="props.presentation.actions.details.trigger.class"
          v-bind="props.presentation.actions.details.trigger.attrs"
        >
          <span
            :class="props.presentation.actions.details.trigger.content.class"
            v-bind="props.presentation.actions.details.trigger.content.attrs"
          >
            <span
              :class="[
                props.presentation.actions.details.trigger.content.icon.name,
                props.presentation.actions.details.trigger.content.icon.class,
              ]"
            ></span>
          </span>
        </button>
        <section
          :id="props.presentation.actions.details.panel.id"
          :class="props.presentation.actions.details.panel.class"
          :hidden="props.presentation.actions.details.panel.hidden"
          v-bind="props.presentation.actions.details.panel.attrs"
        >
          <div :class="props.presentation.actions.details.body.class">
            <div :class="props.presentation.actions.details.body.heading.class">
              <p :class="props.presentation.actions.details.body.heading.title.class">
                {{ props.presentation.actions.details.body.heading.title.text }}
              </p>
              <p :class="props.presentation.actions.details.body.heading.binding.class">
                {{ props.presentation.actions.details.body.heading.binding.text }}
              </p>
            </div>
            <div
              :class="props.presentation.actions.details.body.indicators.class"
              v-bind="props.presentation.actions.details.body.indicators.attrs"
            >
              <span
                v-if="props.presentation.actions.details.body.indicators.lifecycle"
                :class="props.presentation.actions.details.body.indicators.lifecycle.class"
              >
                {{ props.presentation.actions.details.body.indicators.lifecycle.text }}
              </span>
              <component
                :is="props.presentation.actions.details.body.indicators.source.wrapper.tag"
                v-if="props.presentation.actions.details.body.indicators.source?.wrapper"
                :class="props.presentation.actions.details.body.indicators.source.wrapper.class"
              >
                <component
                  :is="props.presentation.actions.details.body.indicators.source.badge.tag"
                  :class="props.presentation.actions.details.body.indicators.source.badge.class"
                  v-bind="props.presentation.actions.details.body.indicators.source.badge.attrs"
                >
                  <span
                    :class="[
                      props.presentation.actions.details.body.indicators.source.badge.icon.name,
                      props.presentation.actions.details.body.indicators.source.badge.icon.class,
                    ]"
                  ></span>
                  <span>{{ props.presentation.actions.details.body.indicators.source.badge.text }}</span>
                </component>
                <a
                  v-if="props.presentation.actions.details.body.indicators.source.inventory_link"
                  :class="props.presentation.actions.details.body.indicators.source.inventory_link.class"
                  v-bind="props.presentation.actions.details.body.indicators.source.inventory_link.attrs"
                >
                  <span
                    :class="[
                      props.presentation.actions.details.body.indicators.source.inventory_link.icon.name,
                      props.presentation.actions.details.body.indicators.source.inventory_link.icon.class,
                    ]"
                  ></span>
                </a>
              </component>
              <component
                :is="props.presentation.actions.details.body.indicators.source.badge.tag"
                v-else-if="props.presentation.actions.details.body.indicators.source"
                :class="props.presentation.actions.details.body.indicators.source.badge.class"
                v-bind="props.presentation.actions.details.body.indicators.source.badge.attrs"
              >
                <span
                  :class="[
                    props.presentation.actions.details.body.indicators.source.badge.icon.name,
                    props.presentation.actions.details.body.indicators.source.badge.icon.class,
                  ]"
                ></span>
                <span>{{ props.presentation.actions.details.body.indicators.source.badge.text }}</span>
              </component>
              <component
                :is="badge.tag"
                v-for="(badge, index) in props.presentation.actions.details.body.indicators.data_management"
                :key="`data-management-${index}`"
                :class="badge.class"
                v-bind="badge.attrs"
              >
                {{ badge.text }}
              </component>
              <div
                v-for="warning in props.presentation.actions.details.body.indicators.warnings"
                :id="warning.component_id"
                :key="warning.component_id"
                class="contents"
              >
                <WidgetWarning :presentation="warning" />
              </div>
            </div>
            <div
              :class="props.presentation.actions.details.body.actions.class"
              v-bind="props.presentation.actions.details.body.actions.attrs"
            >
              <div
                v-if="props.presentation.actions.details.body.actions.query"
                :id="props.presentation.actions.details.body.actions.query.component_id"
                class="contents"
              >
                <WidgetQueryDiagnostics
                  :presentation="props.presentation.actions.details.body.actions.query"
                />
              </div>
              <button
                v-if="props.presentation.actions.details.body.actions.frame_evidence"
                :type="props.presentation.actions.details.body.actions.frame_evidence.type"
                :class="props.presentation.actions.details.body.actions.frame_evidence.class"
                v-bind="props.presentation.actions.details.body.actions.frame_evidence.attrs"
              >
                <span
                  :class="[
                    props.presentation.actions.details.body.actions.frame_evidence.icon.name,
                    props.presentation.actions.details.body.actions.frame_evidence.icon.class,
                  ]"
                ></span>
              </button>
              <div
                v-if="props.presentation.actions.details.body.actions.data_links"
                :id="props.presentation.actions.details.body.actions.data_links.component_id"
                class="contents"
              >
                <WidgetDataLinks
                  :presentation="props.presentation.actions.details.body.actions.data_links"
                />
              </div>
              <button
                v-if="props.presentation.actions.details.body.actions.inspector"
                :type="props.presentation.actions.details.body.actions.inspector.type"
                :class="props.presentation.actions.details.body.actions.inspector.class"
                v-bind="props.presentation.actions.details.body.actions.inspector.attrs"
              >
                <span
                  :class="[
                    props.presentation.actions.details.body.actions.inspector.icon.name,
                    props.presentation.actions.details.body.actions.inspector.icon.class,
                  ]"
                ></span>
              </button>
            </div>
          </div>
        </section>
      </div>
      <button
        v-for="action in props.presentation.actions.edit"
        :key="action.key"
        :type="action.type"
        :class="action.class"
        v-bind="action.attrs"
      >
        <span :class="[action.icon.name, action.icon.class]"></span>
      </button>
    </div>
  </div>
</template>
