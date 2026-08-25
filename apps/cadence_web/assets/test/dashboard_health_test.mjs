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
  "one CadencePopover per health group preserves public root trigger and panel identities",
  "all dashboard health attrs classes text item anchors and server ordering pass through",
  "open_evidence capture_dashboard_health_snapshot and clipboard contracts stay Phoenix-owned",
  "trigger activation toggles synchronized aria hidden and data-overlay-open state",
  "opening one group closes every other Reka or legacy overlay without restoring focus",
  "truthy unchanged overlay identity preserves open state across DTO object refreshes",
  "removed or changed identities close and adapter teardown removes coordination listeners",
  "outside dismissal suppresses focus while Escape resolves the current public trigger",
  "bottom-end fixed inline positioning keeps the existing offsets width and collision gutter",
  "the server alone decides whether the non-SSR DashboardHealth island is rendered",
]

assert.equal(process.versions.node, "24.16.0", "DashboardHealth contracts use pinned Node 24.16.0")
assert.equal(nodeScenarioLedger.length, 10)
assert.equal(CADENCE_OVERLAY_OPENED_EVENT, "cadence:overlay-opened")

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/DashboardHealth.vue")
const adapterPath = resolve(__dirname, "../vue/ui/reka/CadencePopover.vue")
const clipboardPath = resolve(__dirname, "../vue/ClipboardButton.vue")
const overlayStylesPath = resolve(__dirname, "../css/components/overlay.css")
const viewportSmokePath = resolve(__dirname, "dashboard_viewport_smoke.mjs")
const presenterPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_health_components.ex",
)
const presenterTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_dashboard_show_live/dashboard_health_components_test.exs",
)

const [
  source,
  adapterSource,
  clipboardSource,
  overlayStylesSource,
  viewportSmokeSource,
  presenterSource,
  presenterTestSource,
] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(adapterPath, "utf8"),
  readFile(clipboardPath, "utf8"),
  readFile(overlayStylesPath, "utf8"),
  readFile(viewportSmokePath, "utf8"),
  readFile(presenterPath, "utf8"),
  readFile(presenterTestPath, "utf8"),
])

