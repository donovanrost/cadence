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

const nodeScenarioLedger = [
  "CadencePopover owns the warning overlay without changing caller-owned ids or DOM presentation",
  "warning details evidence and data-link rows retain every server-provided attribute and class",
  "the trigger and panel expose synchronized dialog aria and hidden state",
  "bottom-end positioning uses the existing eight pixel offset and sixteen pixel collision padding",
  "Escape focuses the current trigger while outside and global dismissals suppress focus restoration",
  "panel evidence and data-link actions do not implicitly dismiss the popover",
  "truthy unchanged identity preserves open state while changed or missing identity closes",
]

assert.equal(process.versions.node, "24.16.0", "widget warning contracts use pinned Node 24.16.0")
assert.equal(nodeScenarioLedger.length, 7)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/WidgetWarning.vue")
const adapterPath = resolve(__dirname, "../vue/ui/reka/CadencePopover.vue")
const overlayStylesPath = resolve(__dirname, "../css/components/overlay.css")
const presenterPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/widget_warning_components.ex",
)

const [source, adapterSource, overlayStylesSource, presenterSource] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(adapterPath, "utf8"),
  readFile(overlayStylesPath, "utf8"),
  readFile(presenterPath, "utf8"),
])
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(template, "WidgetWarning.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

// The migration changes overlay mechanics only; the presentation remains the public contract.
assert.match(source, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.equal(template.match(/<CadencePopover/g)?.length, 1)
assert.match(template, /:id="props\.presentation\.overlay\.id"/)
assert.match(template, /:identity="props\.presentation\.overlay\.id"/)
assert.match(template, /:class="props\.presentation\.overlay\.class"/)
assert.match(template, /v-bind="props\.presentation\.overlay\.attrs"/)
assert.match(template, /side="bottom"/)
assert.match(template, /align="end"/)
assert.match(template, /:side-offset="8"/)
assert.match(template, /:collision-padding="16"/)

assert.match(template, /:id="props\.presentation\.trigger\.id"/)
assert.match(template, /:type="props\.presentation\.trigger\.type"/)
assert.match(template, /:class="props\.presentation\.trigger\.class"/)
assert.match(template, /v-bind="props\.presentation\.trigger\.attrs"/)
assert.match(template, /:aria-expanded="String\(open\)"/)
assert.match(template, /v-bind="props\.presentation\.trigger\.badge\.attrs"/)

assert.match(source, /const attrs = \{\.\.\.props\.presentation\.panel\.attrs\}/)
assert.match(source, /delete attrs\.hidden/)
assert.match(template, /:id="props\.presentation\.panel\.id"/)
assert.match(template, /:class="props\.presentation\.panel\.class"/)
assert.match(template, /v-bind="panelAttrs"[\s\S]*:hidden="!open"/)

assert.match(template, /v-bind="props\.presentation\.body\.evidence_button\.attrs"/)
assert.match(template, /v-if="props\.presentation\.body\.details\.visible"/)
assert.match(template, /v-bind="row\.value\.attrs"/)
assert.match(template, /v-if="props\.presentation\.body\.evidence\.visible"/)
assert.match(template, /v-bind="props\.presentation\.body\.evidence\.attrs"/)
assert.match(template, /v-if="props\.presentation\.body\.links\.visible"/)
assert.match(template, /v-bind="props\.presentation\.body\.links\.attrs"/)
assert.match(template, /v-for="row in props\.presentation\.body\.links\.rows"/)
assert.match(template, /v-bind="row\.attrs"/)
assert.doesNotMatch(template, /@click|@pointerdown|@keydown/)
assert.doesNotMatch(source, /open_data_link|open_evidence|phx-hook/)
assert.doesNotMatch(source, /severity|badge-(?:error|warning|info)|\.length/)
assert.doesNotMatch(
  source,
  /createWidgetWarningController|WIDGET_WARNING_CONTROLLER|addEventListener|removeEventListener/,
)
assert.doesNotMatch(source, /onMounted|onBeforeUpdate|onUpdated|onBeforeUnmount/)

// The read-only presenter continues to own event names, payloads, and domain decisions.
assert.match(presenterSource, /\|> EvidenceAttrs\.warning\(placement_id\)/)
assert.match(presenterSource, /"phx-click" => "open_evidence"/)
assert.match(
  presenterSource,
  /\|> DataLinkAttrs\.open\([\s\S]*placement_id: placement_id,[\s\S]*context_fallback:/,
)
assert.match(presenterSource, /"phx-click" => "open_data_link"/)
assert.match(presenterSource, /warning_data_link_context_fallback\(warning\)/)
assert.match(presenterSource, /warning_badge_class\(%\{severity: :error\}\)/)

// CadencePopover supplies non-modal Reka dialog behavior and compatibility semantics.
assert.match(
  adapterSource,
  /import \{PopoverContent, PopoverRoot, PopoverTrigger\} from "reka-ui"/,
)
assert.match(adapterTemplate, /<PopoverRoot[\s\S]*:open="open"[\s\S]*:modal="false"/)
assert.match(adapterTemplate, /<PopoverTrigger as-child>/)
assert.match(adapterTemplate, /<PopoverContent[\s\S]*v-if="open"[\s\S]*as-child/)
assert.match(adapterTemplate, /:side="props\.side"/)
assert.match(adapterTemplate, /:align="props\.align"/)
assert.match(adapterTemplate, /:collision-padding="props\.collisionPadding"/)
assert.match(adapterTemplate, /position-strategy="fixed"/)
assert.match(adapterSource, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(adapterSource, /@interact-outside="handleInteractOutside"/)
assert.match(adapterSource, /focusCurrentPopoverTrigger\(currentRoot\)/)
assert.match(
  adapterSource,
  /const handleInteractOutside = \(event: Event\) => \{[\s\S]*event\.preventDefault\(\)[\s\S]*closeWithoutFocus\(\)\n\}/,
)
assert.match(
  adapterSource,
  /const closeWithoutFocus = \(\) => \{[\s\S]*suppressCloseAutoFocus = true[\s\S]*open\.value = false\n\}/,
)
assert.match(adapterSource, /preservesPopoverOpenState\(open\.value, previousIdentity, nextIdentity\)/)
assert.match(
  overlayStylesSource,
  /\[data-reka-popper-content-wrapper\] > \.cadence-overlay-panel \{\n    position: static;/,
)

assert.equal(preservesPopoverOpenState(true, "warning-a", "warning-a"), true)
assert.equal(preservesPopoverOpenState(false, "warning-a", "warning-a"), false)
assert.equal(preservesPopoverOpenState(true, "warning-a", "warning-b"), false)
assert.equal(preservesPopoverOpenState(true, "warning-a", ""), false)
assert.equal(preservesPopoverOpenState(true, "warning-a", null), false)
assert.equal(preservesPopoverOpenState(true, "warning-a", undefined), false)

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

class FakeWindow extends EventTarget {
  CustomEvent = class extends Event {
    constructor(type, options) {
      super(type)
      this.detail = options.detail
    }
  }
}

const windowObject = new FakeWindow()
const firstRoot = {id: "warning-first"}
const secondRoot = {id: "warning-second"}
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

announceCadencePopoverOpened(windowObject, firstRoot)
assert.equal(firstCloseCount, 0)
assert.equal(secondCloseCount, 1, "global coordination closes peers without doing focus work")
windowObject.dispatchEvent(new windowObject.CustomEvent(CADENCE_OVERLAY_OPENED_EVENT, {detail: {}}))
assert.equal(firstCloseCount, 1)
assert.equal(secondCloseCount, 2)
removeFirst()
removeSecond()

console.log("widget_warning_test passed")
