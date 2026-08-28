import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

assert.equal(process.versions.node, "24.16.0", "migration contracts use pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const {parse} = integrationRequire("@vue/compiler-sfc")
const cadencePanelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const cadencePageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const cadencePageHeaderFrameOpen = '<CadencePageHeaderFrame variant="ops">'
const cadencePageHeaderFrameClose = "</CadencePageHeaderFrame>"
const cadenceTableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const opsPageHeaderOpen =
  '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">'

const files = [
  {
    name: "OpsDataSources.vue",
    panels: 3,
    sha256: "43d992e51884e03f1dca0e87c726f9b3fcfae9b1e887ba8b4fe09565ad9b242a",
    rawVariants: ['          <aside class="space-y-4">'],
    migrations: [
      {
        componentOpen: `            <CadencePanel
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >`,
        sectionOpen: '            <section class="card bg-base-200 border border-base-300">',
        slotOpen: "              <template #header>",
        headerOpen: `              <div
                class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
              >`,
        slotClose: "              </template>",
        headerClose: "              </div>",
        componentClose: "            </CadencePanel>",
        sectionClose: "            </section>",
      },
      {
        componentOpen: `            <CadencePanel
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >`,
        sectionOpen: '            <section class="card bg-base-200 border border-base-300">',
        slotOpen: "              <template #header>",
        headerOpen: `              <div
                class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
              >`,
        slotClose: "              </template>",
        headerClose: "              </div>",
        componentClose: "            </CadencePanel>",
        sectionClose: "            </section>",
      },
      {
        componentOpen: `            <CadencePanel
              v-for="list in [
                page.activity.binding_events,
                page.activity.source_events,
                page.activity.health_events
              ]"
              :key="list.id"
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >`,
        sectionOpen: `            <section
              v-for="list in [
                page.activity.binding_events,
                page.activity.source_events,
                page.activity.health_events
              ]"
              :key="list.id"
              class="card bg-base-200 border border-base-300"
            >`,
        slotOpen: "              <template #header>",
        headerOpen: `              <div
                class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
              >`,
        slotClose: "              </template>",
        headerClose: "              </div>",
        componentClose: "            </CadencePanel>",
        sectionClose: "            </section>",
      },
    ],
  },
  {
    name: "OpsFleetPlanning.vue",
    panels: 3,
    opsPageHeader: true,
    sha256: "807d7a9b33db0044832785fc03655737f9e8885ce56bbecf2d20705185294644",
    importText: `${cadencePanelImport}\n`,
    rawVariants: [
      `  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">`,
      '        <aside class="space-y-5">',
    ],
    migrations: [
      {
        componentOpen: `      <CadencePanel
        id="fleet-planning-control-strip"
        class="grid border border-base-300 bg-base-200/20 md:grid-cols-4"
        header-class="border-b border-base-300 px-4 py-4 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0"
      >`,
        sectionOpen: `      <section
        id="fleet-planning-control-strip"
        class="grid border border-base-300 bg-base-200/20 md:grid-cols-4"
      >`,
        slotOpen: `        <template
          v-for="metric in control_metrics"
          :id="metric.id"
          :key="metric.id"
          #header
        >`,
        headerOpen: `        <div
          v-for="metric in control_metrics"
          :id="metric.id"
          :key="metric.id"
          class="border-b border-base-300 px-4 py-4 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0"
        >`,
        slotClose: "        </template>",
        headerClose: "        </div>",
        componentClose: "      </CadencePanel>",
        sectionClose: "      </section>",
      },
      {
        componentOpen: `        <CadencePanel
          class="min-w-0 border border-base-300 bg-base-200/15"
          header-class="flex items-center justify-between border-b border-base-300 px-4 py-3"
        >`,
        sectionOpen: '        <section class="min-w-0 border border-base-300 bg-base-200/15">',
        slotOpen: "          <template #header>",
        headerOpen:
          '          <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">',
        slotClose: "          </template>",
        headerClose: "          </div>",
        componentClose: "        </CadencePanel>",
        sectionClose: "        </section>",
      },
      {
        componentOpen: `          <CadencePanel
            :id="journey.id"
            class="border border-base-300 bg-base-200/15"
            header-class="border-b border-base-300 px-4 py-3"
          >`,
        sectionOpen:
          '          <section :id="journey.id" class="border border-base-300 bg-base-200/15">',
        slotOpen: "            <template #header>",
        headerOpen: '            <div class="border-b border-base-300 px-4 py-3">',
        slotClose: "            </template>",
        headerClose: "            </div>",
        componentClose: "          </CadencePanel>",
        sectionClose: "          </section>",
      },
    ],
  },
  {
    name: "OpsFleetPlanningPolicy.vue",
    panels: 2,
    opsPageHeader: true,
    sha256: "3ce5cb561e6c1495fd263b18c2c932fc19d200432d2e529fdef6eec7a09db711",
    rawVariants: ['    <aside class="min-w-0 space-y-5">'],
    migrations: [
      {
        componentOpen: `      <CadencePanel
        :id="page.manifest.id"
        class="border border-base-300 bg-base-200/15"
        header-class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3"
      >`,
        sectionOpen:
          '      <section :id="page.manifest.id" class="border border-base-300 bg-base-200/15">',
        slotOpen: "        <template #header>",
        headerOpen:
          '        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3">',
        slotClose: "        </template>",
        headerClose: "        </div>",
        componentClose: "      </CadencePanel>",
        sectionClose: "      </section>",
      },
      {
        componentOpen: `      <CadencePanel
        :id="grant_ledger.id"
        class="border border-base-300 bg-base-200/15"
        header-class="flex items-center justify-between border-b border-base-300 px-4 py-3"
      >`,
        sectionOpen:
          '      <section :id="grant_ledger.id" class="border border-base-300 bg-base-200/15">',
        slotOpen: "        <template #header>",
        headerOpen:
          '        <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">',
        slotClose: "        </template>",
        headerClose: "        </div>",
        componentClose: "      </CadencePanel>",
        sectionClose: "      </section>",
      },
    ],
  },
  {
    name: "SpacecraftList.vue",
    panels: 2,
    sha256: "b322bffd1e6082c1d7f18a942c3a5879e2751beceb2e3d0f41175d2a11e25669",
    rawVariants: [],
    migrations: [
      {
        componentOpen: `    <CadencePanel
      id="spacecraft-vehicles-card"
      class="card border border-base-300 bg-base-200"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >`,
        sectionOpen:
          '    <section id="spacecraft-vehicles-card" class="card border border-base-300 bg-base-200">',
        slotOpen: "      <template #header>",
        headerOpen:
          '      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">',
        slotClose: "      </template>",
        headerClose: "      </div>",
        componentClose: "    </CadencePanel>",
        sectionClose: "    </section>",
      },
      {
        componentOpen: `    <CadencePanel
      id="spacecraft-profiles-card"
      class="card border border-base-300 bg-base-200"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >`,
        sectionOpen:
          '    <section id="spacecraft-profiles-card" class="card border border-base-300 bg-base-200">',
        slotOpen: "      <template #header>",
        headerOpen:
          '      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">',
        slotClose: "      </template>",
        headerClose: "      </div>",
        componentClose: "    </CadencePanel>",
        sectionClose: "    </section>",
      },
    ],
  },
]

const countExact = (source, value) => source.split(value).length - 1

const replaceOnce = (source, before, after, label) => {
  assert.ok(source.includes(before), `${label} exists exactly where reconstruction expects it`)
  return source.replace(before, after)
}

const peelTableFrames = (source, name) => {
  const boundaries =
    name === "SpacecraftList.vue"
      ? [
          {
            componentOpen: '          <CadenceTableFrame id="spacecraft-vehicles-table">',
            tableOpen: '          <table id="spacecraft-vehicles-table" class="table">',
          },
          {
            componentOpen:
              '          <CadenceTableFrame id="spacecraft-profiles-preview-table">',
            tableOpen:
              '          <table id="spacecraft-profiles-preview-table" class="table">',
          },
        ]
      : []
  const importCount = boundaries.length > 0 ? 1 : 0

  assert.equal(
    countExact(source, cadenceTableFrameImport),
    importCount,
    `${name} has its expected CadenceTableFrame import count before peeling`,
  )
  assert.equal(
    countExact(source, "<CadenceTableFrame"),
    boundaries.length,
    `${name} has its expected CadenceTableFrame opening count before peeling`,
  )
  assert.equal(
    countExact(source, "</CadenceTableFrame>"),
    boundaries.length,
    `${name} has its expected CadenceTableFrame closing count before peeling`,
  )

  let predecessorCompatibleSource = source.replace(cadenceTableFrameImport, "")

  for (const [index, boundary] of boundaries.entries()) {
    predecessorCompatibleSource = replaceOnce(
      predecessorCompatibleSource,
      boundary.componentOpen,
      boundary.tableOpen,
      `${name} table frame ${index + 1} opening boundary`,
    )
  }

  predecessorCompatibleSource = predecessorCompatibleSource.replaceAll(
    "</CadenceTableFrame>",
    "</table>",
  )
  assert.equal(
    countExact(predecessorCompatibleSource, "CadenceTableFrame"),
    0,
    `${name} predecessor source has no residual CadenceTableFrame`,
  )

  return predecessorCompatibleSource
}

const peelPageHeaderFrame = (source, name) => {
  assert.equal(countExact(source, cadencePageHeaderFrameImport), 1, `${name} page header import count`)
  assert.equal(countExact(source, cadencePageHeaderFrameOpen), 1, `${name} page header open count`)
  assert.equal(countExact(source, cadencePageHeaderFrameClose), 1, `${name} page header close count`)

  const predecessorCompatibleSource = source
    .replace(cadencePageHeaderFrameImport, "")
    .replace(cadencePageHeaderFrameOpen, opsPageHeaderOpen)
    .replace(cadencePageHeaderFrameClose, "</header>")

  assert.equal(
    countExact(predecessorCompatibleSource, "CadencePageHeaderFrame"),
    0,
    `${name} predecessor source has no residual CadencePageHeaderFrame`
  )

  return predecessorCompatibleSource
}

const replaceOnceAfter = (source, before, after, start, label) => {
  const index = source.indexOf(before, start)
  assert.notEqual(index, -1, `${label} exists after its panel opening`)

  return {
    source: source.slice(0, index) + after + source.slice(index + before.length),
    next: index + after.length,
  }
}

assert.equal(files.reduce((total, file) => total + file.panels, 0), 10)

for (const file of files) {
  const filename = resolve(vueDirectory, file.name)
  const source = await readFile(filename, "utf8")
  const parsed = parse(source, {filename})

  assert.deepEqual(parsed.errors, [], `${file.name} parses with the pinned Vue compiler`)
  assert.equal(countExact(source, cadencePanelImport), 1, `${file.name} has one exact import`)
  assert.equal(countExact(source, "<CadencePanel"), file.panels, `${file.name} open count`)
  assert.equal(countExact(source, "</CadencePanel>"), file.panels, `${file.name} close count`)
  assert.equal(countExact(source, "header-class="), file.panels, `${file.name} header-class count`)
  assert.equal(countExact(source, "#header"), file.panels, `${file.name} header slot count`)
  assert.equal(file.migrations.length, file.panels, `${file.name} frozen migration ledger count`)

  const predecessorCompatibleSource = peelTableFrames(
    file.opsPageHeader ? peelPageHeaderFrame(source, file.name) : source,
    file.name,
  )

  for (const rawVariant of file.rawVariants) {
    assert.equal(
      countExact(predecessorCompatibleSource, rawVariant),
      1,
      `${file.name} keeps raw variant exactly once`
    )
  }

  let reconstructed = replaceOnce(
    predecessorCompatibleSource,
    file.importText ?? cadencePanelImport,
    "",
    `${file.name} CadencePanel import`,
  )

  for (const [index, migration] of file.migrations.entries()) {
    const label = `${file.name} panel ${index + 1}`
    let replacement = replaceOnceAfter(
      reconstructed,
      migration.componentOpen,
      migration.sectionOpen,
      0,
      `${label} opening boundary`,
    )
    reconstructed = replacement.source
    replacement = replaceOnceAfter(
      reconstructed,
      migration.slotOpen,
      migration.headerOpen,
      replacement.next,
      `${label} header opening boundary`,
    )
    reconstructed = replacement.source
    replacement = replaceOnceAfter(
      reconstructed,
      migration.slotClose,
      migration.headerClose,
      replacement.next,
      `${label} header closing boundary`,
    )
    reconstructed = replacement.source
    replacement = replaceOnceAfter(
      reconstructed,
      migration.componentClose,
      migration.sectionClose,
      replacement.next,
      `${label} closing boundary`,
    )
    reconstructed = replacement.source
  }

  assert.doesNotMatch(reconstructed, /CadencePanel/, `${file.name} reconstruction has no CadencePanel`)
  assert.equal(
    createHash("sha256").update(reconstructed).digest("hex"),
    file.sha256,
    `${file.name} reconstructs the frozen base byte-for-byte`,
  )
}

console.log("panel_ops_fleet_migration_test passed (10 exact panels across 4 SFCs)")