const script = source.match(/<script setup(?: lang="ts")?>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "DashboardHealth.vue must have a script setup block")
assert.ok(template, "DashboardHealth.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

// DashboardHealth renders the server presentation while CadencePopover owns overlay mechanics.
assert.match(script, /import ClipboardButton from "\.\/ClipboardButton\.vue"/)
assert.match(script, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.match(script, /presentation: \{type: Object, required: true\}/)
assert.equal(template.match(/<CadencePopover\b/g)?.length, 1)

assert.match(template, /:id="presentation\.root\.id"/)
assert.match(template, /:class="presentation\.root\.class"/)
assert.match(template, /v-bind="presentation\.root\.attrs"/)
assert.match(template, /:class="presentation\.label\.class"/)
assert.match(template, /\{\{ presentation\.label\.text \}\}/)
assert.match(template, /:class="presentation\.status\.class"/)
assert.match(template, /\{\{ presentation\.status\.text \}\}/)
assert.match(template, /:class="presentation\.summary\.class"/)
assert.match(template, /\{\{ presentation\.summary\.text \}\}/)
assert.match(template, /:class="presentation\.controls_class"/)

assert.match(template, /:id="presentation\.copy_host\.id"/)
assert.match(template, /:class="presentation\.copy_host\.class"/)
assert.match(template, /<ClipboardButton v-bind="presentation\.copy_props" \/>/)
assert.match(clipboardSource, /v-bind="props\.data_attrs"/)

assert.match(template, /:id="presentation\.evidence\.id"/)
assert.match(template, /:type="presentation\.evidence\.type"/)
assert.match(template, /:class="presentation\.evidence\.class"/)
assert.match(template, /:title="presentation\.evidence\.title"/)
assert.match(template, /:aria-label="presentation\.evidence\.aria_label"/)
assert.match(template, /v-bind="presentation\.evidence\.attrs"/)
assert.match(
  template,
  /:class="\[presentation\.evidence\.icon\.name, presentation\.evidence\.icon\.class\]"/,
)

assert.match(template, /:id="presentation\.capture\.id"/)
assert.match(template, /:type="presentation\.capture\.type"/)
assert.match(template, /:class="presentation\.capture\.class"/)
assert.match(template, /:title="presentation\.capture\.title"/)
assert.match(template, /:aria-label="presentation\.capture\.aria_label"/)
assert.match(template, /v-bind="presentation\.capture\.attrs"/)
assert.match(
  template,
  /:class="\[presentation\.capture\.icon\.name, presentation\.capture\.icon\.class\]"/,
)

assert.match(template, /v-for="group in presentation\.groups"/)
assert.match(template, /:id="group\.overlay\.id"/)
assert.match(template, /:key="group\.key"/)
assert.match(template, /:identity="group\.overlay\.id"/)
assert.match(template, /:class="group\.overlay\.class"/)
assert.match(template, /v-bind="group\.overlay\.attrs"/)
assert.match(template, /side="bottom"/)
assert.match(template, /align="end"/)
assert.match(template, /:side-offset="8"/)
assert.match(template, /:collision-padding="16"/)

assert.match(template, /<template #trigger="\{open\}">/)
assert.match(template, /:id="group\.overlay\.trigger\.id"/)
assert.match(template, /:type="group\.overlay\.trigger\.type"/)
assert.match(template, /:class="group\.overlay\.trigger\.class"/)
assert.match(template, /v-bind="group\.overlay\.trigger\.attrs"/)
assert.match(
  template,
  /:aria-expanded="[\s\S]*open[\s\S]*group\.overlay\.trigger\.aria_expanded\.open[\s\S]*group\.overlay\.trigger\.aria_expanded\.closed[\s\S]*"/,
)
assert.match(template, /:class="group\.badge\.class"/)
assert.match(template, /:title="group\.badge\.title"/)
assert.match(template, /v-bind="group\.badge\.attrs"/)
assert.match(template, /:class="\[group\.badge\.icon\.name, group\.badge\.icon\.class\]"/)
assert.match(template, /\{\{ group\.badge\.label \}\}/)
assert.match(template, /:class="group\.badge\.count_class"/)
assert.match(template, /\{\{ group\.badge\.count \}\}/)

assert.match(template, /<template #content="\{open\}">/)
assert.match(template, /:id="group\.overlay\.panel\.id"/)
assert.match(template, /:class="group\.overlay\.panel\.class"/)
assert.match(template, /v-bind="group\.overlay\.panel\.attrs"[\s\S]*:hidden="!open"/)
assert.match(template, /:class="group\.details\.class"/)
assert.match(template, /:class="group\.details\.heading\.class"/)
assert.match(template, /\{\{ group\.details\.heading\.text \}\}/)
assert.match(template, /:class="group\.details\.items_class"/)
assert.match(template, /v-for="item in group\.items"/)
assert.match(template, /:key="item\.key"/)
assert.match(template, /:href="item\.href"/)
assert.match(template, /:class="item\.class"/)
assert.match(template, /v-bind="item\.attrs"/)
assert.match(template, /:class="item\.title\.class"/)
assert.match(template, /\{\{ item\.title\.text \}\}/)
assert.match(template, /:class="item\.reason\.class"/)
assert.match(template, /\{\{ item\.reason\.text \}\}/)

assert.doesNotMatch(template, /@click|@pointerdown|@keydown/)
assert.doesNotMatch(source, /nextTick|onMounted|onUpdated|onBeforeUnmount|ref\(/)
assert.doesNotMatch(source, /addEventListener|removeEventListener|dispatchEvent|CustomEvent/)
assert.doesNotMatch(source, /openGroupId|overlayState|positionPanel|cadence:overlay-opened/)
assert.doesNotMatch(source, /\.sort\(|\.reverse\(|\.splice\(/)
assert.doesNotMatch(
  template,
  /Dashboard health|Open dashboard health|Capture dashboard health|open_evidence|capture_dashboard_health_snapshot|#widget-|btn |badge |hero-/,
)

// The read-only Phoenix presenter remains authoritative for visibility, identity, actions, and DTOs.
assert.match(
  presenterSource,
  /def dashboard_health_strip\(%\{health: %\{visible\?: true\} = health\} = assigns\)/,
)
assert.match(presenterSource, /def dashboard_health_strip\(assigns\), do: ~H""/)
assert.match(presenterSource, /id="dashboard-health-rollup-component"/)
assert.match(presenterSource, /v-component="DashboardHealth"/)
assert.match(presenterSource, /presentation=\{@presentation\}/)
assert.match(presenterSource, /v-ssr=\{false\}/)
assert.match(presenterSource, /class="contents"/)
assert.match(presenterSource, /id: "dashboard-health-rollup"/)
assert.match(presenterSource, /id: "dashboard-health-snapshot-copy-component"/)
assert.match(presenterSource, /button_id: "dashboard-health-snapshot-copy"/)
assert.match(presenterSource, /id: "dashboard-health-snapshot-capture"/)
assert.match(presenterSource, /"phx-click" => "open_evidence"/)
assert.match(presenterSource, /"phx-click" => "capture_dashboard_health_snapshot"/)
assert.match(presenterSource, /"phx-value-snapshot" => snapshot_json/)

assert.match(presenterSource, /\|> dashboard_health_groups\(\)/)
assert.match(presenterSource, /\|> Enum\.with_index\(\)/)
assert.match(presenterSource, /dashboard_health_group_dto\(group, index\)/)
assert.match(presenterSource, /overlay_id = "dashboard-health-group-#\{group_key\}"/)
assert.match(presenterSource, /key: "#\{overlay_id\}-#\{index\}"/)
assert.match(presenterSource, /id: "#\{overlay_id\}-trigger"/)
assert.match(presenterSource, /"aria-controls" => "#\{overlay_id\}-panel"/)
assert.match(presenterSource, /id: "#\{overlay_id\}-panel"/)
assert.match(presenterSource, /"data-overlay-kind" => "popover"/)
assert.match(presenterSource, /"data-overlay-placement" => "bottom-end"/)
assert.match(presenterSource, /"data-overlay-width" => "md"/)
assert.match(presenterSource, /\|> Map\.get\(:items, \[\]\)/)
assert.match(presenterSource, /dashboard_health_item_dto\(item, group_key, item_index\)/)
assert.match(presenterSource, /href: "#widget-#\{placement_id\}"/)

assert.match(
  presenterTestSource,
  /test "dashboard health strip renders no island unless visibility is exactly true"[\s\S]*for visible\? <- \[false, nil, "true", 1\]/,
)
assert.match(
  presenterTestSource,
  /assert Enum\.map\(presentation\["groups"\], & &1\["order"\]\) == \[0, 1\]/,
)
assert.match(
  presenterTestSource,
  /assert Enum\.map\(degraded_group\["items"\], & &1\["href"\]\) == \["#widget-degraded-placement"\]/,
)

const dashboardHealthDataAttrs = Array.from(
  new Set(
    Array.from(
      presenterSource.matchAll(/"(data-dashboard-health-[^"]+)"/g),
      (match) => match[1],
    ),
  ),
).sort()

assert.deepEqual(dashboardHealthDataAttrs, [
  "data-dashboard-health-affected",
  "data-dashboard-health-affected-placements",
  "data-dashboard-health-badge",
  "data-dashboard-health-badge-count",
  "data-dashboard-health-badge-placements",
  "data-dashboard-health-blocked",
  "data-dashboard-health-blocked-placements",
  "data-dashboard-health-degraded",
  "data-dashboard-health-degraded-placements",
  "data-dashboard-health-evidence-open",
  "data-dashboard-health-group",
  "data-dashboard-health-group-count",
  "data-dashboard-health-group-placements",
  "data-dashboard-health-item",
  "data-dashboard-health-item-lifecycle",
  "data-dashboard-health-item-reason",
  "data-dashboard-health-item-source",
  "data-dashboard-health-item-state",
  "data-dashboard-health-item-warnings",
  "data-dashboard-health-ready",
  "data-dashboard-health-rollup",
  "data-dashboard-health-severity",
  "data-dashboard-health-snapshot-capture",
  "data-dashboard-health-snapshot-copy",
  "data-dashboard-health-snapshot-id",
  "data-dashboard-health-snapshot-schema",
  "data-dashboard-health-stale",
  "data-dashboard-health-stale-placements",
  "data-dashboard-health-state",
  "data-dashboard-health-states",
  "data-dashboard-health-widgets",
])

// The read-only adapter supplies synchronized state, non-modal fixed positioning, and focus policy.
assert.match(
  adapterSource,
  /import \{PopoverContent, PopoverRoot, PopoverTrigger\} from "reka-ui"/,
)
assert.match(adapterTemplate, /:data-overlay-open="open \? '' : undefined"/)
assert.match(adapterTemplate, /<PopoverRoot[\s\S]*:open="open"[\s\S]*:modal="false"/)
assert.match(adapterTemplate, /@update:open="updateOpen"/)
assert.match(adapterTemplate, /<PopoverTrigger as-child>/)
assert.match(adapterTemplate, /<PopoverContent[\s\S]*v-if="open"[\s\S]*as-child/)
assert.match(adapterTemplate, /:side="props\.side"/)
assert.match(adapterTemplate, /:align="props\.align"/)
assert.match(adapterTemplate, /:side-offset="props\.sideOffset"/)
assert.match(adapterTemplate, /:collision-padding="props\.collisionPadding"/)
assert.match(adapterTemplate, /:prioritize-position="props\.prioritizePosition"/)
assert.match(adapterTemplate, /position-strategy="fixed"/)
assert.match(adapterTemplate, /sticky="always"/)
assert.match(adapterTemplate, /<slot v-else name="content" :open="open"><\/slot>/)
assert.doesNotMatch(adapterSource, /PopoverPortal|forceMount/)
assert.match(adapterSource, /sideOffset: 8/)
assert.match(adapterSource, /collisionPadding: 16/)
assert.match(adapterSource, /prioritizePosition: true/)
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
assert.match(adapterSource, /onBeforeUnmount\(\(\) => \{[\s\S]*removeLegacyOverlayListener\?\.\(\)/)

assert.match(
  overlayStylesSource,
  /\[data-reka-popper-content-wrapper\] > \.cadence-overlay-panel \{\n    position: static;/,
)
assert.match(
  overlayStylesSource,
  /\.cadence-popover-panel\[data-overlay-width="md"\] \{ width: min\(20rem, calc\(100vw - 2rem\)\); \}/,
)
assert.match(viewportSmokeSource, /narrow\.wrapper\.position,[\s\S]*"fixed"/)
assert.match(viewportSmokeSource, /style\.transform !== "none"/)
assert.match(viewportSmokeSource, /panelRect\.left >= 15/)
assert.match(viewportSmokeSource, /panelRect\.right <= window\.innerWidth - 15/)

// Open state survives only a truthy, unchanged group.overlay.id across a prop patch.
const blockedIdentity = "dashboard-health-group-blocked"
assert.equal(preservesPopoverOpenState(true, blockedIdentity, blockedIdentity), true)
assert.equal(preservesPopoverOpenState(false, blockedIdentity, blockedIdentity), false)
assert.equal(
  preservesPopoverOpenState(true, blockedIdentity, "dashboard-health-group-degraded"),
  false,
)
assert.equal(preservesPopoverOpenState(true, blockedIdentity, ""), false)
assert.equal(preservesPopoverOpenState(true, blockedIdentity, null), false)
assert.equal(preservesPopoverOpenState(true, blockedIdentity, undefined), false)

// Escape focus resolves the current public trigger after a DTO refresh, never a stale element.
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

class FakeWindow extends EventTarget {
  CustomEvent = class extends Event {
    constructor(type, options) {
      super(type)
      this.detail = options.detail
    }
  }

  listenerCount(type) {
    return this.listeners?.get(type)?.size || 0
  }

  addEventListener(type, listener) {
    const listeners = this.listeners?.get(type) || new Set()
    listeners.add(listener)
    this.listeners ||= new Map()
    this.listeners.set(type, listeners)
    super.addEventListener(type, listener)
  }

  removeEventListener(type, listener) {
    this.listeners?.get(type)?.delete(listener)
    super.removeEventListener(type, listener)
  }
}

// Every group adapter participates in one-open coordination without doing focus work here.
const windowObject = new FakeWindow()
const blockedRoot = {id: blockedIdentity}
const degradedRoot = {id: "dashboard-health-group-degraded"}
let blockedCloseCount = 0
let degradedCloseCount = 0
const removeBlocked = subscribeToLegacyOverlayOpen(
  windowObject,
  blockedRoot,
  () => (blockedCloseCount += 1),
)
const removeDegraded = subscribeToLegacyOverlayOpen(
  windowObject,
  degradedRoot,
  () => (degradedCloseCount += 1),
)

assert.equal(windowObject.listenerCount(CADENCE_OVERLAY_OPENED_EVENT), 2)
announceCadencePopoverOpened(windowObject, blockedRoot)
assert.equal(blockedCloseCount, 0, "the opening health group ignores its own announcement")
assert.equal(degradedCloseCount, 1, "opening one health group closes its peer")

announceCadencePopoverOpened(windowObject, {id: "legacy-overlay"})
assert.equal(blockedCloseCount, 1, "a legacy overlay closes an open health group")
assert.equal(degradedCloseCount, 2, "legacy coordination reaches every mounted group adapter")

removeBlocked()
removeDegraded()
assert.equal(windowObject.listenerCount(CADENCE_OVERLAY_OPENED_EVENT), 0)
announceCadencePopoverOpened(windowObject, {id: "after-cleanup"})
assert.equal(blockedCloseCount, 1, "teardown removes the blocked group listener")
assert.equal(degradedCloseCount, 2, "teardown removes the degraded group listener")

console.log("dashboard_health_test passed")
