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
  "both inspector and standalone hosts render the same server-owned rollup contracts",
  "saved presets and detail use two non-portalled as-child CadencePopover boundaries",
  "root trigger panel ids overlay attrs classes and server collection order stay exact",
  "review preset data-link and open-review handoffs remain immutable Phoenix contracts",
  "opening either comparison overlay closes its peer and legacy overlays without focus work",
  "same truthy prop identity stays open while changed or missing identities close",
  "Escape focus restoration resolves the current trigger after a LiveView prop patch",
  "outside dismissal closes without restoring trigger focus",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "dashboard comparison contracts use pinned Node 24.16.0",
)
assert.equal(nodeScenarioLedger.length, 8)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const inspectorPath = resolve(testDirectory, "../vue/DashboardComparisonInspector.vue")
const rollupPath = resolve(testDirectory, "../vue/DashboardComparisonRollup.vue")
const adapterPath = resolve(testDirectory, "../vue/ui/reka/CadencePopover.vue")
const overlayStylesPath = resolve(testDirectory, "../css/components/overlay.css")
const viewportSmokePath = resolve(testDirectory, "dashboard_viewport_smoke.mjs")
const presenterPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/comparison_rollup_components.ex",
)

const [
  inspectorSource,
  rollupSource,
  adapterSource,
  overlayStylesSource,
  viewportSmokeSource,
  presenterSource,
] = await Promise.all([
  readFile(inspectorPath, "utf8"),
  readFile(rollupPath, "utf8"),
  readFile(adapterPath, "utf8"),
  readFile(overlayStylesPath, "utf8"),
  readFile(viewportSmokePath, "utf8"),
  readFile(presenterPath, "utf8"),
])

const rollupScript = rollupSource.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const rollupTemplate = rollupSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(rollupScript, "DashboardComparisonRollup.vue must have a script setup block")
assert.ok(rollupTemplate, "DashboardComparisonRollup.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

const countMatches = (source, pattern) => source.match(pattern)?.length || 0

const assertInOrder = (source, fragments, message) => {
  let cursor = -1

  for (const fragment of fragments) {
    const next = source.indexOf(fragment, cursor + 1)
    assert.ok(next > cursor, `${message}: ${fragment}`)
    cursor = next
  }
}

// The immutable parent keeps the rollup in both its aside and standalone placements.
assert.match(inspectorSource, /import ClipboardButton from "\.\/ClipboardButton\.vue"/)
assert.match(
  inspectorSource,
  /import DashboardComparisonInspectorHeader from "\.\/DashboardComparisonInspectorHeader\.vue"/,
)
assert.match(
  inspectorSource,
  /import DashboardComparisonRollup from "\.\/DashboardComparisonRollup\.vue"/,
)
assert.match(inspectorSource, /presentation: \{type: Object, required: true\}/)
assert.equal(countMatches(inspectorSource, /<DashboardComparisonRollup\b/g), 2)
assert.equal(
  countMatches(
    inspectorSource,
    /<ClipboardButton v-bind="presentation\.rollup\.[^"]+\.props" \/>/g,
  ),
  4,
  "both inspector and standalone paths directly compose both clipboard controls",
)
assertInOrder(
  inspectorSource,
  [
    '<aside v-if="presentation.inspector"',
    'v-bind="presentation.inspector.body.attrs"',
    '<DashboardComparisonRollup :presentation="presentation.rollup">',
    '<DashboardComparisonRollup v-else :presentation="presentation.rollup">',
  ],
  "the aside rollup must remain ahead of the standalone rollup",
)
assert.doesNotMatch(inspectorSource, /v-component|<\.vue|data-name/)

