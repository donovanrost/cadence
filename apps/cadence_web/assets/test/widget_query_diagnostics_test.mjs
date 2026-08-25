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

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/WidgetQueryDiagnostics.vue")
const adapterPath = resolve(__dirname, "../vue/ui/reka/CadencePopover.vue")
const overlayStylesPath = resolve(__dirname, "../css/components/overlay.css")
const componentSource = await readFile(componentPath, "utf8")
const adapterSource = await readFile(adapterPath, "utf8")
const overlayStylesSource = await readFile(overlayStylesPath, "utf8")
const componentTemplate = componentSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(componentTemplate, "WidgetQueryDiagnostics.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

// The presentation remains the sole source of public DOM and Phoenix contracts.
assert.match(componentSource, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.match(componentTemplate, /:id="props\.presentation\.overlay\.id"/)
assert.match(componentTemplate, /:identity="props\.presentation\.overlay\.id"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.overlay\.attrs"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.trigger\.attrs"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.trigger\.content\.attrs"/)
assert.match(componentSource, /const attrs = \{\.\.\.props\.presentation\.panel\.attrs\}/)
assert.match(componentSource, /delete attrs\.hidden/)
assert.match(componentTemplate, /v-bind="panelAttrs"[\s\S]*:hidden="!open"/)
assert.match(componentTemplate, /v-bind="row\.label\.attrs"/)
assert.match(componentTemplate, /v-bind="row\.value\.attrs"/)
assert.match(componentTemplate, /v-bind="props\.presentation\.body\.evidence_button\.attrs"/)
assert.match(componentTemplate, /:aria-expanded="String\(open\)"/)
assert.match(componentTemplate, /:hidden="!open"/)
assert.match(componentTemplate, /:key="row\.key"/)
assert.doesNotMatch(
  componentTemplate,
  /Widget query|Open query evidence|open_evidence|hero-|btn |cadence:/,
)
assert.doesNotMatch(componentSource, /cadence:overlay-opened|addEventListener|removeEventListener/)
assert.doesNotMatch(componentSource, /createWidgetQueryDiagnosticsController|onBeforeUpdate|onUpdated/)
assert.doesNotMatch(componentSource, /phx-hook|<script(?! setup)/)

// The adapter makes the Reka decisions explicit and keeps the legacy bridge centralized.
assert.match(
  adapterSource,
  /import \{PopoverContent, PopoverRoot, PopoverTrigger\} from "reka-ui"/,
)
assert.match(adapterTemplate, /<PopoverRoot[\s\S]*:open="open"/)
assert.match(adapterTemplate, /:modal="false"/)
assert.match(adapterTemplate, /@update:open="updateOpen"/)
assert.match(adapterTemplate, /<PopoverTrigger as-child>/)
assert.match(adapterTemplate, /<PopoverContent[\s\S]*v-if="open"[\s\S]*as-child/)
assert.match(adapterTemplate, /:side-offset="props\.sideOffset"/)
assert.match(adapterTemplate, /:collision-padding="props\.collisionPadding"/)
assert.match(adapterTemplate, /position-strategy="fixed"/)
assert.match(adapterTemplate, /<slot v-else name="content" :open="open"><\/slot>/)
assert.doesNotMatch(adapterSource, /PopoverPortal|forceMount/)
assert.match(adapterSource, /sideOffset: 8/)
assert.match(adapterSource, /collisionPadding: 16/)
assert.match(adapterSource, /subscribeToLegacyOverlayOpen/)
assert.match(adapterSource, /announceCadencePopoverOpened/)
assert.match(adapterSource, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(adapterSource, /@interact-outside="handleInteractOutside"/)
assert.match(adapterSource, /event\.preventDefault\(\)/)
assert.match(adapterSource, /await nextTick\(\)/)
assert.match(adapterSource, /focusCurrentPopoverTrigger\(currentRoot\)/)
assert.match(
  adapterSource,
  /const handleInteractOutside = \(event: Event\) => \{[\s\S]*suppressCloseAutoFocus = true\n\}/,
)
assert.match(
  adapterSource,
  /const closeWithoutFocus = \(\) => \{[\s\S]*suppressCloseAutoFocus = true[\s\S]*open\.value = false\n\}/,
)
assert.match(adapterSource, /preservesPopoverOpenState\(open\.value, previousIdentity, nextIdentity\)/)
assert.doesNotMatch(adapterSource, /<style(?:\s[^>]*)?>/)
assert.match(
  overlayStylesSource,
  /@layer components \{[\s\S]*\[data-reka-popper-content-wrapper\] > \.cadence-overlay-panel \{\n    position: static;/,
)
assert.doesNotMatch(adapterSource, /setTimeout|setInterval/)

// Open state survives only a truthy, unchanged overlay identity across a prop patch.
assert.equal(preservesPopoverOpenState(true, "widget-query-a", "widget-query-a"), true)
assert.equal(preservesPopoverOpenState(false, "widget-query-a", "widget-query-a"), false)
assert.equal(preservesPopoverOpenState(true, "widget-query-a", "widget-query-b"), false)
assert.equal(preservesPopoverOpenState(true, "widget-query-a", ""), false)
assert.equal(preservesPopoverOpenState(true, "widget-query-a", null), false)
assert.equal(preservesPopoverOpenState(true, "widget-query-a", undefined), false)

// Close autofocus resolves the public trigger from the current island instead of a stale Reka ref.
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

// Reka islands and remaining legacy overlays retain one-open coordination without focus work here.
const windowObject = new FakeWindow()
const firstRoot = {id: "widget-query-first"}
const secondRoot = {id: "widget-query-second"}
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
assert.equal(firstCloseCount, 0, "an opening popover must ignore its own announcement")
assert.equal(secondCloseCount, 1, "opening one Reka popover must close the other island")

const legacyRoot = {id: "legacy-overlay"}
announceCadencePopoverOpened(windowObject, legacyRoot)
assert.equal(firstCloseCount, 1, "a legacy overlay must close an open Reka popover")
assert.equal(secondCloseCount, 2, "legacy coordination must reach every mounted adapter")

removeFirst()
removeSecond()
assert.equal(
  windowObject.listenerCount(CADENCE_OVERLAY_OPENED_EVENT),
  0,
  "adapter teardown must leave no compatibility listeners",
)

announceCadencePopoverOpened(windowObject, legacyRoot)
assert.equal(firstCloseCount, 1)
assert.equal(secondCloseCount, 2)

console.log("widget_query_diagnostics_test passed")
