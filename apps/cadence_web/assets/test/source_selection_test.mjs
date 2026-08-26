import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"
import {
  CADENCE_OVERLAY_OPENED_EVENT,
  announceCadencePopoverOpened,
  focusCurrentPopoverTrigger,
  preservesPopoverOpenState,
  subscribeToLegacyOverlayOpen,
} from "../vue/ui/reka/popover_compatibility.js"

const nodeScenarioLedger = [
  "one CadencePopover per selection preserves unique server identity and server order",
  "an unchanged server identity preserves open state while refreshed props render directly",
  "opening one source selection closes every other Reka or legacy overlay without focus",
  "Escape restores focus to the current trigger after a prop refresh",
  "outside dismissal closes without restoring trigger focus",
  "all public overlay panel candidate and source-selection bindings remain server-authored",
  "candidate navigation retains exact mission-scoped query href and LiveView redirect metadata",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "SourceSelection contracts use pinned Node 24.16.0",
)
assert.equal(nodeScenarioLedger.length, 7)
assert.equal(CADENCE_OVERLAY_OPENED_EVENT, "cadence:overlay-opened")

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/SourceSelection.vue")
const adapterPath = resolve(__dirname, "../vue/ui/reka/CadencePopover.vue")
const presenterPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/source_selection_components.ex",
)
const presenterTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_dashboard_show_live/source_selection_components_test.exs",
)
const sourcePresentationPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/source_presentation.ex",
)
const sourceExecutionPath = resolve(
  __dirname,
  "../../../cadence/lib/cadence/dashboards/source_request_execution.ex",
)

const [
  source,
  adapterSource,
  presenterSource,
  presenterTestSource,
  sourcePresentationSource,
  sourceExecutionSource,
] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(adapterPath, "utf8"),
  readFile(presenterPath, "utf8"),
  readFile(presenterTestPath, "utf8"),
  readFile(sourcePresentationPath, "utf8"),
  readFile(sourceExecutionPath, "utf8"),
])

