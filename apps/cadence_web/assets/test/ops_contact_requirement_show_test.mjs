import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = [
  "the opportunity control uses one wrapper-free CadenceToggle",
  "the server DTO remains the only source of pressed state",
  "a toggle request emits the exact Phoenix event and snapshot payload without local mutation",
  "the original button ID class aria label disabled state and checkmark stay exact",
  "the opportunity stream row identity and selected row class stay exact",
  "every non-toggle form action navigation and presentation binding stays byte-pinned",
  "Phoenix MapSet membership remains the selection authority",
  "Phoenix retains the exact toggle action DTO and LiveVue forwarding contract",
  "the focused ExUnit selection and disabled-state scenarios stay byte-pinned",
  "the requirement route remains in the authenticated current-scope Ops live session",
  "Reka UI remains locked to the reviewed Toggle export and implementation version",
]

assert.equal(
  process.versions.node,
  "24.16.0",
  "Ops Contact Requirement Show contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 11)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  component: resolve(__dirname, "../vue/OpsContactRequirementShow.vue"),
  presenter: resolve(
    __dirname,
    "../../lib/cadence_web/live/ops_contact_requirement_show_live.ex",
  ),
  presenterTest: resolve(
    __dirname,
    "../../test/cadence_web/live/ops_contact_requirements_live_test.exs",
  ),
  router: resolve(__dirname, "../../lib/cadence_web/router.ex"),
  packageLock: resolve(__dirname, "../../package-lock.json"),
}

const [source, presenterSource, presenterTestSource, routerSource, packageLockSource] =
  await Promise.all(Object.values(paths).map((path) => readFile(path, "utf8")))

const sourceSlice = (sourceText, start, end, label) => {
  const startIndex = sourceText.indexOf(start)
  const endIndex = sourceText.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return sourceText.slice(startIndex, endIndex)
}

const inclusiveSourceSlice = (sourceText, start, end, label) => {
  const slice = sourceSlice(sourceText, start, end, label)
  return `${slice}${end}`
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex")
const cadencePanelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const occurrences = (sourceText, needle) => sourceText.split(needle).length - 1

const reconstructPanelBase = (migratedSource, expectedPanels) => {
  let sourceText = migratedSource.replace(cadencePanelImport, "")
  let reconstructedPanels = 0

  while (sourceText.includes("<CadencePanel")) {
    const panelStart = sourceText.indexOf("<CadencePanel")
    const lineStart = sourceText.lastIndexOf("\n", panelStart) + 1
    const panelIndent = sourceText.slice(lineStart, panelStart)
    const panelOpenEnd = sourceText.indexOf(">", panelStart) + 1
    const panelOpen = sourceText.slice(panelStart, panelOpenEnd)
    const inlineHeaderClass = panelOpen.match(/ header-class="([^"]+)">$/)
    const multilineHeaderClass = panelOpen.match(/\n([ \t]*)header-class="([^"]+)"\n[ \t]*>$/)

    assert.ok(
      inlineHeaderClass || multilineHeaderClass,
      "each CadencePanel opening must carry one reconstructable header-class",
    )

    const headerClass = inlineHeaderClass?.[1] ?? multilineHeaderClass[2]
    const baseOpen = inlineHeaderClass
      ? panelOpen
          .replace("<CadencePanel", "<section")
          .replace(` header-class="${headerClass}"`, "")
      : panelOpen
          .replace("<CadencePanel", "<section")
          .replace(`${multilineHeaderClass[1]}header-class="${headerClass}"\n`, "")
    const slotIndent = `${panelIndent}  `
    const slotOpen = `${slotIndent}<template #header>`
    const slotStart = sourceText.indexOf(slotOpen, panelOpenEnd)
    const slotEnd = slotStart + slotOpen.length
    const slotClose = `\n${slotIndent}</template>`
    const slotCloseStart = sourceText.indexOf(slotClose, slotEnd)
    const slotCloseEnd = slotCloseStart + slotClose.length
    const panelClose = `\n${panelIndent}</CadencePanel>`
    const panelCloseStart = sourceText.indexOf(panelClose, slotCloseEnd)
    const panelCloseEnd = panelCloseStart + panelClose.length

    assert.notEqual(slotStart, -1, "each CadencePanel must open an immediate header slot")
    assert.notEqual(slotCloseStart, -1, "each CadencePanel header slot must close")
    assert.notEqual(panelCloseStart, -1, "each CadencePanel must close")

    sourceText =
      sourceText.slice(0, panelStart) +
      baseOpen +
      sourceText.slice(panelOpenEnd, slotStart) +
      `${slotIndent}<div class="${headerClass}">` +
      sourceText.slice(slotEnd, slotCloseStart) +
      `\n${slotIndent}</div>` +
      sourceText.slice(slotCloseEnd, panelCloseStart) +
      `\n${panelIndent}</section>` +
      sourceText.slice(panelCloseEnd)

    reconstructedPanels += 1
  }

  assert.equal(reconstructedPanels, expectedPanels, "all expected panels must reconstruct")
  assert.equal(
    occurrences(sourceText, "CadencePanel"),
    0,
    "reconstruction must remove CadencePanel",
  )
  return sourceText
}

