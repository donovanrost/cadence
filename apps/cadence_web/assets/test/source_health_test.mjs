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
  "one CadencePopover per source preserves server order presentation objects and keys",
  "public duplicate root trigger and panel ids remain intentionally duplicated",
  "open state follows overlay id plus duplicate occurrence across prop refreshes",
  "empty health remains a server-owned no-island case",
  "every source-health open_evidence payload passes through unchanged",
  "bottom-end non-modal dialog placement keeps eight pixel offset and sixteen pixel collision",
  "opening one source closes every other Reka or legacy overlay without restoring focus",
  "outside dismissal suppresses focus while Escape resolves the current public trigger",
]

assert.equal(process.versions.node, "24.16.0", "SourceHealth contracts use pinned Node 24.16.0")
assert.equal(nodeScenarioLedger.length, 8)
assert.equal(CADENCE_OVERLAY_OPENED_EVENT, "cadence:overlay-opened")

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/SourceHealth.vue")
const adapterPath = resolve(__dirname, "../vue/ui/reka/CadencePopover.vue")
const presenterPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/source_health_components.ex",
)
const evidenceAttrsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/evidence_attrs.ex",
)
const presenterTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_dashboard_show_live/source_health_components_test.exs",
)

const [source, adapterSource, presenterSource, evidenceAttrsSource, presenterTestSource] =
  await Promise.all([
    readFile(componentPath, "utf8"),
    readFile(adapterPath, "utf8"),
    readFile(presenterPath, "utf8"),
    readFile(evidenceAttrsPath, "utf8"),
    readFile(presenterTestPath, "utf8"),
  ])
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(template, "SourceHealth.vue must have a template block")
assert.ok(adapterTemplate, "CadencePopover.vue must have a template block")

// Vue only renders the server DTO; CadencePopover owns all overlay mechanics.
assert.match(source, /import \{computed\} from "vue"/)
assert.match(source, /import CadencePopover from "\.\/ui\/reka\/CadencePopover\.vue"/)
assert.equal(template.match(/<CadencePopover\b/g)?.length, 1)
assert.match(template, /:id="presentation\.root\.id"/)
assert.match(template, /:class="presentation\.root\.class"/)
assert.match(template, /v-bind="presentation\.root\.attrs"/)
assert.match(template, /v-for="entry in popoverEntries"/)
assert.match(template, /:id="entry\.source\.overlay\.id"/)
assert.match(template, /:key="entry\.key"/)
assert.match(template, /:identity="entry\.source\.overlay\.id"/)
assert.match(template, /:class="entry\.source\.overlay\.class"/)
assert.match(template, /v-bind="entry\.source\.overlay\.attrs"/)
assert.match(template, /side="bottom"/)
assert.match(template, /align="end"/)
assert.match(template, /:side-offset="8"/)
assert.match(template, /:collision-padding="16"/)

assert.match(template, /:id="entry\.source\.trigger\.id"/)
assert.match(template, /:type="entry\.source\.trigger\.type"/)
assert.match(template, /:class="entry\.source\.trigger\.class"/)
assert.match(template, /v-bind="entry\.source\.trigger\.attrs"/)
assert.match(template, /:aria-expanded="String\(open\)"/)
assert.match(template, /v-bind="entry\.source\.badge\.attrs"/)
assert.match(template, /:id="entry\.source\.panel\.id"/)
assert.match(template, /:class="entry\.source\.panel\.class"/)
assert.match(
  template,
  /v-bind="entry\.source\.panel\.attrs"[\s\S]*:hidden="!open"/,
)
assert.match(template, /v-if="entry\.source\.details\.circuit\.visible"/)
assert.match(template, /v-bind="entry\.source\.details\.evidence\.attrs"/)
assert.match(template, /v-bind="row\.value\.attrs"/)
assert.match(template, /:key="row\.key"/)
assert.doesNotMatch(template, /@click|@pointerdown|@keydown/)
assert.doesNotMatch(template, /open_evidence|Source status|Inspect evidence|badge-/)
assert.doesNotMatch(
  source,
  /createSourceHealthController|SOURCE_HEALTH_CONTROLLER|addEventListener|removeEventListener/,
)
assert.doesNotMatch(source, /onMounted|onBeforeUpdate|onUpdated|onBeforeUnmount/)
assert.doesNotMatch(source, /cadence:overlay-opened|setTimeout|setInterval|<script(?! setup)/)

// Local keys model the precise public-ID occurrence while leaving source objects untouched.
const entriesStartMarker = "// SOURCE_HEALTH_POPOVER_ENTRIES_START"
const entriesEndMarker = "// SOURCE_HEALTH_POPOVER_ENTRIES_END"
const entriesStart = source.indexOf(entriesStartMarker)
const entriesEnd = source.indexOf(entriesEndMarker)
assert.ok(entriesStart >= 0 && entriesEnd > entriesStart, "occurrence identity remains auditable")

