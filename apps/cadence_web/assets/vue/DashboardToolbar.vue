<script setup lang="ts">
import {onBeforeUnmount, onBeforeUpdate, onMounted, onUpdated, ref} from "vue"

import DashboardComparisonToggle from "./DashboardComparisonToggle.vue"
import DashboardEditorActions from "./DashboardEditorActions.vue"
import DashboardRuntimeContextSelector from "./DashboardRuntimeContextSelector.vue"
import DashboardRuntimeControls from "./DashboardRuntimeControls.vue"
import DashboardTimePicker from "./DashboardTimePicker.vue"
import DashboardToolbarMenu from "./DashboardToolbarMenu.vue"
import WidgetWarning from "./WidgetWarning.vue"

type ToolbarPresentation = Record<string, any>

const props = defineProps<{presentation: ToolbarPresentation}>()
const emit = defineEmits(["recents-loaded", "select-range"])
const scopePopover = ref<HTMLElement | null>(null)
const dataHealthPopover = ref<HTMLElement | null>(null)

const forwardRecentsLoaded = (payload: unknown) => emit("recents-loaded", payload)
const forwardSelectRange = (payload: unknown) => emit("select-range", payload)

// DASHBOARD_TOOLBAR_POPOVER_CONTROLLER_START
const createDashboardToolbarPopoverController = ({rootElement, documentObject, windowObject}) => {
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
// DASHBOARD_TOOLBAR_POPOVER_CONTROLLER_END

const controllers = new Map<string, any>()

const currentPopoverRoots = () =>
  [scopePopover.value, dataHealthPopover.value].filter(
    (rootElement): rootElement is HTMLElement => Boolean(rootElement),
  )

const mountPopoverControllers = () => {
  for (const rootElement of currentPopoverRoots()) {
    const controller = createDashboardToolbarPopoverController({
      rootElement,
      documentObject: document,
      windowObject: window,
    })
    controller.mounted()
    controllers.set(rootElement.id, controller)
  }
}

const updatePopoverControllers = () => {
  const roots = currentPopoverRoots()
  const activeIds = new Set(roots.map((rootElement) => rootElement.id))

  for (const [id, controller] of controllers) {
    if (!activeIds.has(id)) {
      controller.destroyed()
      controllers.delete(id)
    }
  }

  for (const rootElement of roots) {
    const controller = controllers.get(rootElement.id)
    if (controller) {
      controller.updated(rootElement)
    } else {
      const nextController = createDashboardToolbarPopoverController({
        rootElement,
        documentObject: document,
        windowObject: window,
      })
      nextController.mounted()
      controllers.set(rootElement.id, nextController)
    }
  }
}

onMounted(mountPopoverControllers)
onBeforeUpdate(() => controllers.forEach((controller) => controller.beforeUpdate()))
onUpdated(updatePopoverControllers)
onBeforeUnmount(() => {
  controllers.forEach((controller) => controller.destroyed())
  controllers.clear()
})
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <div :class="props.presentation.title.wrapper_class">
      <h1 v-bind="props.presentation.title.attrs">{{ props.presentation.title.text }}</h1>
    </div>

    <div v-if="props.presentation.viewer" v-bind="props.presentation.viewer.root.attrs">
      <div
        v-bind="props.presentation.viewer.operational_scope.root.attrs"
        ref="scopePopover"
      >
        <button v-bind="props.presentation.viewer.operational_scope.trigger.attrs">
          <span :class="props.presentation.viewer.operational_scope.trigger.label.class">
            {{ props.presentation.viewer.operational_scope.trigger.label.text }}
          </span>
          <span :class="props.presentation.viewer.operational_scope.trigger.value.class">
            {{ props.presentation.viewer.operational_scope.trigger.value.text }}
          </span>
          <span
            v-if="props.presentation.viewer.operational_scope.trigger.override"
            v-bind="props.presentation.viewer.operational_scope.trigger.override.attrs"
          >{{ props.presentation.viewer.operational_scope.trigger.override.text }}</span>
          <span :class="props.presentation.viewer.operational_scope.trigger.icon_class"></span>
        </button>

        <section v-bind="props.presentation.viewer.operational_scope.panel.attrs">
          <div :class="props.presentation.viewer.operational_scope.panel.header.class">
            <span :class="props.presentation.viewer.operational_scope.panel.header.icon_class"></span>
            <div>
              <p :class="props.presentation.viewer.operational_scope.panel.header.title.class">
                {{ props.presentation.viewer.operational_scope.panel.header.title.text }}
              </p>
              <p :class="props.presentation.viewer.operational_scope.panel.header.description.class">
                {{ props.presentation.viewer.operational_scope.panel.header.description.text }}
              </p>
            </div>
          </div>
          <div :class="props.presentation.viewer.operational_scope.panel.body.class">
            <div
              v-if="props.presentation.viewer.operational_scope.panel.body.context"
              v-bind="props.presentation.viewer.operational_scope.panel.body.context_host.attrs"
            >
              <DashboardRuntimeContextSelector
                :presentation="props.presentation.viewer.operational_scope.panel.body.context"
              />
            </div>

            <details v-bind="props.presentation.viewer.operational_scope.panel.body.query_options.attrs">
              <summary
                v-bind="props.presentation.viewer.operational_scope.panel.body.query_options.summary.attrs"
              >
                <span
                  :class="props.presentation.viewer.operational_scope.panel.body.query_options.summary.leading_class"
                >
                  <span
                    :class="props.presentation.viewer.operational_scope.panel.body.query_options.summary.icon_class"
                  ></span>
                  <span
                    :class="props.presentation.viewer.operational_scope.panel.body.query_options.summary.copy_class"
                  >
                    <span
                      :class="props.presentation.viewer.operational_scope.panel.body.query_options.summary.title.class"
                    >{{ props.presentation.viewer.operational_scope.panel.body.query_options.summary.title.text }}</span>
                    <span
                      :class="props.presentation.viewer.operational_scope.panel.body.query_options.summary.description.class"
                    >{{ props.presentation.viewer.operational_scope.panel.body.query_options.summary.description.text }}</span>
                  </span>
                </span>
                <span
                  :class="props.presentation.viewer.operational_scope.panel.body.query_options.summary.chevron_class"
                ></span>
              </summary>
              <div
                v-bind="props.presentation.viewer.operational_scope.panel.body.query_options.panel.attrs"
              >
                <div
                  v-bind="props.presentation.viewer.operational_scope.panel.body.query_options.panel.runtime_controls_host.attrs"
                >
                  <DashboardRuntimeControls
                    :runtime_controls="props.presentation.viewer.operational_scope.panel.body.query_options.panel.runtime_controls"
                  />
                </div>
              </div>
            </details>
          </div>
        </section>
      </div>

      <div v-bind="props.presentation.viewer.time_picker_host.attrs">
        <DashboardTimePicker
          :presentation="props.presentation.viewer.time_picker"
          @recents-loaded="forwardRecentsLoaded"
          @select-range="forwardSelectRange"
        />
      </div>
    </div>

    <div
      v-if="props.presentation.comparison_toggle"
      id="dashboard-comparison-toggle-component"
      class="contents"
    >
      <DashboardComparisonToggle :presentation="props.presentation.comparison_toggle" />
    </div>

    <div
      v-if="props.presentation.data_health"
      v-bind="props.presentation.data_health.root.attrs"
      ref="dataHealthPopover"
    >
      <button v-bind="props.presentation.data_health.trigger.attrs">
        <span v-bind="props.presentation.data_health.trigger.badge.attrs">
          <span :class="props.presentation.data_health.trigger.badge.icon_class"></span>
          <span>{{ props.presentation.data_health.trigger.badge.count }}</span>
          <span class="hidden sm:inline">{{ props.presentation.data_health.trigger.badge.label }}</span>
        </span>
      </button>
      <section v-bind="props.presentation.data_health.panel.attrs">
        <div :class="props.presentation.data_health.panel.body.class">
          <div :class="props.presentation.data_health.panel.body.header.class">
            <span :class="props.presentation.data_health.panel.body.header.icon_class"></span>
            <div :class="props.presentation.data_health.panel.body.header.copy_class">
              <p :class="props.presentation.data_health.panel.body.header.title.class">
                {{ props.presentation.data_health.panel.body.header.title.text }}
              </p>
              <p :class="props.presentation.data_health.panel.body.header.summary.class">
                {{ props.presentation.data_health.panel.body.header.summary.text }}
              </p>
            </div>
          </div>
          <div
            v-if="props.presentation.data_health.panel.body.warnings.length"
            :class="props.presentation.data_health.panel.body.warnings_class"
          >
            <div
              v-for="warning in props.presentation.data_health.panel.body.warnings"
              :key="warning.component_id"
              :id="warning.component_id"
              class="contents"
            >
              <WidgetWarning :presentation="warning" />
            </div>
          </div>
          <p
            v-if="props.presentation.data_health.panel.body.degraded_message"
            :class="props.presentation.data_health.panel.body.degraded_message.class"
          >{{ props.presentation.data_health.panel.body.degraded_message.text }}</p>
          <a v-bind="props.presentation.data_health.panel.body.action.attrs">
            <span :class="props.presentation.data_health.panel.body.action.icon_class"></span>
            {{ props.presentation.data_health.panel.body.action.text }}
          </a>
          <a
            v-if="props.presentation.data_health.panel.body.diagnostics_action"
            v-bind="props.presentation.data_health.panel.body.diagnostics_action.attrs"
          >
            <span :class="props.presentation.data_health.panel.body.diagnostics_action.icon_class"></span>
            {{ props.presentation.data_health.panel.body.diagnostics_action.text }}
          </a>
        </div>
      </section>
    </div>

    <div
      v-if="props.presentation.editor_actions"
      id="dashboard-editor-actions-component"
      class="contents"
    >
      <DashboardEditorActions :presentation="props.presentation.editor_actions" />
    </div>

    <DashboardToolbarMenu :presentation="props.presentation.menu" />
  </div>
</template>
