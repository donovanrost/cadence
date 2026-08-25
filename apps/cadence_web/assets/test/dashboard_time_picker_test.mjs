import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  CADENCE_OVERLAY_OPENED_EVENT,
  announceCadencePopoverOpened,
  focusCurrentPopoverTrigger,
  preservesPopoverOpenState,
  subscribeToLegacyOverlayOpen,
} from "../vue/ui/reka/popover_compatibility.js"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/DashboardTimePicker.vue")
const adapterPath = resolve(testDirectory, "../vue/ui/reka/CadencePopover.vue")
const overlayStylesPath = resolve(testDirectory, "../css/components/overlay.css")
const absoluteRangePath = resolve(testDirectory, "../vue/DashboardAbsoluteRangePane.vue")
const quickRangesPath = resolve(testDirectory, "../vue/DashboardQuickRangeList.vue")
const toolbarPath = resolve(testDirectory, "../vue/DashboardToolbar.vue")
const viewportSmokePath = resolve(testDirectory, "dashboard_viewport_smoke.mjs")
const presenterPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_time_picker_components.ex",
)

const [
  componentSource,
  adapterSource,
  overlayStylesSource,
  absoluteRangeSource,
  quickRangesSource,
  toolbarSource,
  viewportSmokeSource,
  presenterSource,
] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(adapterPath, "utf8"),
  readFile(overlayStylesPath, "utf8"),
  readFile(absoluteRangePath, "utf8"),
  readFile(quickRangesPath, "utf8"),
  readFile(toolbarPath, "utf8"),
  readFile(viewportSmokePath, "utf8"),
  readFile(presenterPath, "utf8"),
])

