import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readdir, readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  cadenceEmptyStateConsumers,
  cadenceEmptyStateMigration,
  emptyStateActionClass,
  emptyStateActionContainerClass,
  emptyStateActionIconClass,
  emptyStateDescriptionClass,
  emptyStateFrameMigrations,
  emptyStateFramePredecessor,
  emptyStateRootClass,
  emptyStateSha256,
  emptyStateVariantLedger,
  peelCadenceEmptyStateComponent,
  peelCadenceEmptyStateFrames,
} from "./empty_state_frame_test_support.mjs"
import {
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "the complete predecessor Vue tree has exactly fourteen frozen border-dashed occurrences",
  "only the three exact action-bearing empty states migrate and every no-action, class-order, and shape variant stays excluded",
  "both caller migrations and the legacy DTO adapter reconstruct exact predecessor bytes and full SHA-256 values",
  "all five existing CadenceEmptyState consumers remain byte-identical to the predecessor",
  "the three callers keep native anchors, routing attrs, icons, directives, conditions, and semantic action text in caller source",
  "the production-compiled SpacecraftList fleet and profiles empty states preserve exact native DOM",
  "the production-compiled CommsOverview transport empty state preserves exact native DOM while validation stays raw",
  "reactive href and label updates preserve each caller-owned native action identity",
  "the shared frame has exactly three direct production consumers and no overlapping leaf component",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `empty-state migration contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 9)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const lines = (...sourceLines) => sourceLines.join("\n")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const git = (...args) =>
  execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const predecessorSource = (repositoryPath) =>
  git("show", `${emptyStateFramePredecessor}:${repositoryPath}`)

assert.equal(git("cat-file", "-t", emptyStateFramePredecessor).trim(), "commit")

const frozenEntries = [
  ...emptyStateFrameMigrations,
  cadenceEmptyStateMigration,
  ...cadenceEmptyStateConsumers,
  ...emptyStateVariantLedger.filter(({sha256}) => sha256),
]
const frozenByPath = new Map()

for (const entry of frozenEntries) {
  const byteLength = entry.predecessorByteLength ?? entry.byteLength
  const sha256 = entry.predecessorSha256 ?? entry.sha256
  const existing = frozenByPath.get(entry.repositoryPath)

  if (existing) {
    assert.deepEqual(existing, {byteLength, sha256}, `${entry.repositoryPath} ledger agrees`)
    continue
  }

  const source = predecessorSource(entry.repositoryPath)
  assert.equal(Buffer.byteLength(source), byteLength, `${entry.repositoryPath} frozen byte length`)
  assert.equal(emptyStateSha256(source), sha256, `${entry.repositoryPath} frozen SHA-256`)
  frozenByPath.set(entry.repositoryPath, {byteLength, sha256})
}

const predecessorBorderDashedLines = git(
  "grep",
  "-n",
  "-F",
  "border-dashed",
  emptyStateFramePredecessor,
  "--",
  ":(glob)apps/cadence_web/assets/vue/**/*.vue",
)
  .trim()
  .split("\n")

assert.equal(predecessorBorderDashedLines.length, 14)
assert.equal(
  predecessorBorderDashedLines.filter((line) => line.includes(emptyStateRootClass)).length,
  7,
  "the predecessor has exactly seven canonical root-class occurrences",
)

const predecessorVariantCounts = Object.fromEntries(
  emptyStateVariantLedger.map(({repositoryPath}) => [repositoryPath, 0]),
)

for (const resultLine of predecessorBorderDashedLines) {
  const repositoryPath = resultLine
    .slice(`${emptyStateFramePredecessor}:`.length)
    .split(":", 1)[0]
  assert.ok(repositoryPath in predecessorVariantCounts, `${repositoryPath} has a frozen classification`)
  predecessorVariantCounts[repositoryPath] += 1
}

assert.deepEqual(
  predecessorVariantCounts,
  Object.fromEntries(emptyStateVariantLedger.map(({repositoryPath, count}) => [repositoryPath, count])),
)
assert.equal(emptyStateFrameMigrations.reduce((total, entry) => total + entry.boundaries.length, 0), 3)
assert.equal(
  emptyStateVariantLedger.reduce((total, entry) => total + entry.count, 0),
  14,
)

const currentMigrationSources = new Map()
for (const migration of emptyStateFrameMigrations) {
  const current = await readFile(resolve(vueDirectory, migration.file), "utf8")
  const predecessor = predecessorSource(migration.repositoryPath)

  currentMigrationSources.set(migration.file, current)
  assert.equal(peelCadenceEmptyStateFrames(current, migration.file), predecessor)
  assert.equal(occurrences(current, migration.importLine), 1)
  assert.equal(current.match(/<CadenceEmptyStateFrame\b/g)?.length, migration.boundaries.length)

  for (const boundary of migration.boundaries) {
    assert.equal(occurrences(current, boundary.migrated), 1)
    assert.match(boundary.migrated, /<a\b/)
    assert.match(boundary.migrated, /:href=/)
    assert.match(boundary.migrated, /data-phx-link="redirect"/)
    assert.match(boundary.migrated, /data-phx-link-state="push"/)
    assert.ok(boundary.migrated.includes(`class="${emptyStateActionClass}"`))
    assert.ok(boundary.migrated.includes(`class="${emptyStateActionIconClass}"`))
  }
}

const currentCadenceEmptyState = await readFile(
  resolve(vueDirectory, cadenceEmptyStateMigration.file),
  "utf8",
)
assert.equal(
  peelCadenceEmptyStateComponent(currentCadenceEmptyState),
  predecessorSource(cadenceEmptyStateMigration.repositoryPath),
)
assert.match(
  currentMigrationSources.get("SpacecraftList.vue"),
  /^<script setup lang="ts">\nimport StatusBadge from "\.\/StatusBadge\.vue"\nimport CadenceEmptyStateFrame from "\.\/ui\/components\/CadenceEmptyStateFrame\.vue"\nimport CadenceListToolbarFrame/m,
)
assert.match(
  currentMigrationSources.get("CommsOverview.vue"),
  /^<script setup lang="ts">\nimport CadenceCard from "\.\/ui\/components\/CadenceCard\.vue"\nimport CadenceEmptyStateFrame from "\.\/ui\/components\/CadenceEmptyStateFrame\.vue"\nimport StatusBadge/m,
)
assert.match(
  currentCadenceEmptyState,
  /^<script setup lang="ts">\nimport CadenceEmptyStateFrame from "\.\/CadenceEmptyStateFrame\.vue"\nimport type \{EmptyStatePresentation\}/m,
)
assert.equal(occurrences(currentMigrationSources.get("SpacecraftList.vue"), "CadenceEmptyStateFrame"), 6)
assert.equal(occurrences(currentMigrationSources.get("CommsOverview.vue"), "CadenceEmptyStateFrame"), 4)
assert.equal(occurrences(currentCadenceEmptyState, "CadenceEmptyStateFrame"), 4)

for (const consumer of cadenceEmptyStateConsumers) {
  const current = await readFile(resolve(vueDirectory, consumer.file), "utf8")
  const predecessor = predecessorSource(consumer.repositoryPath)

  assert.equal(current, predecessor, `${consumer.file} remains byte-identical`)
  assert.equal(Buffer.byteLength(current), consumer.byteLength)
  assert.equal(emptyStateSha256(current), consumer.sha256)
  assert.equal(current.match(/^import CadenceEmptyState\b/gm)?.length, 1)
  assert.equal(current.match(/<CadenceEmptyState\b/g)?.length, 1)
}

for (const exclusion of emptyStateVariantLedger.filter(({sha256}) => sha256)) {
  const current = await readFile(resolve(repositoryRoot, exclusion.repositoryPath), "utf8")
  const predecessor = predecessorSource(exclusion.repositoryPath)

  assert.equal(current, predecessor, `${exclusion.file}: ${exclusion.classification}`)
  assert.equal(Buffer.byteLength(current), exclusion.byteLength)
  assert.equal(emptyStateSha256(current), exclusion.sha256)
  assert.doesNotMatch(current, /CadenceEmptyStateFrame/)
}

const validationExclusion = lines(
  `          <div class="${emptyStateRootClass}">`,
  '            <p class="hud-label">{{ overview.validation.empty_state.title }}</p>',
  `            <p class="${emptyStateDescriptionClass}">`,
  "              {{ overview.validation.empty_state.description }}",
  "            </p>",
  "          </div>",
)
const currentCommsOverview = currentMigrationSources.get("CommsOverview.vue")
assert.equal(occurrences(currentCommsOverview, validationExclusion), 1)
assert.equal(occurrences(currentCommsOverview, emptyStateRootClass), 1)
assert.equal(occurrences(currentMigrationSources.get("SpacecraftList.vue"), emptyStateRootClass), 0)

const vueFiles = (await readdir(vueDirectory, {recursive: true}))
  .filter((file) => file.endsWith(".vue"))
  .sort()
const currentVueSources = await Promise.all(
  vueFiles.map(async (file) => ({file, source: await readFile(resolve(vueDirectory, file), "utf8")})),
)
assert.deepEqual(
  currentVueSources
    .filter(({source}) => /^import CadenceEmptyStateFrame\b/m.test(source))
    .map(({file}) => file),
  ["CommsOverview.vue", "SpacecraftList.vue", "ui/components/CadenceEmptyState.vue"],
)
assert.equal(
  currentVueSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceEmptyStateFrame\b/g)?.length ?? 0),
    0,
  ),
  4,
)

const frameSource = await readFile(
  resolve(vueDirectory, "ui/components/CadenceEmptyStateFrame.vue"),
  "utf8",
)
assert.doesNotMatch(
  frameSource,
  /<a\b|<button\b|href|data-phx-link|No spacecraft|No profiles|Register the first|Create the first/,
)
assert.match(
  currentMigrationSources.get("SpacecraftList.vue"),
  /<CadenceEmptyStateFrame v-if="roster\.fleet_empty">/,
)
assert.match(
  currentMigrationSources.get("SpacecraftList.vue"),
  /<CadenceEmptyStateFrame v-if="profiles\.empty">/,
)
assert.match(
  currentCommsOverview,
  /<div v-if="overview\.transport\.empty" class="mt-6">\n          <CadenceEmptyStateFrame>/,
)

const dom = installDom(
  '<div id="spacecraft-empty-state-host"></div><div id="comms-empty-state-host"></div>',
)
const [spacecraftSfc, commsSfc] = await Promise.all([
  loadSfc(resolve(vueDirectory, "SpacecraftList.vue")),
  loadSfc(resolve(vueDirectory, "CommsOverview.vue")),
])
const {createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")

const roster = reactive({
  fleet_empty: true,
  subtitle: "Fleet subtitle",
  new_spacecraft_href: "/missions/mission-1/spacecraft/new",
})
const profiles = reactive({
  empty: true,
  subtitle: "Profiles subtitle",
  new_profile_href: "/missions/mission-1/spacecraft/profiles/new",
})
const spacecraftApp = createApp(
  defineComponent({
    setup: () => () =>
      h(spacecraftSfc.component, {
        summary_tiles: [],
        roster,
        profiles,
      }),
  }),
)
spacecraftApp.mount(dom.window.document.querySelector("#spacecraft-empty-state-host"))
await flushVue(nextTick)

const spacecraftEmptyStates = dom.window.document.querySelectorAll(
  `#spacecraft-list-content [class="${emptyStateRootClass}"]`,
)
assert.equal(spacecraftEmptyStates.length, 2)
assert.equal(
  spacecraftEmptyStates[0].outerHTML,
  `<div class="${emptyStateRootClass}"><p class="hud-label">No spacecraft yet</p><p class="${emptyStateDescriptionClass}"> Register the first spacecraft for this mission. </p><div class="${emptyStateActionContainerClass}"><a href="/missions/mission-1/spacecraft/new" data-phx-link="redirect" data-phx-link-state="push" class="${emptyStateActionClass}"><span class="${emptyStateActionIconClass}"></span> Register the first spacecraft </a></div></div>`,
)
assert.equal(
  spacecraftEmptyStates[1].outerHTML,
  `<div class="${emptyStateRootClass}"><p class="hud-label">No profiles yet</p><p class="${emptyStateDescriptionClass}"> Create a profile to reuse frame and packet interpretation settings across spacecraft. </p><div class="${emptyStateActionContainerClass}"><a href="/missions/mission-1/spacecraft/profiles/new" data-phx-link="redirect" data-phx-link-state="push" class="${emptyStateActionClass}"><span class="${emptyStateActionIconClass}"></span> Create the first profile </a></div></div>`,
)
const fleetAction = spacecraftEmptyStates[0].querySelector("a")
const profilesAction = spacecraftEmptyStates[1].querySelector("a")