const entriesSource = source
  .slice(entriesStart + entriesStartMarker.length, entriesEnd)
  .replace("(sources: SourcePresentation[])", "(sources)")
  .replace("new Map<string, number>()", "new Map()")

assert.match(entriesSource, /occurrenceByOverlayId\.get\(source\.overlay\.id\) \?\? 0/)
assert.match(entriesSource, /JSON\.stringify\(\[source\.overlay\.id, occurrence\]\)/)
assert.doesNotMatch(entriesSource, /source\.key\s*=|source\.order\s*=|\.sort\(|\.reverse\(/)
assert.doesNotMatch(entriesSource, /replace\(|normalize|slug/i)

const entriesContext = {}
vm.createContext(entriesContext)
vm.runInContext(
  `${entriesSource}\nglobalThis.sourceHealthPopoverEntries = sourceHealthPopoverEntries`,
  entriesContext,
  {filename: componentPath},
)

const sourceHealthPopoverEntries = entriesContext.sourceHealthPopoverEntries
assert.equal(typeof sourceHealthPopoverEntries, "function")

const duplicateId = "source-health-request-a-default"
const sources = [
  {key: "server-key-a", order: 0, overlay: {id: duplicateId}},
  {key: "server-key-b", order: 1, overlay: {id: "source-health-request-b-ds-b"}},
  {key: "server-key-c", order: 2, overlay: {id: duplicateId}},
]
const entries = Array.from(sourceHealthPopoverEntries(sources))

assert.deepEqual(entries.map((entry) => entry.source), sources)
assert.deepEqual(entries.map((entry) => entry.source.key), sources.map((item) => item.key))
assert.deepEqual(entries.map((entry) => entry.source.order), [0, 1, 2])
assert.deepEqual(entries.map((entry) => entry.source.overlay.id), [
  duplicateId,
  "source-health-request-b-ds-b",
  duplicateId,
])
assert.deepEqual(entries.map((entry) => entry.occurrence), [0, 0, 1])
assert.deepEqual(entries.map((entry) => entry.key), [
  JSON.stringify([duplicateId, 0]),
  JSON.stringify(["source-health-request-b-ds-b", 0]),
  JSON.stringify([duplicateId, 1]),
])

const openKey = entries[2].key
const refreshedSources = [
  {key: "server-key-b-next", order: 0, overlay: {id: "source-health-request-b-ds-b"}},
  {key: "server-key-a-next", order: 1, overlay: {id: duplicateId}},
  {key: "server-key-c-next", order: 2, overlay: {id: duplicateId}},
]
const refreshedEntries = Array.from(sourceHealthPopoverEntries(refreshedSources))
assert.equal(
  refreshedEntries[2].key,
  openKey,
  "the second duplicate remains open even when another public ID moves",
)
assert.equal(
  refreshedEntries.some((entry) => entry.key === openKey),
  true,
  "the same public ID occurrence survives a DTO refresh",
)
assert.equal(
  Array.from(sourceHealthPopoverEntries(refreshedSources.slice(0, 2))).some(
    (entry) => entry.key === openKey,
  ),
  false,
  "removing the open duplicate occurrence removes its local identity",
)

// The read-only presenter pins the island boundary, public IDs, ordering, and payload source.
assert.match(
  presenterSource,
  /def source_health_strip\(%\{health: \[_source \| _\] = health\} = assigns\)/,
)
assert.match(presenterSource, /def source_health_strip\(assigns\), do: ~H""/)
assert.match(presenterSource, /id="dashboard-source-health-component"/)
assert.match(presenterSource, /v-component="SourceHealth"/)
assert.match(presenterSource, /presentation=\{@presentation\}/)
assert.match(presenterSource, /v-ssr=\{false\}/)
assert.match(presenterSource, /class="contents"/)
assert.match(presenterSource, /health[\s\S]*\|> Enum\.with_index\(\)[\s\S]*source_health_source_dto/)
assert.match(presenterSource, /key: "#\{overlay_id\}-#\{index\}"/)
assert.match(presenterSource, /id: "#\{overlay_id\}-trigger"/)
assert.match(presenterSource, /"aria-controls" => "#\{overlay_id\}-panel"/)
assert.match(presenterSource, /id: "#\{overlay_id\}-panel"/)
assert.match(presenterSource, /"aria-haspopup" => "dialog"/)
assert.match(presenterSource, /placement: "bottom-end"/)
assert.match(presenterSource, /"data-overlay-placement" => "bottom-end"/)
assert.match(
  presenterSource,
  /request_id = Map\.get\(source, :request_id\) \|\| Map\.get\(source, :logical_source_text\)/,
)
assert.match(
  presenterSource,
  /data_source_id = Map\.get\(source, :data_source_id\) \|\| "default"/,
)
assert.match(
  presenterSource,
  /"source-health-#\{text_value\(request_id\)\}-#\{text_value\(data_source_id\)\}"/,
)

const duplicateOracleEnd = presenterTestSource.indexOf(
  '  test "source health strip renders no island for an empty health list"',
)
const duplicateOracleSource = presenterTestSource.slice(0, duplicateOracleEnd)
assert.ok(duplicateOracleEnd > 0, "the duplicate public-ID oracle remains auditable")
assert.equal(
  duplicateOracleSource.match(
    /"key" => "source-health-req-telemetry-questdb-flight-[01]"/g,
  )?.length,
  2,
)
for (const publicId of [
  "source-health-req-telemetry-questdb-flight",
  "source-health-req-telemetry-questdb-flight-trigger",
  "source-health-req-telemetry-questdb-flight-panel",
]) {
  assert.equal(
    duplicateOracleSource.match(new RegExp(`"id" => "${publicId}"`, "g"))?.length,
    2,
    `${publicId} remains intentionally duplicated`,
  )
}
assert.match(
  presenterTestSource,
  /test "source health strip renders no island for an empty health list"[\s\S]*LazyHTML\.query\("#dashboard-source-health-component"\)[\s\S]*LazyHTML\.attribute\("id"\)/,
)

const evidenceStart = evidenceAttrsSource.indexOf("  def source_health(source) when is_map(source) do")
const evidenceEnd = evidenceAttrsSource.indexOf("  def source_health(_source), do: %{}", evidenceStart)
assert.ok(evidenceStart >= 0 && evidenceEnd > evidenceStart, "source evidence registry is auditable")
const evidenceSource = evidenceAttrsSource.slice(evidenceStart, evidenceEnd)
const evidenceKeys = Array.from(
  evidenceSource.matchAll(/"([^"]+)" =>/g),
  (match) => `phx-value-${match[1]}`,
)
assert.deepEqual(evidenceKeys, [
  "phx-value-kind",
  "phx-value-source-evidence-mode",
  "phx-value-source-request-id",
  "phx-value-logical-source",
  "phx-value-realm",
  "phx-value-data-source-id",
  "phx-value-source-binding-id",
  "phx-value-source-health-event-id",
  "phx-value-source-health-reason",
  "phx-value-source-health-probe-kind",
  "phx-value-source-health-probe-message",
  "phx-value-source-health-probe-metadata",
])
assert.match(presenterSource, /EvidenceAttrs\.source_health\(\)/)
assert.match(presenterSource, /"phx-click" => "open_evidence"/)
assert.match(presenterSource, /"data-source-evidence-open" => ""/)

// The read-only adapter supplies Reka placement, coordination, and focus semantics.
assert.match(
  adapterSource,
  /import \{PopoverContent, PopoverRoot, PopoverTrigger\} from "reka-ui"/,
)
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

assert.equal(preservesPopoverOpenState(true, duplicateId, duplicateId), true)
assert.match(adapterSource, /suppressEscapeDismiss = true/)
assert.match(adapterSource, /!nextOpen && suppressEscapeDismiss/)
assert.equal(preservesPopoverOpenState(false, duplicateId, duplicateId), false)
assert.equal(preservesPopoverOpenState(true, duplicateId, "source-health-other-default"), false)
assert.equal(preservesPopoverOpenState(true, duplicateId, ""), false)
assert.equal(preservesPopoverOpenState(true, duplicateId, null), false)

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
const firstDuplicateRoot = {id: duplicateId}
const secondDuplicateRoot = {id: duplicateId}
let firstCloseCount = 0
let secondCloseCount = 0
const removeFirst = subscribeToLegacyOverlayOpen(
  windowObject,
  firstDuplicateRoot,
  () => (firstCloseCount += 1),
)
const removeSecond = subscribeToLegacyOverlayOpen(
  windowObject,
  secondDuplicateRoot,
  () => (secondCloseCount += 1),
)

announceCadencePopoverOpened(windowObject, firstDuplicateRoot)
assert.equal(firstCloseCount, 0, "an opening duplicate ignores its own element announcement")
assert.equal(secondCloseCount, 1, "the other duplicate closes without public-ID normalization")

announceCadencePopoverOpened(windowObject, {id: "legacy-overlay"})
assert.equal(firstCloseCount, 1, "legacy global coordination closes the open source")
assert.equal(secondCloseCount, 2)
removeFirst()
removeSecond()
announceCadencePopoverOpened(windowObject, {id: "after-cleanup"})
assert.equal(firstCloseCount, 1, "teardown removes the first compatibility listener")
assert.equal(secondCloseCount, 2, "teardown removes the second compatibility listener")

console.log("source_health_test passed")
