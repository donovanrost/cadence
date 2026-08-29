import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {pageTitleCallerNames, peelCadencePageTitle} from "./page_title_test_support.mjs"
import {integrationRequire} from "./reka_adapter_test_support.mjs"
import {peelCadencePaginationFrame} from "./pagination_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  "24.16.0",
  "application, mission, and ops card migration contracts use pinned Node 24.16.0",
)

const base = "00c264585863a89a76d55484b777a7e73eda7fa5"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const pageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const tableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const validationMessageImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const peelValidationMessage = (source, name) => {
  if (name !== "ApplicationHost") return source

  return source
    .replace(validationMessageImport, "")
    .replace(
      `                <CadenceValidationMessage
                  v-for="error in field.errors"
                  :key="error"
                >`,
      `                <p
                  v-for="error in field.errors"
                  :key="error"
                  class="mt-1.5 text-sm text-error"
                >`,
    )
    .replace(
      "                >{{ error }}</CadenceValidationMessage>",
      "                >{{ error }}</p>",
    )
}
const peelTableFrame = (source, name) => {
  if (name !== "MissionOverview") return source

  const frameOpening = '        <CadenceTableFrame v-else id="mission-spacecraft-readiness">'
  const tableOpening = '        <table v-else id="mission-spacecraft-readiness" class="table">'
  const frameClosing = "        </CadenceTableFrame>"
  const tableClosing = "        </table>"

  assert.equal(
    source.split(tableFrameImport).length - 1,
    1,
    "MissionOverview imports CadenceTableFrame exactly once",
  )
  assert.equal(
    count(source, /^import CadenceTableFrame\b/gm),
    1,
    "MissionOverview has exactly one CadenceTableFrame import declaration",
  )
  assert.equal(count(source, /<CadenceTableFrame\b/g), 1, "MissionOverview has one table frame")
  assert.equal(count(source, /<\/CadenceTableFrame>/g), 1, "MissionOverview closes one table frame")
  assert.equal(source.split(frameOpening).length - 1, 1, "MissionOverview table opening is exact")
  assert.equal(source.split(frameClosing).length - 1, 1, "MissionOverview table closing is exact")

  const peeled = source
    .replace(tableFrameImport, "")
    .replace(frameOpening, tableOpening)
    .replace(frameClosing, tableClosing)

  assert.doesNotMatch(peeled, /CadenceTableFrame/)
  return peeled
}
const peelPageHeaderFrame = (source) =>
  source
    .replace(pageHeaderFrameImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")
const digest = (value) => createHash("sha256").update(value).digest("hex")
const count = (value, pattern) => value.match(pattern)?.length ?? 0

const migrationLedger = Object.freeze([
  Object.freeze({
    name: "ApplicationHost",
    path: resolve(testDirectory, "../vue/ApplicationHost.vue"),
    cardImport: 'import CadenceCard from "./ui/components/CadenceCard.vue"\n',
    baseSha256: "ffadfbc1f3b53845b1f19bc26c7e5abf03d50cac9eb909043a4033afeca86f41",
    boundaries: Object.freeze([
      Object.freeze({
        name: "generated application form",
        opening: `    <CadenceCard
      v-if="declarative_surface.form"
      :id="declarative_surface.form.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
`,
        originalOpening: `    <section
      v-if="declarative_surface.form"
      :id="declarative_surface.form.id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">`,
        closing: "\n    </CadenceCard>",
        originalClosing: "      </div>\n    </section>",
      }),
      Object.freeze({
        name: "application activity",
        opening: `    <CadenceCard
      v-if="declarative_surface.activity"
      :id="declarative_surface.activity.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
`,
        originalOpening: `    <section
      v-if="declarative_surface.activity"
      :id="declarative_surface.activity.id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">`,
        closing: "\n    </CadenceCard>",
        originalClosing: "      </div>\n    </section>",
      }),
    ]),
  }),
  Object.freeze({
    name: "ApplicationStats",
    path: resolve(testDirectory, "../vue/application_host/ApplicationStats.vue"),
    cardImport: 'import CadenceCard from "../ui/components/CadenceCard.vue"\n',
    baseSha256: "8a8befeae2c585231946858f273bf16ba6f898209ea74fde7dc22b4a8a998d78",
    boundaries: Object.freeze([
      Object.freeze({
        name: "application stat",
        opening: `    <CadenceCard
      v-for="stat in stats"
      :id="stat.id"
      :key="stat.stat_id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
`,
        originalOpening: `    <section
      v-for="stat in stats"
      :id="stat.id"
      :key="stat.stat_id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">`,
        closing: "\n    </CadenceCard>",
        originalClosing: "      </div>\n    </section>",
      }),
    ]),
  }),
  Object.freeze({
    name: "MissionOverview",
    path: resolve(testDirectory, "../vue/MissionOverview.vue"),
    cardImport: 'import CadenceCard from "./ui/components/CadenceCard.vue"\n',
    baseSha256: "79c4f3777ad19171238631f3c8f546ec591891ed8f049164b8554c55ddeb1371",
    boundaries: Object.freeze([
      Object.freeze({
        name: "mission readiness stat",
        opening: `    <CadenceCard
      v-for="card in overview.readiness_cards"
      :key="card.title"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
`,
        originalOpening: `    <section
      v-for="card in overview.readiness_cards"
      :key="card.title"
      class="card bg-base-200 border border-base-300"
    >
      <div class="card-body p-6">`,
        closing: "\n    </CadenceCard>",
        originalClosing: "      </div>\n    </section>",
      }),
      Object.freeze({
        name: "mission setup",
        opening: `  <CadenceCard
    class="card bg-base-200 border border-base-300"
    body-class="card-body p-6"
  >
`,
        originalOpening:
          `  <section class="card bg-base-200 border border-base-300">\n` +
          `    <div class="card-body p-6">`,
        closing: "\n  </CadenceCard>",
        originalClosing: "    </div>\n  </section>",
      }),
    ]),
  }),
  Object.freeze({
    name: "MissionApplications",
    path: resolve(testDirectory, "../vue/MissionApplications.vue"),
    cardImport: 'import CadenceCard from "./ui/components/CadenceCard.vue"\n',
    baseSha256: "286f701655753832b9fd76b5fa85baaf64105955271b49c904733be4499062fa",
    boundaries: Object.freeze([
      Object.freeze({
        name: "mission application",
        opening: `    <CadenceCard
      v-for="application in applications"
      :id="application.id"
      :key="application.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
`,
        originalOpening: `    <section
      v-for="application in applications"
      :id="application.id"
      :key="application.id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">`,
        closing: "\n    </CadenceCard>",
        originalClosing: "      </div>\n    </section>",
      }),
    ]),
  }),
  Object.freeze({
    name: "OpsActivationRequests",
    path: resolve(testDirectory, "../vue/OpsActivationRequests.vue"),
    cardImport: 'import CadenceCard from "./ui/components/CadenceCard.vue"\n',
    baseSha256: "022bbbfb84c969d7a93eeaaabe7d2d21a7364654795b8ff52eca4bf3e256ed27",
    boundaries: Object.freeze([
      Object.freeze({
        name: "activation request list",
        opening: `    <CadenceCard
      :id="page.list.card_id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
`,
        originalOpening:
          `    <section :id="page.list.card_id" class="card bg-base-200 border border-base-300">\n` +
          `      <div class="card-body p-6">`,
        closing: "\n    </CadenceCard>",
        originalClosing: "      </div>\n    </section>",
      }),
      Object.freeze({
        name: "activation decision form",
        opening: `    <CadenceCard
      v-if="selected"
      :id="form.panel_id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
`,
        originalOpening: `    <section
      v-if="selected"
      :id="form.panel_id"
      class="card bg-base-200 border border-base-300"
    >
      <div class="card-body p-6">`,
        closing: "\n    </CadenceCard>",
        originalClosing: "      </div>\n    </section>",
      }),
    ]),
  }),
])

assert.deepEqual(
  migrationLedger.map(({boundaries}) => boundaries.length),
  [2, 1, 2, 1, 2],
  "the five-file migration ledger is frozen at the requested 2/1/2/1/2 split",
)

const {compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")
let totalBoundaries = 0

for (const entry of migrationLedger) {
  const source = await readFile(entry.path, "utf8")
  const filename = `${entry.name}.vue`
  const pageTitleCompatibleSource = pageTitleCallerNames.includes(filename)
    ? peelCadencePageTitle(source, filename)
    : source
  const prePaginationSource =
    entry.name === "ApplicationHost"
      ? peelCadencePaginationFrame(pageTitleCompatibleSource, "ApplicationHost.vue")
      : pageTitleCompatibleSource

  assert.equal(
    source.split(entry.cardImport).length - 1,
    1,
    `${entry.name} imports CadenceCard exactly once`,
  )
  assert.equal(count(source, /<CadenceCard\b/g), entry.boundaries.length)
  assert.equal(count(source, /body-class="card-body p-6"/g), entry.boundaries.length)
  assert.equal(count(source, /<div class="card-body p-6">/g), 0)
  assert.doesNotMatch(
    source,
    /<section\b[^>]*class="[^"]*\bcard\b[^"]*"[^>]*>\s*<div class="card-body p-6">/,
  )

  let reconstructed = peelPageHeaderFrame(
    peelTableFrame(peelValidationMessage(prePaginationSource, entry.name), entry.name),
  ).replace(entry.cardImport, "")

  for (const boundary of entry.boundaries) {
    assert.equal(
      reconstructed.split(boundary.opening).length - 1,
      1,
      `${entry.name} ${boundary.name} opening is exact and unique`,
    )

    const openingIndex = reconstructed.indexOf(boundary.opening)
    const slotStart = openingIndex + boundary.opening.length
    const closingIndex = reconstructed.indexOf(boundary.closing, slotStart)

    assert.ok(closingIndex > slotStart, `${entry.name} ${boundary.name} closing follows opening`)

    const callerSlot = reconstructed.slice(slotStart, closingIndex)

    assert.doesNotMatch(callerSlot, /<div class="card-body p-6">/)

    const original =
      `${boundary.originalOpening}\n${callerSlot}\n` + boundary.originalClosing

    reconstructed =
      reconstructed.slice(0, openingIndex) +
      original +
      reconstructed.slice(closingIndex + boundary.closing.length)
  }

  assert.doesNotMatch(reconstructed, /CadenceCard/)
  assert.equal(
    digest(reconstructed),
    entry.baseSha256,
    `${entry.name} reconstructs base ${base} byte-for-byte`,
  )

  const parsed = parse(source, {filename: entry.path})

  assert.deepEqual(parsed.errors, [], `${entry.name} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${entry.name} keeps its script setup block`)
  assert.ok(parsed.descriptor.template, `${entry.name} keeps its SFC template`)

  const compiled = compileTemplate({
    source: parsed.descriptor.template.content,
    filename: entry.path,
    id: `card-app-ops-${entry.name}`,
  })

  assert.deepEqual(compiled.errors, [], `${entry.name} template compiles`)
  assert.match(compiled.code, /function render/)
  totalBoundaries += entry.boundaries.length
}

assert.equal(migrationLedger.length, 5)
assert.equal(totalBoundaries, 8)
console.log("card_app_ops_migration_test passed (5 SFCs, 8 exact boundaries)")