const overview = reactive({
  transport: {
    id: "transport-card",
    eyebrow: "Transport",
    count: 0,
    count_label: "configured",
    description: "Transport summary",
    status: {tone: "attention", label: "Setup required"},
    empty: true,
    empty_state: {
      title: "No transports yet",
      description: "Create the first mission transport.",
      action_label: "Create transport",
      action_href: "/missions/mission-1/comms/transports/new",
    },
    rows: [],
    manage_label: "Manage",
    manage_href: "/missions/mission-1/comms/transports",
    add_label: "Add",
    add_href: "/missions/mission-1/comms/transports/new",
  },
  validation: {
    id: "validation-card",
    eyebrow: "Validation",
    title: "Validation title",
    description: "Validation summary",
    status: {tone: "ready", label: "Ready"},
    empty: true,
    empty_state: {
      title: "No validation findings",
      description: "All current communications resources are valid.",
    },
    findings_id: "validation-findings",
    finding_groups: [],
  },
})
const commsApp = createApp(
  defineComponent({
    setup: () => () => h(commsSfc.component, {overview}),
  }),
)
commsApp.mount(dom.window.document.querySelector("#comms-empty-state-host"))
await flushVue(nextTick)

const commsEmptyStates = dom.window.document.querySelectorAll(
  `#comms-overview-content [class="${emptyStateRootClass}"]`,
)
assert.equal(commsEmptyStates.length, 2)
assert.equal(
  commsEmptyStates[0].outerHTML,
  `<div class="${emptyStateRootClass}"><p class="hud-label">No transports yet</p><p class="${emptyStateDescriptionClass}">Create the first mission transport.</p><div class="${emptyStateActionContainerClass}"><a href="/missions/mission-1/comms/transports/new" data-phx-link="redirect" data-phx-link-state="push" class="${emptyStateActionClass}"><span class="${emptyStateActionIconClass}"></span> Create transport</a></div></div>`,
)
assert.equal(
  commsEmptyStates[1].outerHTML,
  `<div class="${emptyStateRootClass}"><p class="hud-label">No validation findings</p><p class="${emptyStateDescriptionClass}">All current communications resources are valid.</p></div>`,
  "the explicitly excluded validation empty state remains raw and actionless",
)
const transportAction = commsEmptyStates[0].querySelector("a")

roster.new_spacecraft_href = "/missions/mission-1/spacecraft/new?phase=updated"
profiles.new_profile_href = "/missions/mission-1/spacecraft/profiles/new?phase=updated"
overview.transport.empty_state.action_href =
  "/missions/mission-1/comms/transports/new?phase=updated"
overview.transport.empty_state.action_label = "Create updated transport"
await flushVue(nextTick)

assert.strictEqual(spacecraftEmptyStates[0].querySelector("a"), fleetAction)
assert.strictEqual(spacecraftEmptyStates[1].querySelector("a"), profilesAction)
assert.strictEqual(commsEmptyStates[0].querySelector("a"), transportAction)
assert.equal(fleetAction.getAttribute("href"), roster.new_spacecraft_href)
assert.equal(profilesAction.getAttribute("href"), profiles.new_profile_href)
assert.equal(transportAction.getAttribute("href"), overview.transport.empty_state.action_href)
assert.equal(transportAction.textContent.trim(), "Create updated transport")

assert.doesNotThrow(() => commsApp.unmount())
assert.doesNotThrow(() => spacecraftApp.unmount())
dom.window.close()

console.log(`empty_state_frame_migration_test passed (${scenarios.length} semantic scenarios)`)