const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(template, "SourceSelection.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

// Vue renders the current server DTO while CadencePopover owns every overlay mechanic.
assert.match(source, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.equal(template.match(/<CadencePopover\b/g)?.length, 1)
assert.match(template, /v-for="selection in presentation\.selections"/)
assert.match(template, /:id="selection\.overlay\.id"/)
assert.match(template, /:key="selection\.overlay\.id"/)
assert.match(template, /:identity="selection\.overlay\.id"/)
assert.match(template, /:class="selection\.overlay\.class"/)
assert.match(template, /data-overlay-kind="popover"/)
assert.match(template, /:data-overlay-placement="selection\.overlay\.placement"/)
assert.match(template, /v-bind="selection\.overlay\.attrs"/)
assert.match(template, /side="bottom"/)
assert.match(template, /align="end"/)
assert.match(template, /:side-offset="8"/)
assert.match(template, /:collision-padding="16"/)

assert.match(template, /:id="presentation\.id"/)
assert.match(template, /:class="presentation\.class"/)
assert.match(template, /v-bind="presentation\.attrs"/)
assert.match(template, /presentation\.label\.text/)
assert.match(template, /#trigger="\{open\}"/)
assert.match(template, /:id="selection\.overlay\.trigger_id"/)
assert.match(template, /data-overlay-trigger/)
assert.match(template, /aria-haspopup="dialog"/)
assert.match(template, /:aria-expanded="String\(open\)"/)
assert.match(template, /:aria-controls="selection\.overlay\.panel_id"/)
assert.match(template, /:aria-label="selection\.overlay\.label"/)
assert.match(template, /:class="selection\.overlay\.trigger_class"/)
assert.match(template, /:class="selection\.badge\.class"/)
assert.match(template, /:title="selection\.badge\.title"/)
assert.match(template, /v-bind="selection\.badge\.attrs"/)
assert.match(template, /selection\.badge\.icon\.name/)
assert.match(template, /selection\.badge\.icon\.class/)
assert.match(template, /selection\.badge\.label/)

assert.match(template, /#content="\{open\}"/)
assert.match(template, /:id="selection\.overlay\.panel_id"/)
assert.match(template, /data-overlay-panel/)
assert.match(template, /:data-overlay-width="selection\.overlay\.width"/)
assert.match(template, /:class="selection\.overlay\.panel_class"/)
assert.match(template, /:hidden="!open"/)
assert.match(template, /v-for="fact in selection\.details\.facts"/)
assert.match(template, /:key="fact\.label"/)
assert.match(template, /v-if="selection\.candidates\.length > 0"/)
assert.match(template, /v-for="candidate in selection\.candidates"/)
assert.match(template, /:key="candidate\.key"/)
assert.match(template, /:class="candidate\.class"/)
assert.match(template, /v-bind="candidate\.attrs"/)
assert.match(template, /candidate\.binding\.text/)
assert.match(template, /candidate\.data_source\.text/)
assert.match(template, /candidate\.decision\.text/)
assert.match(template, /candidate\.reason\.text/)
assert.match(template, /candidate\.window\.text/)
assert.match(
  template,
  /v-if="candidate\.action"[\s\S]*:href="candidate\.action\.href"[\s\S]*:class="candidate\.action\.class"[\s\S]*:title="candidate\.action\.title"[\s\S]*v-bind="candidate\.action\.attrs"/,
)
assert.match(template, /candidate\.action\.icon\.name/)
assert.match(template, /candidate\.action\.icon\.class/)
assert.match(template, /candidate\.action\.label/)
assert.match(template, /v-if="candidate\.product_summary"/)
assert.match(template, /v-bind="candidate\.product_summary\.attrs"/)

assert.doesNotMatch(template, /@click|@pointerdown|@keydown/)
assert.doesNotMatch(template, /\.sort\(|\.reverse\(|\[selectionIndex\]/)
assert.doesNotMatch(source, /nextTick|onMounted|onUpdated|onBeforeUnmount|ref\(/)
assert.doesNotMatch(
  source,
  /openSelectionId|positionPanel|document\.|window\.dispatchEvent|addEventListener|removeEventListener/,
)
assert.doesNotMatch(source, /cadence:overlay-opened|setTimeout|setInterval/)
assert.doesNotMatch(source, /occurrence|JSON\.stringify|new Map/)

// The read-only adapter supplies Reka open state, placement, coordination, and focus semantics.
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
assert.match(adapterTemplate, /position-strategy="fixed"/)
assert.match(adapterTemplate, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(adapterTemplate, /@interact-outside="handleInteractOutside"/)
assert.match(adapterSource, /subscribeToLegacyOverlayOpen/)
assert.match(adapterSource, /announceCadencePopoverOpened/)
assert.match(adapterSource, /preservesPopoverOpenState\(open\.value, previousIdentity, nextIdentity\)/)
assert.match(adapterSource, /focusCurrentPopoverTrigger\(currentRoot\)/)
assert.match(
  adapterSource,
  /const closeWithoutFocus = \(\) => \{[\s\S]*suppressCloseAutoFocus = true[\s\S]*open\.value = false\n\}/,
)
assert.match(
  adapterSource,
  /const handleInteractOutside = \(event: Event\) => \{[\s\S]*trigger\?\.contains\(event\.target\)[\s\S]*event\.preventDefault\(\)[\s\S]*closeWithoutFocus\(\)\n\}/,
)
assert.doesNotMatch(adapterSource, /PopoverPortal|forceMount|setTimeout|setInterval/)

// Evaluate the adapter's actual dismissal functions with minimal Vue and DOM primitives.
const behaviorStart = adapterSource.indexOf("const root = ref<HTMLElement | null>(null)")
const behaviorEnd = adapterSource.indexOf("watch(\n", behaviorStart)
assert.ok(behaviorStart >= 0 && behaviorEnd > behaviorStart, "adapter behavior is auditable")

const behaviorSource = adapterSource
  .slice(behaviorStart, behaviorEnd)
  .replace("ref<HTMLElement | null>(null)", "ref(null)")
  .replace(
    "let removeLegacyOverlayListener: (() => void) | null = null",
    "let removeLegacyOverlayListener = null",
  )
  .replace("(nextOpen: boolean)", "(nextOpen)")
  .replaceAll("(event: Event)", "(event)")
  .replace("querySelector<HTMLElement>", "querySelector")

class FakeNode {}

const behaviorContext = {
  Node: FakeNode,
  announceCadencePopoverOpened: () => {},
  focusCurrentPopoverTrigger,
  nextTick: async () => {},
  preservesPopoverOpenState,
  props: {identity: "source-selection-req-telemetry"},
  ref: (value) => ({value}),
}
vm.createContext(behaviorContext)
vm.runInContext(
  `${behaviorSource}\nglobalThis.behavior = {\n` +
    "  root, open, closeWithoutFocus, handleCloseAutoFocus, handleInteractOutside,\n" +
    "  suppressCloseAutoFocus: () => suppressCloseAutoFocus,\n" +
    "}",
  behaviorContext,
  {filename: adapterPath},
)

const behavior = behaviorContext.behavior
let staleTriggerFocusCount = 0
let currentTriggerFocusCount = 0
const staleTrigger = {
  contains: () => false,
  focus: () => (staleTriggerFocusCount += 1),
}
const currentTrigger = {
  contains: () => false,
  focus: () => (currentTriggerFocusCount += 1),
}
let renderedTrigger = staleTrigger
behavior.root.value = {
  id: "source-selection-req-telemetry",
  querySelector(selector) {
    assert.equal(selector, ":scope > [data-overlay-trigger]")
    return renderedTrigger
  },
}

assert.equal(
  preservesPopoverOpenState(
    true,
    "source-selection-req-telemetry",
    "source-selection-req-telemetry",
  ),
  true,
  "an open selection survives a DTO refresh with the same server identity",
)
assert.equal(
  preservesPopoverOpenState(
    true,
    "source-selection-req-telemetry",
    "source-selection-req-commanding",
  ),
  false,
)
assert.equal(preservesPopoverOpenState(true, "source-selection-req-telemetry", ""), false)
assert.equal(preservesPopoverOpenState(false, "source-selection-req-telemetry", ""), false)

// Escape follows Reka's close-auto-focus path and resolves the trigger from refreshed DOM.
renderedTrigger = currentTrigger
behavior.open.value = false
const escapeCloseEvent = {
  preventDefaultCount: 0,
  preventDefault() {
    this.preventDefaultCount += 1
  },
}
behavior.handleCloseAutoFocus(escapeCloseEvent)
await new Promise((resolvePromise) => setImmediate(resolvePromise))
assert.equal(escapeCloseEvent.preventDefaultCount, 1)
assert.equal(currentTriggerFocusCount, 1, "Escape focuses the current public trigger")
assert.equal(staleTriggerFocusCount, 0, "Escape never focuses a stale trigger reference")

// Outside interaction closes through the adapter without restoring trigger focus.
const outsideTarget = new FakeNode()
const outsideInteractionEvent = {
  target: outsideTarget,
  preventDefaultCount: 0,
  preventDefault() {
    this.preventDefaultCount += 1
  },
}
behavior.open.value = true
behavior.handleInteractOutside(outsideInteractionEvent)
assert.equal(outsideInteractionEvent.preventDefaultCount, 1)
assert.equal(behavior.open.value, false)
assert.equal(behavior.suppressCloseAutoFocus(), true)
behavior.open.value = false
const outsideCloseEvent = {
  preventDefaultCount: 0,
  preventDefault() {
    this.preventDefaultCount += 1
  },
}
behavior.handleCloseAutoFocus(outsideCloseEvent)
await new Promise((resolvePromise) => setImmediate(resolvePromise))
assert.equal(outsideCloseEvent.preventDefaultCount, 1)
assert.equal(currentTriggerFocusCount, 1, "outside close must not restore trigger focus")
assert.equal(behavior.suppressCloseAutoFocus(), false, "suppression resets after the close")

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

const windowObject = new FakeWindow()
const firstRoot = {id: "source-selection-req-commanding"}
const secondRoot = {id: "source-selection-req-telemetry"}
let firstCloseCount = 0
let secondCloseCount = 0
const removeFirst = subscribeToLegacyOverlayOpen(windowObject, firstRoot, () => {
  firstCloseCount += 1
})
const removeSecond = subscribeToLegacyOverlayOpen(windowObject, secondRoot, () => {
  secondCloseCount += 1
  behavior.closeWithoutFocus()
})

assert.equal(windowObject.listenerCount(CADENCE_OVERLAY_OPENED_EVENT), 2)
behavior.open.value = true
announceCadencePopoverOpened(windowObject, firstRoot)
assert.equal(firstCloseCount, 0)
assert.equal(secondCloseCount, 1, "opening one selection closes the other selection")
assert.equal(behavior.open.value, false)
assert.equal(behavior.suppressCloseAutoFocus(), true)
const coordinationCloseEvent = {preventDefault() {}}
behavior.handleCloseAutoFocus(coordinationCloseEvent)
await new Promise((resolvePromise) => setImmediate(resolvePromise))
assert.equal(currentTriggerFocusCount, 1, "coordination performs no focus restoration")

announceCadencePopoverOpened(windowObject, {id: "legacy-dashboard-overlay"})
assert.equal(firstCloseCount, 1, "legacy overlay coordination closes the Reka selection")
assert.equal(secondCloseCount, 2)
assert.equal(currentTriggerFocusCount, 1)

removeFirst()
removeSecond()
assert.equal(windowObject.listenerCount(CADENCE_OVERLAY_OPENED_EVENT), 0)

// Production selections are unique by construction, so public overlay ID is the stable Vue key.
assert.match(
  sourceExecutionSource,
  /defp source_selection_by_request_id\(source_results\) do[\s\S]*Enum\.reduce\(%\{\}[\s\S]*Map\.put\(acc, source_request\.request_id, selection\)/,
)
assert.match(
  sourcePresentationSource,
  /context_value\(:source_selection_by_request_id, %\{\}\)[\s\S]*selections when is_map\(selections\)[\s\S]*Enum\.map\(fn \{request_id, selection\}[\s\S]*source_selection_summary\(request_id, selection\)[\s\S]*Enum\.sort_by\(& &1\.request_id\)/,
)
assert.match(presenterSource, /overlay_id = "source-selection-#\{request_id\}"/)
assert.match(presenterSource, /selections: Enum\.map\(selections, &source_selection_dto\(&1, mission_id\)\)/)
assert.match(
  presenterSource,
  /Map\.get\(:candidates, \[\]\)[\s\S]*Enum\.with_index\(\)[\s\S]*source_selection_candidate_dto\(candidate, mission_id, index\)/,
)
assert.match(presenterSource, /key: "source-selection-candidate-#\{index\}"/)

// The read-only Phoenix presenter and its focused test pin the exact host and public bindings.
assert.match(presenterSource, /id="dashboard-source-selection-component"/)
assert.match(presenterSource, /v-component="SourceSelection"/)
assert.match(presenterSource, /presentation=\{@source_selection_presentation\}/)
assert.match(presenterSource, /v-ssr=\{false\}/)
assert.match(presenterSource, /class="contents"/)
assert.match(presenterSource, /:if=\{@selections != \[\]\}/)
assert.match(presenterSource, /id: "dashboard-source-selection"/)
assert.match(presenterSource, /"data-source-selection-requests"/)
assert.match(presenterSource, /"data-source-selection-request-ids"/)
assert.match(presenterSource, /"data-source-selection-bindings"/)
assert.match(presenterSource, /"data-source-selection-data-sources"/)
assert.match(presenterSource, /"data-source-selection-rejected"/)
assert.match(presenterSource, /trigger_id: "#\{overlay_id\}-trigger"/)
assert.match(presenterSource, /panel_id: "#\{overlay_id\}-panel"/)
assert.match(presenterSource, /placement: "bottom-end"/)
assert.match(presenterSource, /width: "lg"/)
assert.match(presenterSource, /"data-source-selection-detail" => request_id/)
assert.match(presenterSource, /"data-source-selection" => request_id/)
assert.match(presenterSource, /"data-source-selection-state"/)
assert.match(presenterSource, /"data-source-selection-logical-source"/)
assert.match(presenterSource, /"data-source-selection-binding"/)
assert.match(presenterSource, /"data-source-selection-data-source"/)
assert.match(presenterSource, /"data-source-selection-candidates"/)
assert.match(presenterSource, /"data-source-selection-eligible"/)
assert.match(presenterSource, /"data-source-selection-rejected"/)
assert.match(presenterSource, /"data-source-selection-candidate" => binding_id/)
assert.match(presenterSource, /"data-source-selection-candidate-source" => data_source_id/)
assert.match(presenterSource, /"data-source-selection-candidate-decision"/)
assert.match(presenterSource, /"data-source-selection-candidate-reasons"/)
assert.match(presenterSource, /"data-source-selection-candidate-window"/)
assert.match(presenterSource, /"data-source-selection-candidate-health"/)
assert.match(presenterSource, /"data-source-selection-candidate-freshness"/)
assert.match(presenterSource, /"data-source-selection-candidate-requested-products"/)
assert.match(presenterSource, /"data-source-selection-candidate-supported-products"/)
assert.match(presenterSource, /"data-source-selection-candidate-missing-products"/)
assert.match(presenterSource, /"data-source-selection-candidate-action"/)
assert.match(presenterSource, /"data-source-selection-candidate-action-query"/)
assert.match(presenterSource, /href: href/)
assert.match(presenterSource, /class: "btn btn-ghost btn-xs gap-1"/)
assert.match(presenterSource, /"data-phx-link" => "redirect"/)
assert.match(presenterSource, /"data-phx-link-state" => "push"/)
assert.match(presenterSource, /"data-source-selection-candidate-open"/)
assert.match(
  presenterSource,
  /~p"\/missions\/#\{mission_id\}\/ops\/data-sources\?#\{query\}"/,
)

assert.match(presenterTestSource, /vue\.id == "dashboard-source-selection-component"/)
assert.match(presenterTestSource, /presentation\["id"\] == "dashboard-source-selection"/)
assert.match(presenterTestSource, /selection\["overlay"\]\["id"\] == "source-selection-req-telemetry"/)
assert.match(
  presenterTestSource,
  /selection\["overlay"\]\["trigger_id"\] == "source-selection-req-telemetry-trigger"/,
)
assert.match(
  presenterTestSource,
  /selection\["overlay"\]\["panel_id"\] == "source-selection-req-telemetry-panel"/,
)
assert.match(
  presenterTestSource,
  /"data-phx-link" => "redirect"[\s\S]*"data-phx-link-state" => "push"[\s\S]*"data-source-selection-candidate-open" => "primary-flight"/,
)
assert.match(presenterTestSource, /primary_href =~ "\/missions\/mission-1\/ops\/data-sources\?"/)
assert.match(presenterTestSource, /primary_href =~ "data_source_id=primary-questdb"/)
assert.match(presenterTestSource, /primary_href =~ "source_binding_id=primary-flight"/)

console.log("source_selection_test passed")
