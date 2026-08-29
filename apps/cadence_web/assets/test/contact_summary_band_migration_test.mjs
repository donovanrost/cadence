#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  compactHeaderBodyFramePath,
} from "./compact_page_header_body_frame_test_support.mjs"
import {narrowFormPageFramePath} from "./narrow_form_page_frame_test_support.mjs"
import {
  contactSummaryBandCallerNames,
  contactSummaryBandHeaderClass,
  contactSummaryBandMigrationFor,
  contactSummaryBandMigrations,
  contactSummaryBandPredecessorCommit,
  contactSummaryBandPrimitive,
  contactSummaryBandRootClass,
  peelContactSummaryBand,
} from "./contact_summary_band_test_support.mjs"
import {opsListBodyFramePath} from "./ops_list_body_frame_test_support.mjs"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "all current Vue SFCs and the fixed predecessor tree yield the exact two-file structural cohort",
  "the fixed predecessor commit freezes all three Git blobs, byte lengths, and SHA-256 values",
  "each caller peels only the newest summary wrapper back to exact predecessor bytes",
  "the existing CadencePanel normal SFC source and Git blob remain unchanged",
  "both real caller SFCs compile and mount after JSDOM globals are installed",
  "caller ids, classes, direct DIV topology, footer data, and Fragment transparency stay exact",
  "reactive summary updates preserve native section, grid, footer, and explicit child identity",
  "the iterated requirement fields retain keyed native identity through update and reorder",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `contact summary band contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 8)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const dom = installDom(
  '<div id="requirement-summary-contract"></div><div id="plan-summary-contract"></div>',
)

for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLParagraphElement",
  "HTMLSelectElement",
  "HTMLTextAreaElement",
  "HTMLOptionElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {parse: parseDom} = integrationRequire("@vue/compiler-dom")
const {parse} = integrationRequire("@vue/compiler-sfc")

const sha256 = (value) => createHash("sha256").update(value).digest("hex")
const gitBlobId = (value) =>
  createHash("sha1")
    .update(`blob ${value.byteLength}\0`)
    .update(value)
    .digest("hex")
const gitShow = (commit, path) =>
  execFileSync("git", ["-C", repositoryRoot, "show", `${commit}:${path}`])
const gitObject = (commit, path) =>
  execFileSync("git", ["-C", repositoryRoot, "rev-parse", `${commit}:${path}`], {
    encoding: "utf8",
  }).trim()

const walkVueFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  entries.sort((left, right) => left.name.localeCompare(right.name))
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = resolve(directory, entry.name)
      if (entry.isDirectory()) return walkVueFiles(entryPath)
      return entry.isFile() && entry.name.endsWith(".vue") ? [entryPath] : []
    }),
  )
  return nested.flat()
}

const predecessorVuePaths = execFileSync(
  "git",
  [
    "-C",
    repositoryRoot,
    "ls-tree",
    "-r",
    "--name-only",
    contactSummaryBandPredecessorCommit,
    "apps/cadence_web/assets/vue",
  ],
  {encoding: "utf8"},
)
  .trim()
  .split("\n")
  .filter((path) => path.endsWith(".vue"))
  .sort()
const currentVuePaths = (await walkVueFiles(vueDirectory))
  .map((path) => `apps/cadence_web/assets/vue/${path.slice(vueDirectory.length + 1)}`)
  .sort()

assert.equal(predecessorVuePaths.length, 223, "the fixed predecessor audits all 223 Vue SFCs")
assert.deepEqual(
  currentVuePaths,
  [
    ...predecessorVuePaths,
    compactHeaderBodyFramePath,
    "apps/cadence_web/assets/vue/ui/components/CadenceFormPageFrame.vue",
    narrowFormPageFramePath,
    opsListBodyFramePath,
    "apps/cadence_web/assets/vue/ui/components/CadenceOpsPageBodyFrame.vue",
    "apps/cadence_web/assets/vue/ui/components/CadenceDefinitionListPanel.vue",
    "apps/cadence_web/assets/vue/ui/components/CadenceOpsListFrame.vue",
    "apps/cadence_web/assets/vue/ui/components/CadenceStatTile.vue",
    "apps/cadence_web/assets/vue/ui/components/CadenceDashboardSettingsSectionFrame.vue",
  ].sort(),
  "the current SFC path cohort adds only the audited presentation primitives",
)
assert.deepEqual(contactSummaryBandCallerNames, [
  "OpsContactRequirementShow.vue",
  "OpsContactPlanShow.vue",
])
assert.equal(new Set(contactSummaryBandCallerNames).size, 2)
assert.throws(
  () => contactSummaryBandMigrationFor("UnknownContactSummary.vue"),
  /audited contact summary band caller/,
)

const elementChildren = (node) => node.children?.filter((child) => child.type === 1) ?? []
const staticAttribute = (node, name) =>
  node.props.find((property) => property.type === 6 && property.name === name)?.value?.content
const directive = (node, name, argument) =>
  node.props.find(
    (property) =>
      property.type === 7 &&
      property.name === name &&
      property.arg?.type === 4 &&
      property.arg.content === argument,
  )
const hasDirective = (node, name) =>
  node.props.some((property) => property.type === 7 && property.name === name)
const dynamicId = (node) => directive(node, "bind", "id")?.exp?.content
const hasBorderTop = (node) =>
  (staticAttribute(node, "class")?.split(/\s+/) ?? []).includes("border-t")
const allElements = (root) => {
  const elements = []
  const visit = (node) => {
    if (node.type === 1) elements.push(node)
    for (const child of node.children ?? []) visit(child)
  }
  visit(root)
  return elements
}
const parseTemplate = (source, filename) => {
  const parsed = parse(source, {filename})
  assert.deepEqual(parsed.errors, [], `${filename} parses as an SFC`)
  if (!parsed.descriptor.template) return null
  return parseDom(parsed.descriptor.template.content)
}
const nativeCandidates = (source, filename) => {
  const template = parseTemplate(source, filename)
  if (!template) return []
  return allElements(template).filter((node) => {
    const children = elementChildren(node)
    return (
      node.tag === "section" &&
      node.props.length === 2 &&
      dynamicId(node) !== undefined &&
      staticAttribute(node, "class") === contactSummaryBandRootClass &&
      children.length === 2 &&
      children[0].tag === "div" &&
      staticAttribute(children[0], "class") === contactSummaryBandHeaderClass &&
      children[1].tag === "div" &&
      hasBorderTop(children[1])
    )
  })
}
const migratedCandidates = (source, filename) => {
  const template = parseTemplate(source, filename)
  if (!template) return []
  return allElements(template).filter((node) => {
    const children = elementChildren(node)
    const headerTemplate = children[0]
    return (
      node.tag === "CadencePanel" &&
      node.props.length === 3 &&
      dynamicId(node) !== undefined &&
      staticAttribute(node, "class") === contactSummaryBandRootClass &&
      staticAttribute(node, "header-class") === contactSummaryBandHeaderClass &&
      children.length === 2 &&
      headerTemplate.tag === "template" &&
      directive(headerTemplate, "slot", "header") !== undefined &&
      children[1].tag === "div" &&
      hasBorderTop(children[1])
    )
  })
}

const predecessorCohort = []
const currentCohort = []
for (const path of predecessorVuePaths) {
  const filename = path.split("/").at(-1)
  const predecessorSource = gitShow(contactSummaryBandPredecessorCommit, path).toString("utf8")
  const currentSource = await readFile(resolve(repositoryRoot, path), "utf8")

  for (const candidate of nativeCandidates(predecessorSource, path)) {
    predecessorCohort.push({file: filename, id: dynamicId(candidate)})
  }
  assert.equal(nativeCandidates(currentSource, path).length, 0, `${filename} has no native target left`)
  for (const candidate of migratedCandidates(currentSource, path)) {
    const headerChildren = elementChildren(elementChildren(candidate)[0])
    currentCohort.push({
      file: filename,
      id: dynamicId(candidate),
      headerChildren: headerChildren.length,
      iterated: hasDirective(headerChildren[0], "for"),
    })
  }
}

assert.deepEqual(predecessorCohort, [
  {file: "OpsContactPlanShow.vue", id: "page.summary.id"},
  {file: "OpsContactRequirementShow.vue", id: "page.horizon.id"},
])
assert.deepEqual(currentCohort, [
  {
    file: "OpsContactPlanShow.vue",
    id: "page.summary.id",
    headerChildren: 3,
    iterated: false,
  },
  {
    file: "OpsContactRequirementShow.vue",
    id: "page.horizon.id",
    headerChildren: 1,
    iterated: true,
  },
])

const predecessorType = execFileSync(
  "git",
  ["-C", repositoryRoot, "cat-file", "-t", contactSummaryBandPredecessorCommit],
  {encoding: "utf8"},
).trim()
assert.equal(predecessorType, "commit")

for (const frozen of [contactSummaryBandPrimitive, ...contactSummaryBandMigrations]) {
  const predecessorBytes = gitShow(contactSummaryBandPredecessorCommit, frozen.path)
  assert.equal(frozen.predecessorCommit, contactSummaryBandPredecessorCommit)
  assert.equal(gitObject(contactSummaryBandPredecessorCommit, frozen.path), frozen.predecessorBlob)
  assert.equal(gitBlobId(predecessorBytes), frozen.predecessorBlob)
  assert.equal(predecessorBytes.byteLength, frozen.predecessorByteLength)
  assert.equal(sha256(predecessorBytes), frozen.predecessorSha256)
}

const primitivePath = resolve(repositoryRoot, contactSummaryBandPrimitive.path)
const primitiveBytes = await readFile(primitivePath)
const primitivePredecessorBytes = gitShow(
  contactSummaryBandPredecessorCommit,
  contactSummaryBandPrimitive.path,
)
assert.deepEqual(primitiveBytes, primitivePredecessorBytes)
assert.equal(gitBlobId(primitiveBytes), contactSummaryBandPrimitive.predecessorBlob)
assert.equal(sha256(primitiveBytes), contactSummaryBandPrimitive.predecessorSha256)

for (const migration of contactSummaryBandMigrations) {
  const current = await readFile(resolve(repositoryRoot, migration.path), "utf8")
  const predecessorBytes = gitShow(contactSummaryBandPredecessorCommit, migration.path)
  const reconstructed = peelContactSummaryBand(current, migration.file)

  assert.deepEqual(Buffer.from(reconstructed), predecessorBytes)
  assert.equal(current.split(migration.migrated).length - 1, 1)
  assert.equal(current.split(migration.predecessor).length - 1, 0)
  assert.equal(migration.migrated.match(/@[-\w]+=/g)?.length ?? 0, 0)
}

const requirementPath = resolve(vueDirectory, "OpsContactRequirementShow.vue")
const planPath = resolve(vueDirectory, "OpsContactPlanShow.vue")
const [requirementSfc, planSfc] = await Promise.all([loadSfc(requirementPath), loadSfc(planPath)])
const {createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")

const requirementPage = reactive({
  id: "requirement-page",
  back_action: {label: "Back", href: "/ops/requirements"},
  header: {
    priority: "Urgent",
    version_label: "v7",
    intent: "Downlink payload",
    outcome: "Return the payload before the deadline.",
    plan_action: {id: "plan-action", event: "plan", payload: {}, label: "Plan", disabled: false},
  },
  horizon: {
    id: "requirement-horizon-initial",
    fields: [
      {label: "Priority", value: "Critical", class: "mt-1 font-mono text-sm text-error"},
      {label: "Cadence", value: "Daily", class: "mt-1 font-mono text-sm"},
      {label: "Window", value: "04:00 UTC", class: "mt-1 font-mono text-sm text-primary"},
    ],
    rationale: "Rationale & evidence",
  },
  planning: {
    heading: "Planning searches",
    description: "Search description",
    run_state: {id: "planning-state", label: "Ready"},
    error: {id: "planning-error", message: null},
    searches: {
      id: "planning-searches",
      empty: {id: "planning-searches-empty", message: "No searches"},
    },
  },
  opportunities: {
    heading: "Opportunities",
    description: "Opportunity description",
    selected_count: {id: "selected-count", label: "0 selected"},
    list: {id: "opportunities", empty: {id: "opportunities-empty", message: "No opportunities"}},
    footer: "Selection footer",
    create_action: {id: "create-plan", event: "create-plan", payload: {}, label: "Create", disabled: true},
  },
  journey: {heading: "Journey", steps: []},
  versions: {heading: "Versions", id: "requirement-versions"},
})

const planPage = reactive({
  id: "plan-page",
  back_action: {label: "Back", href: "/ops/requirements"},
  header: {
    state: {label: "Pending", class: "badge badge-warning"},
    version_label: "v3",
    heading: "Contact plan",
    description: "Plan description",
    execute_action: null,
  },
  summary: {
    id: "plan-summary-initial",
    coverage: {label: "Satisfied", class: "mt-1 font-mono text-sm text-success"},
    selected_count: 2,
    approval_identity: "ops@example.test",
    content_hash: {id: "plan-content-hash-initial", value: "sha256:abc&123"},
  },
  selections: {
    id: "plan-selections",
    empty: {id: "plan-selections-empty", message: "No selections"},
  },
  unsatisfied: null,
  policy: {id: "plan-policy", summary: "Policy", selections: []},
  execution: {
    id: "plan-execution",
    heading: "Execution",
    description: "Execution description",
    empty: {id: "plan-execution-empty", message: "No execution"},
  },
  submission: null,
  decision: null,
  approval_evidence: {
    id: "approval-evidence",
    heading: "Approval evidence",
    empty: {id: "approval-evidence-empty", message: "No approvals"},
  },
  rationale: {heading: "Rationale", value: "Plan rationale", plan_id: "plan-3"},
})

const RequirementOracle = defineComponent({
  setup() {
    return () =>
      h(requirementSfc.component, {
        page: requirementPage,
        requirement_versions: [],
        planning_searches: [],
        opportunities: [],
      })
  },
})
const PlanOracle = defineComponent({
  setup() {
    return () =>
      h(planSfc.component, {
        page: planPage,
        submission_form: null,
        admin_controls: null,
        selected_opportunities: [],
        execution_items: [],
        approvals: [],
      })
  },
})

const requirementApp = createApp(RequirementOracle)
const planApp = createApp(PlanOracle)
requirementApp.mount(dom.window.document.querySelector("#requirement-summary-contract"))
planApp.mount(dom.window.document.querySelector("#plan-summary-contract"))
await flushVue(nextTick)

const requirementSection = dom.window.document.querySelector("#requirement-horizon-initial")
const requirementHeader = requirementSection.firstElementChild
const requirementFooter = requirementSection.lastElementChild
const requirementFields = [...requirementHeader.children]

assert.equal(
  requirementSection.outerHTML,
  '<section id="requirement-horizon-initial" class="border border-base-300 bg-base-200/20"><div class="grid gap-4 p-4 sm:grid-cols-3"><div><p class="hud-label">Priority</p><p class="mt-1 font-mono text-sm text-error">Critical</p></div><div><p class="hud-label">Cadence</p><p class="mt-1 font-mono text-sm">Daily</p></div><div><p class="hud-label">Window</p><p class="mt-1 font-mono text-sm text-primary">04:00 UTC</p></div></div><div class="border-t border-base-300 px-4 py-3 text-sm text-base-content/60">Rationale &amp; evidence</div></section>',
)
assert.ok(requirementSection instanceof dom.window.HTMLElement)
assert.equal(requirementSection.tagName, "SECTION")
assert.deepEqual(elementAttributes(requirementSection), {
  class: contactSummaryBandRootClass,
  id: "requirement-horizon-initial",
})
assert.equal(requirementSection.hasAttribute("header-class"), false)
assert.equal(requirementSection.childNodes.length, 2)
assert.deepEqual([...requirementSection.childNodes].map((node) => node.nodeName), ["DIV", "DIV"])
assert.equal(requirementHeader.className, contactSummaryBandHeaderClass)
assert.equal(requirementHeader.childNodes.length, 3)
assert.deepEqual([...requirementHeader.childNodes].map((node) => node.nodeName), ["DIV", "DIV", "DIV"])
assert.equal(requirementFooter.className, "border-t border-base-300 px-4 py-3 text-sm text-base-content/60")

const originalRequirementFields = [...requirementPage.horizon.fields]
originalRequirementFields[0].value = "Emergency"
originalRequirementFields[0].class = "mt-1 font-mono text-sm text-warning"
requirementPage.horizon.fields = [
  originalRequirementFields[2],
  originalRequirementFields[0],
  originalRequirementFields[1],
]
requirementPage.horizon.id = "requirement-horizon-updated"
requirementPage.horizon.rationale = "Updated rationale"
await flushVue(nextTick)

const updatedRequirementSection = dom.window.document.querySelector("#requirement-horizon-updated")
assert.strictEqual(updatedRequirementSection, requirementSection)
assert.strictEqual(updatedRequirementSection.firstElementChild, requirementHeader)
assert.strictEqual(updatedRequirementSection.lastElementChild, requirementFooter)
assert.strictEqual(requirementHeader.children[0], requirementFields[2])
assert.strictEqual(requirementHeader.children[1], requirementFields[0])
assert.strictEqual(requirementHeader.children[2], requirementFields[1])
assert.equal(requirementHeader.children[1].lastElementChild.className, "mt-1 font-mono text-sm text-warning")
assert.equal(requirementHeader.children[1].lastElementChild.textContent, "Emergency")
assert.equal(requirementFooter.textContent.trim(), "Updated rationale")

const planSection = dom.window.document.querySelector("#plan-summary-initial")
const planHeader = planSection.firstElementChild
const planFooter = planSection.lastElementChild
const planFields = [...planHeader.children]
const planHash = dom.window.document.querySelector("#plan-content-hash-initial")

assert.equal(
  planSection.outerHTML,
  '<section id="plan-summary-initial" class="border border-base-300 bg-base-200/20"><div class="grid gap-4 p-4 sm:grid-cols-3"><div><p class="hud-label">Requirement coverage</p><p class="mt-1 font-mono text-sm text-success">Satisfied</p></div><div><p class="hud-label">Selected windows</p><p class="mt-1 font-mono text-sm">2</p></div><div><p class="hud-label">Approval identity</p><p class="mt-1 font-mono text-sm">ops@example.test</p></div></div><div class="border-t border-base-300 px-4 py-3"><p class="hud-label">Exact content hash</p><p id="plan-content-hash-initial" class="mt-1 break-all font-mono text-[0.68rem] text-base-content/55">sha256:abc&amp;123</p></div></section>',
)
assert.ok(planSection instanceof dom.window.HTMLElement)
assert.equal(planSection.tagName, "SECTION")
assert.deepEqual(elementAttributes(planSection), {
  class: contactSummaryBandRootClass,
  id: "plan-summary-initial",
})
assert.equal(planSection.hasAttribute("header-class"), false)
assert.equal(planSection.childNodes.length, 2)
assert.deepEqual([...planSection.childNodes].map((node) => node.nodeName), ["DIV", "DIV"])
assert.equal(planHeader.className, contactSummaryBandHeaderClass)
assert.equal(planHeader.childNodes.length, 3)
assert.equal(planFooter.className, "border-t border-base-300 px-4 py-3")
assert.deepEqual(elementAttributes(planHash), {
  class: "mt-1 break-all font-mono text-[0.68rem] text-base-content/55",
  id: "plan-content-hash-initial",
})

planPage.summary.id = "plan-summary-updated"
planPage.summary.coverage.label = "Partial"
planPage.summary.coverage.class = "mt-1 font-mono text-sm text-warning"
planPage.summary.selected_count = 3
planPage.summary.approval_identity = "mission-control@example.test"
planPage.summary.content_hash.id = "plan-content-hash-updated"
planPage.summary.content_hash.value = "sha256:def456"
await flushVue(nextTick)

const updatedPlanSection = dom.window.document.querySelector("#plan-summary-updated")
const updatedPlanHash = dom.window.document.querySelector("#plan-content-hash-updated")
assert.strictEqual(updatedPlanSection, planSection)
assert.strictEqual(updatedPlanSection.firstElementChild, planHeader)
assert.strictEqual(updatedPlanSection.lastElementChild, planFooter)
assert.deepEqual([...planHeader.children], planFields)
assert.strictEqual(updatedPlanHash, planHash)
assert.equal(planFields[0].lastElementChild.className, "mt-1 font-mono text-sm text-warning")
assert.equal(planFields[0].lastElementChild.textContent, "Partial")
assert.equal(planFields[1].lastElementChild.textContent, "3")
assert.equal(planFields[2].lastElementChild.textContent, "mission-control@example.test")
assert.equal(updatedPlanHash.textContent, "sha256:def456")

requirementApp.unmount()
planApp.unmount()
dom.window.close()

console.log(
  `contact_summary_band_migration_test passed (${predecessorVuePaths.length} SFCs, ${scenarios.length} scenarios, predecessor ${contactSummaryBandPredecessorCommit})`,
)