// The rollup derives stable identities and strips only the server's initial hidden value.
assert.match(rollupScript, /import \{computed\} from "vue"/)
assert.match(rollupScript, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.match(
  rollupScript,
  /const identity = overlay\?\.root\.attrs\.id\n  return typeof identity === "string" \? identity : null/,
)
assert.match(
  rollupScript,
  /const attrs = \{\.\.\.\(overlay\?\.panel\.attrs \|\| \{}\)\}\n  delete attrs\.hidden\n  return attrs/,
)
assert.match(
  rollupScript,
  /overlayIdentity\(props\.presentation\.saved_presets\)/,
)
assert.match(
  rollupScript,
  /overlayIdentity\(props\.presentation\.details\)/,
)
assert.match(
  rollupScript,
  /overlayPanelAttrs\(props\.presentation\.saved_presets\)/,
)
assert.match(
  rollupScript,
  /overlayPanelAttrs\(props\.presentation\.details\)/,
)
assert.doesNotMatch(
  rollupScript,
  /\b(?:document|window|HTMLElement|CustomEvent|nextTick|onMounted|onUpdated|onBeforeUnmount|ref)\b/,
)
assert.doesNotMatch(
  rollupSource,
  /openOverlayId|overlayState|positionPanel|onDocumentPointerDown|onDocumentKeyDown/,
)

// Exactly two adapter instances retain the public root attrs and bottom-end geometry.
assert.equal(countMatches(rollupTemplate, /<CadencePopover\b/g), 2)
assert.equal(countMatches(rollupTemplate, /side="bottom"/g), 2)
assert.equal(countMatches(rollupTemplate, /align="end"/g), 2)
assert.equal(countMatches(rollupTemplate, /:side-offset="8"/g), 2)
assert.equal(countMatches(rollupTemplate, /:collision-padding="16"/g), 2)
assert.equal(
  countMatches(
    rollupTemplate,
    /v-bind="presentation\.(?:saved_presets|details)\.root\.attrs"/g,
  ),
  2,
)
assert.match(
  rollupTemplate,
  /<CadencePopover[\s\S]*v-if="presentation\.saved_presets"[\s\S]*:identity="savedPresetsIdentity"[\s\S]*v-bind="presentation\.saved_presets\.root\.attrs"/,
)
assert.match(
  rollupTemplate,
  /<CadencePopover[\s\S]*v-if="presentation\.details"[\s\S]*:identity="detailsIdentity"[\s\S]*v-bind="presentation\.details\.root\.attrs"/,
)
assert.equal(countMatches(rollupTemplate, /<template #trigger="\{open\}">/g), 2)
assert.equal(countMatches(rollupTemplate, /<template #content="\{open\}">/g), 2)
assert.equal(countMatches(rollupTemplate, /:aria-expanded="String\(open\)"/g), 2)
assert.equal(countMatches(rollupTemplate, /:hidden="!open"/g), 2)
assert.match(rollupTemplate, /v-bind="savedPresetsPanelAttrs"[\s\S]*:hidden="!open"/)
assert.match(rollupTemplate, /v-bind="detailsPanelAttrs"[\s\S]*:hidden="!open"/)

// Every nested node continues to spread the server-provided attrs and keys.
const requiredRollupBindings = [
  'v-bind="presentation.root.attrs"',
  'v-bind="presentation.label.attrs"',
  'v-bind="presentation.summary.attrs"',
  'v-bind="badge.attrs"',
  'v-bind="presentation.review_form.root.attrs"',
  'v-bind="presentation.review_form.payload.attrs"',
  'v-bind="presentation.review_form.button.attrs"',
  'v-bind="presentation.preset_form.root.attrs"',
  'v-bind="presentation.preset_form.field.wrapper.attrs"',
  'v-bind="presentation.preset_form.field.label.attrs"',
  'v-bind="presentation.preset_form.field.input.attrs"',
  'v-bind="presentation.preset_form.button.attrs"',
  'v-bind="presentation.saved_presets.trigger.attrs"',
  'v-bind="presentation.saved_presets.body.attrs"',
  'v-bind="item.copy.root.attrs"',
  'v-bind="item.copy.name.attrs"',
  'v-bind="item.copy.summary.attrs"',
  'v-bind="item.actions.attrs"',
  'v-bind="item.actions.apply.attrs"',
  'v-bind="item.actions.delete.attrs"',
  'v-bind="presentation.details.trigger.attrs"',
  'v-bind="presentation.details.body.attrs"',
  'v-bind="group.heading.root.attrs"',
  'v-bind="group.heading.label.attrs"',
  'v-bind="group.heading.count.attrs"',
  'v-bind="group.items_root.attrs"',
  'v-bind="item.root.attrs"',
  'v-bind="item.link.attrs"',
  'v-bind="item.handled.attrs"',
  'v-bind="item.label.attrs"',
  'v-bind="item.row.attrs"',
  'v-bind="action.attrs"',
]

for (const binding of requiredRollupBindings) {
  assert.ok(rollupTemplate.includes(binding), `missing server-owned rollup binding: ${binding}`)
}

assertInOrder(
  rollupTemplate,
  [
    'v-bind="presentation.label.attrs"',
    'v-bind="presentation.summary.attrs"',
    'v-for="badge in presentation.badges"',
    '<slot name="open-findings-copy">',
    'v-if="presentation.review_form"',
    '<slot name="preset-copy">',
    'v-if="presentation.preset_form"',
    'v-if="presentation.saved_presets"',
    'v-if="presentation.details"',
  ],
  "root children must retain their server-defined placement",
)
assertInOrder(
  rollupTemplate,
  [
    'v-for="item in presentation.saved_presets.body.items"',
    'v-bind="item.actions.apply.attrs"',
    'v-bind="item.actions.delete.attrs"',
  ],
  "saved preset rows and actions must retain server order",
)
assertInOrder(
  rollupTemplate,
  [
    'v-for="group in presentation.details.body.workflow_groups"',
    'v-for="group in presentation.details.body.groups"',
    'v-for="action in item.actions"',
  ],
  "workflow groups comparison groups and their actions must retain server order",
)
assert.equal(countMatches(rollupTemplate, /v-bind="group\.root\.attrs"/g), 2)
assert.equal(countMatches(rollupTemplate, /v-bind="item\.root\.attrs"/g), 3)
assert.doesNotMatch(rollupSource, /data-dashboard-comparison-/)
assert.doesNotMatch(rollupTemplate, /@click|@pointerdown|@keydown/)
assert.doesNotMatch(rollupSource, /data-name|phx-hook|hooks\/overlay|\bOverlay\b/)

// Freeze the full family of server-owned dashboard comparison data attributes.
const expectedDashboardComparisonAttrs = [
  "data-dashboard-comparison-coverage",
  "data-dashboard-comparison-coverage-placements",
  "data-dashboard-comparison-delta-placements",
  "data-dashboard-comparison-deltas",
  "data-dashboard-comparison-handled",
  "data-dashboard-comparison-handled-placements",
  "data-dashboard-comparison-missing",
  "data-dashboard-comparison-missing-placements",
  "data-dashboard-comparison-open",
  "data-dashboard-comparison-open-findings",
  "data-dashboard-comparison-open-findings-copy",
  "data-dashboard-comparison-open-findings-review",
  "data-dashboard-comparison-open-findings-review-request-ids",
  "data-dashboard-comparison-open-findings-review-state",
  "data-dashboard-comparison-open-placements",
  "data-dashboard-comparison-preset",
  "data-dashboard-comparison-preset-copy",
  "data-dashboard-comparison-preset-path",
  "data-dashboard-comparison-rollup",
  "data-dashboard-comparison-rollup-badge",
  "data-dashboard-comparison-rollup-compare-count",
  "data-dashboard-comparison-rollup-compare-data-management",
  "data-dashboard-comparison-rollup-compare-kind",
  "data-dashboard-comparison-rollup-compare-link",
  "data-dashboard-comparison-rollup-compare-link-target",
  "data-dashboard-comparison-rollup-compare-observables",
  "data-dashboard-comparison-rollup-compare-sample",
  "data-dashboard-comparison-rollup-contact-id",
  "data-dashboard-comparison-rollup-contact-ids",
  "data-dashboard-comparison-rollup-decision",
  "data-dashboard-comparison-rollup-decision-event",
  "data-dashboard-comparison-rollup-decision-link",
  "data-dashboard-comparison-rollup-decision-reason",
  "data-dashboard-comparison-rollup-decision-status",
  "data-dashboard-comparison-rollup-delta",
  "data-dashboard-comparison-rollup-detail",
  "data-dashboard-comparison-rollup-ground-station-id",
  "data-dashboard-comparison-rollup-group",
  "data-dashboard-comparison-rollup-group-count",
  "data-dashboard-comparison-rollup-group-handled",
  "data-dashboard-comparison-rollup-group-unhandled",
  "data-dashboard-comparison-rollup-handled",
  "data-dashboard-comparison-rollup-handoff",
  "data-dashboard-comparison-rollup-item",
  "data-dashboard-comparison-rollup-item-state",
  "data-dashboard-comparison-rollup-item-widget",
  "data-dashboard-comparison-rollup-link",
  "data-dashboard-comparison-rollup-placements",
  "data-dashboard-comparison-rollup-primary-count",
  "data-dashboard-comparison-rollup-primary-data-management",
  "data-dashboard-comparison-rollup-primary-kind",
  "data-dashboard-comparison-rollup-primary-link",
  "data-dashboard-comparison-rollup-primary-link-target",
  "data-dashboard-comparison-rollup-primary-observables",
  "data-dashboard-comparison-rollup-primary-sample",
  "data-dashboard-comparison-rollup-resource-id",
  "data-dashboard-comparison-rollup-scope-id",
  "data-dashboard-comparison-rollup-scope-ids",
  "data-dashboard-comparison-rollup-scope-kind",
  "data-dashboard-comparison-rollup-scope-link-id",
  "data-dashboard-comparison-rollup-source-endpoint-id",
  "data-dashboard-comparison-rollup-spacecraft-id",
  "data-dashboard-comparison-rollup-transport-id",
  "data-dashboard-comparison-rollup-widget-source",
  "data-dashboard-comparison-rollup-widget-type",
  "data-dashboard-comparison-rollup-workflow-decision-status",
  "data-dashboard-comparison-rollup-workflow-group",
  "data-dashboard-comparison-rollup-workflow-group-count",
  "data-dashboard-comparison-rollup-workflow-item",
  "data-dashboard-comparison-rollup-workflow-state",
  "data-dashboard-comparison-saved-preset",
  "data-dashboard-comparison-saved-preset-affected",
  "data-dashboard-comparison-saved-preset-apply",
  "data-dashboard-comparison-saved-preset-compare-view",
  "data-dashboard-comparison-saved-preset-delete",
  "data-dashboard-comparison-saved-preset-name",
  "data-dashboard-comparison-saved-preset-primary-view",
  "data-dashboard-comparison-saved-presets",
  "data-dashboard-comparison-states",
  "data-dashboard-comparison-unchanged",
  "data-dashboard-comparison-unchanged-placements",
  "data-dashboard-comparison-unhandled",
  "data-dashboard-comparison-widgets",
  "data-dashboard-comparison-workflow-badge",
]
const presenterDashboardComparisonAttrs = Array.from(
  new Set(
    Array.from(
      presenterSource.matchAll(/"(data-dashboard-comparison-[^"]+)"/g),
      (match) => match[1],
    ),
  ),
).sort()

assert.deepEqual(presenterDashboardComparisonAttrs, expectedDashboardComparisonAttrs)

// Phoenix remains authoritative for IDs, forms, actions, confirmation, navigation, and DTO state.
const requiredPresenterContracts = [
  '"id" => "dashboard-comparison-rollup"',
  '"id" => "dashboard-comparison-open-findings-review-form"',
  '"phx-submit" => "request_comparison_review"',
  '"id" => "dashboard-comparison-open-findings-review-payload"',
  '"name" => "review[open_findings]"',
  '"id" => "dashboard-comparison-preset-form"',
  '"phx-submit" => "save_comparison_preset"',
  '"id" => "dashboard-comparison-preset-name"',
  '"name" => "preset[name]"',
  '"phx-click" => "apply_comparison_preset"',
  '"phx-click" => "delete_comparison_preset"',
  '"phx-value-preset-id" => id',
  '"data-confirm" => "Delete this comparison preset?"',
  '"dashboard-comparison-saved-presets"',
  '"dashboard-comparison-rollup-detail"',
  '"id" => "#{id}-trigger"',
  '"id" => "#{id}-panel"',
  '"data-overlay-kind" => "popover"',
  '"data-overlay-placement" => "bottom-end"',
  '"class" => "cadence-overlay"',
  '"data-overlay-trigger" => ""',
  '"aria-haspopup" => "dialog"',
  '"aria-controls" => "#{id}-panel"',
  '"class" => "cadence-overlay-trigger"',
  '"data-overlay-panel" => ""',
  '"data-overlay-width" => "lg"',
  '"class" => "cadence-overlay-panel cadence-popover-panel"',
  '"hidden" => true',
  '"href" => comparison_rollup_item_href(item)',
  'do: "#widget-#{placement_id}"',
  '"phx-click" => "open_data_link"',
  "comparison_rollup_review_state(review_requested?)",
  "comparison_rollup_open_review_request_ids(assigns.open_review_summary)",
]

for (const contract of requiredPresenterContracts) {
  assert.ok(presenterSource.includes(contract), `missing server-owned comparison contract: ${contract}`)
}

assert.equal(
  countMatches(presenterSource, /\bDataLinkAttrs\.open\(/g),
  3,
  "decision handoff and both sample variants must retain DataLinkAttrs.open",
)
assert.doesNotMatch(
  rollupSource,
  /request_comparison_review|save_comparison_preset|apply_comparison_preset|delete_comparison_preset|open_data_link|data-confirm/,
)

// CadencePopover owns non-modal Reka mechanics without portals or wrapper replacements.
assert.match(
  adapterSource,
  /import \{PopoverContent, PopoverRoot, PopoverTrigger\} from "reka-ui"/,
)
assert.match(adapterSource, /defineOptions\(\{inheritAttrs: false\}\)/)
assert.match(adapterTemplate, /<div[\s\S]*ref="root"[\s\S]*v-bind="\$attrs"/)
assert.match(adapterTemplate, /:data-overlay-open="open \? '' : undefined"/)
assert.match(adapterTemplate, /<PopoverRoot[\s\S]*:open="open"[\s\S]*:modal="false"/)
assert.match(adapterTemplate, /@update:open="updateOpen"/)
assert.match(adapterTemplate, /<PopoverTrigger as-child>/)
assert.match(adapterTemplate, /<PopoverContent[\s\S]*v-if="open"[\s\S]*as-child/)
assert.match(adapterTemplate, /:side="props\.side"/)
assert.match(adapterTemplate, /:align="props\.align"/)
assert.match(adapterTemplate, /:side-offset="props\.sideOffset"/)
assert.match(adapterTemplate, /:collision-padding="props\.collisionPadding"/)
assert.match(adapterTemplate, /position-strategy="fixed"/)
assert.match(adapterTemplate, /sticky="always"/)
assert.match(adapterTemplate, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(adapterTemplate, /@interact-outside="handleInteractOutside"/)
assert.match(adapterTemplate, /<slot v-else name="content" :open="open"><\/slot>/)
assert.doesNotMatch(adapterSource, /PopoverPortal|PopoverClose|forceMount/)
assert.match(adapterSource, /subscribeToLegacyOverlayOpen/)
assert.match(adapterSource, /announceCadencePopoverOpened/)
assert.match(
  adapterSource,
  /preservesPopoverOpenState\(open\.value, previousIdentity, nextIdentity\)/,
)
assert.match(
  adapterSource,
  /const handleInteractOutside = \(event: Event\) => \{[\s\S]*trigger\?\.contains\(event\.target\)[\s\S]*event\.preventDefault\(\)[\s\S]*closeWithoutFocus\(\)\n\}/,
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
assert.match(
  overlayStylesSource,
  /\[data-reka-popper-content-wrapper\] > \.cadence-overlay-panel \{\n    position: static;/,
)

// Both prop identities keep open state only across the same truthy server identity.
for (const identity of [
  "dashboard-comparison-saved-presets",
  "dashboard-comparison-rollup-detail",
]) {
  assert.equal(preservesPopoverOpenState(true, identity, identity), true)
  assert.equal(preservesPopoverOpenState(false, identity, identity), false)
  assert.equal(preservesPopoverOpenState(true, identity, `${identity}-replacement`), false)
  assert.equal(preservesPopoverOpenState(true, identity, ""), false)
  assert.equal(preservesPopoverOpenState(true, identity, null), false)
  assert.equal(preservesPopoverOpenState(true, identity, undefined), false)
}

// Escape focus uses the currently rendered trigger after the parent replaces its DTO.
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
}

// Each comparison overlay closes its peer, and legacy overlay opens close both without focus work.
const windowObject = new FakeWindow()
const savedPresetsRoot = {id: "dashboard-comparison-saved-presets"}
const detailsRoot = {id: "dashboard-comparison-rollup-detail"}
let savedPresetsCloseCount = 0
let detailsCloseCount = 0
const removeSavedPresets = subscribeToLegacyOverlayOpen(
  windowObject,
  savedPresetsRoot,
  () => (savedPresetsCloseCount += 1),
)
const removeDetails = subscribeToLegacyOverlayOpen(
  windowObject,
  detailsRoot,
  () => (detailsCloseCount += 1),
)

announceCadencePopoverOpened(windowObject, savedPresetsRoot)
assert.equal(savedPresetsCloseCount, 0)
assert.equal(detailsCloseCount, 1, "opening saved presets must close comparison details")
announceCadencePopoverOpened(windowObject, detailsRoot)
assert.equal(savedPresetsCloseCount, 1, "opening comparison details must close saved presets")
assert.equal(detailsCloseCount, 1)
windowObject.dispatchEvent(
  new windowObject.CustomEvent(CADENCE_OVERLAY_OPENED_EVENT, {
    detail: {id: "legacy-overlay"},
  }),
)
assert.equal(savedPresetsCloseCount, 2)
assert.equal(detailsCloseCount, 2)
removeSavedPresets()
removeDetails()

// The read-only smoke oracle still observes the unchanged saved-preset public DOM.
assert.match(
  viewportSmokeSource,
  /document\.querySelector\("#dashboard-comparison-saved-presets"\)/,
)
assert.match(
  viewportSmokeSource,
  /popover\.querySelector\(":scope > \[data-overlay-trigger\]"\)\?\.click\(\)/,
)
assert.match(
  viewportSmokeSource,
  /document\.querySelector\("#dashboard-comparison-saved-presets"\)\?\.hasAttribute\("data-overlay-open"\)/,
)
assert.match(
  viewportSmokeSource,
  /!document\.querySelector\("#dashboard-comparison-saved-presets-panel"\)\?\.hidden/,
)

console.log("dashboard_comparison_inspector_test passed")
