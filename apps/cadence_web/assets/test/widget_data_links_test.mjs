import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  announceCadencePopoverOpened,
  focusCurrentPopoverTrigger,
  preservesPopoverOpenState,
  subscribeToLegacyOverlayOpen,
} from "../vue/ui/reka/popover_compatibility.js"

const nodeScenarioLedger = [
  "one CadencePopover renders all five server-selected data-link menu variants",
  "caller-owned root trigger and panel ids classes attributes and aria remain exact",
  "every open_data_link and open_evidence payload passes through the generic item binding",
  "bottom-end dialog positioning retains eight pixel offset and sixteen pixel collision padding",
  "panel actions stay open while outside and global dismissals do not restore focus",
  "Escape restores focus through the current public trigger rather than a stale trigger",
  "open state survives only the same truthy root identity and closes on changed or missing identity",
]

assert.equal(process.versions.node, "24.16.0", "widget data-link contracts use pinned Node 24.16.0")
assert.equal(nodeScenarioLedger.length, 7)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/WidgetDataLinks.vue")
const adapterPath = resolve(__dirname, "../vue/ui/reka/CadencePopover.vue")
const presenterPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/widget_data_link_components.ex",
)
const dataLinkAttrsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/data_link_attrs.ex",
)
const evidenceAttrsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/evidence_attrs.ex",
)