const componentTemplate = componentSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(componentTemplate, "DashboardTimePicker.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

// Phoenix owns the public DOM and event contracts; the island only binds the presentation.
assert.match(componentSource, /import \{computed\} from "vue"/)
assert.match(componentSource, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.match(componentSource, /from "\.\/DashboardAbsoluteRangePane\.vue"/)
assert.match(componentSource, /from "\.\/DashboardQuickRangeList\.vue"/)
assert.match(componentSource, /from "\.\/DashboardTimeReplay\.vue"/)
assert.match(componentSource, /from "\.\/DashboardSelectedDatumActions\.vue"/)
assert.match(
  componentSource,
  /const identity = props\.presentation\.overlay\.root\.attrs\.id\n  return typeof identity === "string" \? identity : null/,
)
assert.match(
  componentSource,
  /const attrs = \{\.\.\.props\.presentation\.overlay\.panel\.attrs\}\n  delete attrs\.hidden/,
)
assert.match(componentTemplate, /<CadencePopover/)
assert.match(componentTemplate, /:identity="overlayIdentity"/)
assert.match(componentTemplate, /side="bottom"/)
assert.match(componentTemplate, /align="end"/)
assert.match(componentTemplate, /:collision-padding="16"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.overlay\.root\.attrs"/)
assert.match(componentTemplate, /<template #trigger="\{open\}">/)
assert.match(componentTemplate, /v-bind="props\.presentation\.overlay\.trigger\.attrs"/)
assert.match(componentTemplate, /:aria-expanded="String\(open\)"/)
assert.match(componentTemplate, /<template #content="\{open\}">/)
assert.match(componentTemplate, /v-bind="panelAttrs"[\s\S]*:hidden="!open"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.overlay\.panel\.body\.controls\.attrs"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.shift_back\.attrs"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.shift_forward\.attrs"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.zoom_out\.attrs"/)

// Every nested control keeps its server-provided attrs and the two public child emissions.
assert.match(componentSource, /defineEmits\(\["recents-loaded", "select-range"\]\)/)
assert.match(componentTemplate, /v-bind="props\.presentation\.time_picker\.absolute_range_host\.attrs"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.time_picker\.absolute_range"/)
assert.match(componentTemplate, /@recents-loaded="forwardRecentsLoaded"/)
assert.match(componentTemplate, /@select-range="forwardSelectRange"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.time_picker\.quick_ranges_host\.attrs"/)
assert.match(componentTemplate, /:presentation="props\.presentation\.time_picker\.quick_ranges"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.replay_host\.attrs"/)
assert.match(componentTemplate, /:presentation="props\.presentation\.replay"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.selected_datum_host\.attrs"/)
assert.match(componentTemplate, /:presentation="props\.presentation\.selected_datum"/)
assert.match(absoluteRangeSource, /defineEmits\(\["recents-loaded", "select-range"\]\)/)
assert.match(absoluteRangeSource, /<form v-bind="props\.form\.attrs">/)
assert.match(absoluteRangeSource, /<button v-bind="props\.form\.submit\.attrs">/)
assert.match(absoluteRangeSource, /@recents-loaded="forwardRecentsLoaded"/)
assert.match(absoluteRangeSource, /@select-range="forwardSelectRange"/)
assert.match(quickRangesSource, /<form v-bind="presentation\.search\.form\.attrs">/)
assert.match(quickRangesSource, /<input v-bind="presentation\.search\.field\.attrs"/)
assert.match(quickRangesSource, /<button v-bind="item\.attrs">/)
assert.match(
  toolbarSource,
  /<DashboardTimePicker[\s\S]*@recents-loaded="forwardRecentsLoaded"[\s\S]*@select-range="forwardSelectRange"/,
)

const requiredPresenterContracts = [
  'id: "dashboard-time-controls"',
  'id: "dashboard-time-controls-toggle"',
  'id: "dashboard-time-controls-panel"',
  '"data-overlay-placement": "bottom-end"',
  '"aria-haspopup": "dialog"',
  '"aria-controls": "dashboard-time-controls-panel"',
  '"phx-submit": "set_chart_time_range"',
  '"phx-click": "set_time_preset"',
  '"phx-click": "shift_time_range"',
  '"phx-click": "zoom_out_time_range"',
  '"phx-change": "time_quick_search"',
  'v-on:recents-loaded={JS.push("time_recents_loaded")}',
  'v-on:select-range={JS.push("set_chart_time_range")}',
]

for (const contract of requiredPresenterContracts) {
  assert.ok(presenterSource.includes(contract), `missing server-owned time picker contract: ${contract}`)
}

assert.doesNotMatch(
  componentSource,
  /dashboard-time-controls|set_chart_time_range|set_time_preset|shift_time_range|zoom_out_time_range|time_quick_search/,
)
assert.doesNotMatch(componentSource, /cadence:overlay-opened|addEventListener|removeEventListener/)
assert.doesNotMatch(
  componentSource,
  /createDashboardTimePickerController|onBeforeUpdate|onUpdated|onMounted|onBeforeUnmount/,
)
assert.doesNotMatch(componentSource, /phx-hook|hooks\/overlay|\bOverlay\b/)
assert.doesNotMatch(componentSource, /setTimeout|setInterval/)
assert.doesNotMatch(componentSource, /<script(?! setup)/)
assert.doesNotMatch(componentTemplate, /@click="[^"]*(?:close|toggle)/)

// The shared adapter supplies non-modal Reka popover behavior and the legacy bridge.
assert.match(
  adapterSource,
  /import \{PopoverContent, PopoverRoot, PopoverTrigger\} from "reka-ui"/,
)
assert.match(adapterTemplate, /<PopoverRoot[\s\S]*:open="open"/)
assert.match(adapterTemplate, /:modal="false"/)
assert.match(adapterTemplate, /@update:open="updateOpen"/)
assert.match(adapterTemplate, /<PopoverTrigger as-child>/)
assert.match(adapterTemplate, /<PopoverContent[\s\S]*v-if="open"[\s\S]*as-child/)
assert.match(adapterTemplate, /:side="props\.side"/)
assert.match(adapterTemplate, /:align="props\.align"/)
assert.match(adapterTemplate, /:collision-padding="props\.collisionPadding"/)
assert.match(adapterTemplate, /position-strategy="fixed"/)
assert.match(adapterTemplate, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(adapterTemplate, /@interact-outside="handleInteractOutside"/)
assert.match(adapterTemplate, /<slot v-else name="content" :open="open"><\/slot>/)
assert.match(adapterSource, /collisionPadding: 16/)
assert.match(adapterSource, /subscribeToLegacyOverlayOpen/)
assert.match(adapterSource, /announceCadencePopoverOpened/)
assert.match(adapterSource, /preservesPopoverOpenState\(open\.value, previousIdentity, nextIdentity\)/)
assert.match(
  adapterSource,
  /const handleInteractOutside = \(event: Event\) => \{[\s\S]*trigger\?\.contains\(event\.target\)[\s\S]*suppressCloseAutoFocus = true\n\}/,
)
assert.match(
  adapterSource,
  /const closeWithoutFocus = \(\) => \{[\s\S]*suppressCloseAutoFocus = true[\s\S]*open\.value = false\n\}/,
)
assert.match(
  adapterSource,
  /const handleCloseAutoFocus = \(event: Event\) => \{[\s\S]*event\.preventDefault\(\)[\s\S]*if \(restoreFocus\) void restoreCurrentTriggerFocus\(\)/,
)
assert.match(adapterSource, /await nextTick\(\)/)
assert.match(adapterSource, /focusCurrentPopoverTrigger\(currentRoot\)/)
assert.doesNotMatch(adapterSource, /PopoverClose|PopoverPortal|forceMount/)
assert.doesNotMatch(adapterSource, /setTimeout|setInterval/)
assert.match(
  overlayStylesSource,
  /\[data-reka-popper-content-wrapper\] > \.cadence-overlay-panel \{\n    position: static;/,
)
assert.match(
  overlayStylesSource,
  /\.cadence-overlay\[data-overlay-placement="bottom-end"\] > \.cadence-overlay-panel \{\n    right: 0;/,
)

// Same identity patches stay open; changed and missing identities close.
assert.equal(preservesPopoverOpenState(true, "dashboard-time-controls", "dashboard-time-controls"), true)
assert.equal(preservesPopoverOpenState(false, "dashboard-time-controls", "dashboard-time-controls"), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-time-controls", "replacement"), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-time-controls", ""), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-time-controls", null), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-time-controls", undefined), false)

// Escape autofocus resolves the trigger from the current patched island, never a stale ref.
let staleTriggerFocusCount = 0
let currentTriggerFocusCount = 0
const staleTrigger = {focus: () => (staleTriggerFocusCount += 1)}
const currentTrigger = {focus: () => (currentTriggerFocusCount += 1)}
let renderedTrigger = staleTrigger
const currentRoot = {
  querySelector(selector) {
    assert.equal(selector, ":scope > [data-overlay-trigger]")
    return renderedTrigger
  },
}

renderedTrigger = currentTrigger
assert.equal(focusCurrentPopoverTrigger(currentRoot), true)
assert.equal(currentTriggerFocusCount, 1)
assert.equal(staleTriggerFocusCount, 0)
assert.equal(focusCurrentPopoverTrigger({querySelector: () => null}), false)
assert.equal(focusCurrentPopoverTrigger(null), false)

class FakeWindow {
  constructor() {
    this.listeners = new Map()
    this.CustomEvent = class {
      constructor(type, options) {
        this.type = type
        this.detail = options.detail
      }
    }
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) || new Set()
    listeners.add(listener)
    this.listeners.set(type, listeners)
  }

  removeEventListener(type, listener) {
    this.listeners.get(type)?.delete(listener)
  }

  dispatchEvent(event) {
    for (const listener of this.listeners.get(event.type) || []) listener(event)
    return true
  }

  listenerCount(type) {
    return this.listeners.get(type)?.size || 0
  }
}

// Global coordination closes other islands without focusing; teardown removes every listener.
const windowObject = new FakeWindow()
const firstRoot = {id: "dashboard-time-controls"}
const secondRoot = {id: "other-overlay"}
let firstCloseCount = 0
let secondCloseCount = 0
const removeFirst = subscribeToLegacyOverlayOpen(
  windowObject,
  firstRoot,
  () => (firstCloseCount += 1),
)
const removeSecond = subscribeToLegacyOverlayOpen(
  windowObject,
  secondRoot,
  () => (secondCloseCount += 1),
)

assert.equal(windowObject.listenerCount(CADENCE_OVERLAY_OPENED_EVENT), 2)
announceCadencePopoverOpened(windowObject, firstRoot)
assert.equal(firstCloseCount, 0)
assert.equal(secondCloseCount, 1, "opening the time picker must close another overlay")
announceCadencePopoverOpened(windowObject, {id: "legacy-overlay"})
assert.equal(firstCloseCount, 1, "a legacy overlay must close the time picker")
assert.equal(secondCloseCount, 2)
removeFirst()
removeSecond()
assert.equal(windowObject.listenerCount(CADENCE_OVERLAY_OPENED_EVENT), 0)

// Keep the read-only browser smoke oracle aligned with the migrated public DOM.
assert.match(viewportSmokeSource, /document\.querySelector\("#dashboard-time-controls"\)/)
assert.match(viewportSmokeSource, /querySelector\(":scope > \[data-overlay-trigger\]"\)\?\.click\(\)/)
assert.match(viewportSmokeSource, /overlayOpen: timeControls\?\.hasAttribute\("data-overlay-open"\)/)
assert.match(viewportSmokeSource, /controlsVisible: visible\(document\.querySelector\("#dashboard-time-query-controls"\)\)/)
assert.match(viewportSmokeSource, /key: "Escape"/)
assert.match(
  viewportSmokeSource,
  /!document\.querySelector\("#dashboard-time-controls"\)\?\.hasAttribute\("data-overlay-open"\)[\s\S]*document\.querySelector\("#dashboard-time-controls-panel"\)\?\.hidden/,
)

console.log("dashboard_time_picker_test passed")