const script = source.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "OpsContactRequirementShow.vue keeps an auditable TypeScript setup block")
assert.ok(template, "OpsContactRequirementShow.vue keeps an auditable template block")
assert.match(script, /^import CadenceToggle from "\.\/ui\/reka\/CadenceToggle\.vue"$/m)
assert.doesNotMatch(script, /from "reka-ui"/)
assert.doesNotMatch(source, /ToggleRoot/)
assert.equal(template.match(/<CadenceToggle\b/g)?.length, 1)
assert.equal(template.match(/<\/CadenceToggle>/g)?.length, 1)

const opportunityRow = sourceSlice(
  template,
  '            <div\n              v-for="opportunity in opportunities"',
  '          <div class="flex items-center justify-between gap-4 border-t border-base-300 bg-base-200/50 px-4 py-3">',
  "opportunity stream row",
)
const toggleMarkup = inclusiveSourceSlice(
  source,
  "              <CadenceToggle\n",
  "              </CadenceToggle>",
  "opportunity CadenceToggle",
)

assert.match(opportunityRow, /:id="opportunity\.__dom_id"/)
assert.match(opportunityRow, /:key="opportunity\.contact_opportunity_snapshot_id"/)
assert.match(
  opportunityRow,
  /opportunity\.selected && 'bg-primary\/\[0\.06\]'/,
)
assert.equal(toggleMarkup.match(/<button\b/g)?.length, 1)
assert.match(
  toggleMarkup,
  /<CadenceToggle\n\s+:pressed="opportunity\.selected"\n\s+:disabled="opportunity\.toggle_action\.disabled"\n\s+@request-change="toggleOpportunity\(opportunity\)"/,
)
assert.equal(toggleMarkup.match(/@request-change=/g)?.length, 1)
assert.match(toggleMarkup, /:id="opportunity\.toggle_action\.id"/)
assert.match(toggleMarkup, /type="button"/)
assert.match(toggleMarkup, /:disabled="opportunity\.toggle_action\.disabled"/)
assert.match(toggleMarkup, /:aria-label="opportunity\.toggle_action\.aria_label"/)
assert.match(toggleMarkup, /'h-5 w-5 border text-center font-mono text-xs'/)
assert.match(
  toggleMarkup,
  /opportunity\.selected && 'border-primary bg-primary text-primary-content'/,
)
assert.match(toggleMarkup, /!opportunity\.selected && 'border-base-content\/30'/)
assert.match(toggleMarkup, /!opportunity\.eligible && 'cursor-not-allowed opacity-30'/)
assert.match(toggleMarkup, /\{\{ opportunity\.selected \? "✓" : "" \}\}/)
assert.doesNotMatch(toggleMarkup, /@click|@update:model-value|v-model|\bas-child\b/)

// Normalize only the reviewed import and toggle subtree back to the pre-migration marker.
// Its hash proves the rest of this large component is byte-for-byte unchanged.
const normalizedComponentScaffold = reconstructPanelBase(source, 4)
  .replace('import CadenceToggle from "./ui/reka/CadenceToggle.vue"\n\n', "")
  .replace(toggleMarkup, "              <!-- opportunity-toggle -->")