const [source, adapterSource, presenterSource, dataLinkAttrsSource, evidenceAttrsSource] =
  await Promise.all([
    readFile(componentPath, "utf8"),
    readFile(adapterPath, "utf8"),
    readFile(presenterPath, "utf8"),
    readFile(dataLinkAttrsPath, "utf8"),
    readFile(evidenceAttrsPath, "utf8"),
  ])
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(template, "WidgetDataLinks.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

const expectedKinds = [
  "widget",
  "status_matrix_row",
  "data_table_row",
  "state_timeline_row",
  "event_timeline_row",
]
const kindType = source.match(/kind:\n([\s\S]*?)\n  component_id:/)?.[1]
assert.ok(kindType, "WidgetDataLinks must retain its five-kind presentation union")
for (const kind of expectedKinds) assert.match(kindType, new RegExp(`\\| "${kind}"`))

// Reka owns mechanics while the server presentation remains the sole public DOM source.
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
assert.match(template, /v-bind="props\.presentation\.trigger\.content\.attrs"/)
assert.match(source, /const attrs = \{\.\.\.props\.presentation\.panel\.attrs\}/)
assert.match(source, /delete attrs\.hidden/)
assert.match(template, /:id="props\.presentation\.panel\.id"/)
assert.match(template, /:class="props\.presentation\.panel\.class"/)
assert.match(template, /v-bind="panelAttrs"[\s\S]*:hidden="!open"/)

assert.match(template, /v-for="item in props\.presentation\.items"/)
assert.match(template, /:key="item\.key"/)
assert.match(template, /:type="item\.type"/)
assert.match(template, /:class="item\.class"/)
assert.match(template, /v-bind="item\.attrs"/)
assert.doesNotMatch(template, /@click|@pointerdown|@keydown/)
assert.doesNotMatch(source, /open_data_link|open_evidence|phx-value-/)
assert.doesNotMatch(
  source,
  /createWidgetDataLinksController|WIDGET_DATA_LINKS_CONTROLLER|addEventListener|removeEventListener/,
)
assert.doesNotMatch(source, /onMounted|onBeforeUpdate|onUpdated|onBeforeUnmount/)

// The read-only presenter owns all five variants, timestamps, evidence, and navigation payloads.
const presenterContracts = [
  ["widget_data_link_presentation", '"widget"', "widget_link_item"],
  ["status_matrix_row_link_presentation", '"status_matrix_row"', "status_matrix_link_item"],
  ["data_table_row_link_presentation", '"data_table_row"', "data_table_link_item"],
  ["state_timeline_row_link_presentation", '"state_timeline_row"', "state_timeline_link_item"],
  ["event_timeline_row_link_presentation", '"event_timeline_row"', "event_timeline_link_item"],
]
for (const [presentationFunction, kind, itemFunction] of presenterContracts) {
  assert.match(presenterSource, new RegExp(`def ${presentationFunction}\\(`))
  assert.ok(presenterSource.includes(kind), `${presentationFunction} must retain ${kind}`)
  assert.match(presenterSource, new RegExp(itemFunction))
}
assert.match(presenterSource, /DataLinkAttrs\.open\(link,[\s\S]*placement_id: placement_id/)
assert.match(presenterSource, /Map\.put\("phx-click", "open_data_link"\)/)
assert.match(presenterSource, /EvidenceAttrs\.row_frame\(placement_id, row\)/)
assert.match(presenterSource, /Map\.put\("phx-click", "open_evidence"\)/)
assert.match(presenterSource, /DateTime\.to_unix\(occurred_at, :millisecond\)/)
assert.match(presenterSource, /DateTime\.to_unix\(starts_at, :millisecond\)/)

const dataLinkPayloadAttrs = Array.from(
  dataLinkAttrsSource.matchAll(/"[^"\n]+" => "(phx-value-[^"\n]+)"/g),
  (match) => match[1],
)
assert.ok(dataLinkPayloadAttrs.length >= 45, "the full server data-link payload registry is covered")
assert.equal(new Set(dataLinkPayloadAttrs).size, dataLinkPayloadAttrs.length)
for (const requiredAttr of [
  "phx-value-link-id",
  "phx-value-target",
  "phx-value-target-id",
  "phx-value-placement-id",
  "phx-value-timestamp-ms",
  "phx-value-realm",
  "phx-value-data-source-id",
  "phx-value-source-binding-id",
  "phx-value-time-mode",
  "phx-value-time-axis",
  "phx-value-replay-run-id",
  "phx-value-scope-kind",
  "phx-value-scope-id",
  "phx-value-scope-ids",
  "phx-value-nav-trail",
]) {
  assert.ok(dataLinkPayloadAttrs.includes(requiredAttr), `${requiredAttr} must remain server-owned`)
}
assert.match(evidenceAttrsSource, /def row_frame\(placement_id, row\) when is_map\(row\)/)
for (const evidenceKey of [
  '"kind" => "frame"',
  '"placement-id" => event_value(placement_id)',
  '"observable-id" => event_value(frame_observable_id(row))',
  '"source-request-id" => event_value(row, :source_request_id)',
  '"scope-kind" => row_scope_kind(row)',
  '"scope-id" => row_scope_id(row)',
  '"scope-ids" => row_scope_ids(row)',
]) {
  assert.ok(evidenceAttrsSource.includes(evidenceKey), `missing evidence payload contract ${evidenceKey}`)
}

// The shared adapter provides the exact dismissal, focus, and collision behavior.
assert.match(adapterTemplate, /<PopoverRoot[\s\S]*:open="open"[\s\S]*:modal="false"/)
assert.match(adapterTemplate, /<PopoverTrigger as-child>/)
assert.match(adapterTemplate, /<PopoverContent[\s\S]*v-if="open"[\s\S]*as-child/)
assert.match(adapterTemplate, /:side="props\.side"/)
assert.match(adapterTemplate, /:align="props\.align"/)
assert.match(adapterTemplate, /:side-offset="props\.sideOffset"/)
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

// Identity behavior is explicit: only an open popover with the same truthy identity survives.
assert.equal(preservesPopoverOpenState(true, "data-links-a", "data-links-a"), true)
assert.equal(preservesPopoverOpenState(false, "data-links-a", "data-links-a"), false)
assert.equal(preservesPopoverOpenState(true, "data-links-a", "data-links-b"), false)
assert.equal(preservesPopoverOpenState(true, "data-links-a", ""), false)
assert.equal(preservesPopoverOpenState(true, "data-links-a", null), false)
assert.equal(preservesPopoverOpenState(true, "data-links-a", undefined), false)
assert.equal(preservesPopoverOpenState(true, "", ""), false)

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
const firstRoot = {id: "data-links-first"}
const secondRoot = {id: "data-links-second"}
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
assert.equal(secondCloseCount, 1, "global dismissal closes without invoking focus helpers")
removeFirst()
removeSecond()

console.log("widget_data_links_test passed")