assert.equal(
  sha256(normalizedComponentScaffold),
  "996123e781590ef6828c80214a9ead3bc46e8d553ae1199c7fc1cd5625ce9a9f",
  "every non-toggle OpsContactRequirementShow binding remains byte-pinned",
)

assert.doesNotMatch(source, /\bv-model(?::model-value)?=/)
assert.doesNotMatch(script, /\b(?:computed|reactive|ref|watch)\s*\(/)
assert.doesNotMatch(script, /opportunity\.selected\s*=|selected\.value\s*=/)

const toggleOpportunitySource = sourceSlice(
  script,
  "const toggleOpportunity = (opportunity: Opportunity) => {",
  "\n\nconst createPlan",
  "toggleOpportunity emitter",
)

assert.equal(toggleOpportunitySource.match(/\bemit\(/g)?.length, 1)
assert.match(
  toggleOpportunitySource,
  /emit\("toggle-opportunity", opportunity\.toggle_action\.payload\)/,
)
assert.doesNotMatch(toggleOpportunitySource, /if\s*\(|return|selected\s*=|\.selected\s*=/)

const emissions = []
const behaviorContext = vm.createContext({
  emit: (...args) => emissions.push(args),
})
const executableToggleOpportunitySource = toggleOpportunitySource.replace(
  "(opportunity: Opportunity)",
  "(opportunity)",
)

vm.runInContext(
  `${executableToggleOpportunitySource}\nglobalThis.toggleOpportunity = toggleOpportunity`,
  behaviorContext,
  {filename: paths.component},
)

for (const selected of [false, true]) {
  const payload = Object.freeze({snapshot_id: "snapshot-server-1"})
  const opportunity = Object.freeze({
    selected,
    toggle_action: Object.freeze({payload}),
  })

  behaviorContext.toggleOpportunity(opportunity)
  assert.equal(opportunity.selected, selected, "the client never mutates server selection")
  assert.strictEqual(
    emissions.at(-1)[1],
    payload,
    "the exact server-authored action payload is forwarded",
  )
}

assert.deepEqual(emissions, [
  ["toggle-opportunity", {snapshot_id: "snapshot-server-1"}],
  ["toggle-opportunity", {snapshot_id: "snapshot-server-1"}],
])

const presenterMount = sourceSlice(
  presenterSource,
  '  def mount(%{"contact_requirement_id" => requirement_id}, _session, socket) do',
  '\n  @impl true\n  def handle_event("plan"',
  "presenter mount",
)
const presenterToggle = sourceSlice(
  presenterSource,
  '  def handle_event("toggle-opportunity", %{"snapshot_id" => snapshot_id}, socket) do',
  '\n  def handle_event("create-plan"',
  "presenter toggle handler",
)
const presenterHost = sourceSlice(
  presenterSource,
  "  @impl true\n  def render(assigns) do",
  "\n  defp load_requirement",
  "presenter LiveVue host",
)
const presenterOpportunityDto = sourceSlice(
  presenterSource,
  "  defp opportunity_rows(opportunities, selected_snapshot_ids) do",
  "\n  defp requirements_path",
  "presenter opportunity DTO",
)
const presenterContract = [
  presenterMount,
  presenterToggle,
  presenterHost,
  presenterOpportunityDto,
].join("\n-- pinned presenter slice --\n")

assert.equal(
  sha256(presenterContract),
  "6b829a28bb14b03ae45f4f48fc9fc307f952d27aa70893f3ee2be8b8afd297af",
  "the read-only Phoenix presenter contract remains byte-pinned",
)
assert.match(presenterMount, /dom_id: &"planning-opportunity-#\{&1\.contact_opportunity_snapshot_id\}"/)
assert.match(presenterMount, /assign\(:selected_snapshot_ids, MapSet\.new\(\)\)/)
assert.match(presenterToggle, /MapSet\.member\?\(selected, snapshot_id\)/)
assert.match(presenterToggle, /do: MapSet\.delete\(selected, snapshot_id\)/)
assert.match(presenterToggle, /else: MapSet\.put\(selected, snapshot_id\)/)
assert.match(presenterToggle, /opportunity_rows\(socket\.assigns\.opportunities, selected\)/)
assert.match(presenterToggle, /reset: true/)
assert.match(presenterHost, /v-on:toggle-opportunity=\{JS\.push\("toggle-opportunity"\)\}/)
assert.match(presenterHost, /opportunities=\{@streams\.opportunities\}/)
assert.match(presenterOpportunityDto, /selected: MapSet\.member\?\(selected_snapshot_ids, snapshot_id\)/)
assert.match(presenterOpportunityDto, /id: "toggle-#\{snapshot_id\}"/)
assert.match(presenterOpportunityDto, /event: "toggle-opportunity"/)
assert.match(presenterOpportunityDto, /payload: %\{snapshot_id: snapshot_id\}/)
assert.match(presenterOpportunityDto, /disabled: not snapshot\.eligible/)
assert.match(presenterOpportunityDto, /aria_label: "Toggle opportunity selection"/)

const selectionExUnit = sourceSlice(
  presenterTestSource,
  '  test "Requirement detail preserves exact opportunity selection and draft Plan construction" do',
  '\n  test "Requirement detail keeps terminal requirements and ineligible opportunities disabled" do',
  "selection ExUnit scenario",
)
const disabledExUnit = sourceSlice(
  presenterTestSource,
  '  test "Requirement detail keeps terminal requirements and ineligible opportunities disabled" do',
  '\n  test "Requirement detail renders the exact asynchronous planner error" do',
  "disabled opportunity ExUnit scenario",
)

assert.equal(
  sha256(`${selectionExUnit}\n-- pinned ExUnit slice --\n${disabledExUnit}`),
  "21decc9dc51389e7666a880a7d335bf3966cba885f384c66f70d342aae542420",
  "the read-only focused ExUnit contracts remain byte-pinned",
)
assert.match(selectionExUnit, /"__dom_id" => "planning-opportunity-#\{snapshot\.contact_opportunity_snapshot_id\}"/)
assert.match(selectionExUnit, /"selected" => false/)
assert.match(selectionExUnit, /"id" => "toggle-#\{snapshot\.contact_opportunity_snapshot_id\}"/)
assert.match(selectionExUnit, /"event" => "toggle-opportunity"/)
assert.match(selectionExUnit, /"payload" => %\{"snapshot_id" => snapshot\.contact_opportunity_snapshot_id\}/)
assert.match(selectionExUnit, /render_hook\(view, "toggle-opportunity", %\{/)
assert.match(selectionExUnit, /selected_opportunity = put_in\(expected_opportunity\["selected"\], true\)/)
assert.match(selectionExUnit, /\["upsert", "\/opportunities\/-", selected_opportunity\]/)
assert.match(disabledExUnit, /assert opportunity_row\["eligible"\] == false/)
assert.match(disabledExUnit, /assert opportunity_row\["selected"\] == false/)
assert.match(disabledExUnit, /assert opportunity_row\["toggle_action"\]\["disabled"\] == true/)

const authenticatedScope = sourceSlice(
  routerSource,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  '\n  scope "/api", CadenceWeb do',
  "authenticated browser scope",
)
const opsLiveSession = sourceSlice(
  authenticatedScope,
  "    live_session :ops,",
  "\n    live_session :ops_admin,",
  "Ops live session",
)

assert.match(authenticatedScope, /pipe_through \[:browser, :require_authenticated_scope\]/)
assert.match(opsLiveSession, /\{CadenceWeb\.OrganizationAuth, :require_organization_scope\}/)
assert.match(opsLiveSession, /\{CadenceWeb\.MissionAuth, :load_mission\}/)
assert.match(
  opsLiveSession,
  /live "\/missions\/:mission_id\/ops\/requirements\/:contact_requirement_id",\n\s+OpsContactRequirementShowLive,\n\s+:show/,
)

const packageLock = JSON.parse(packageLockSource)
assert.equal(packageLock.packages["node_modules/reka-ui"].version, "2.10.3")

console.log("ops_contact_requirement_show_test passed")
