import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

const scenarioLedger = Object.freeze([
  "SpacecraftReadiness migrates its detail and nested application rows",
  "SpacecraftApplications migrates its status-fact row",
  "MissionApplications migrates its status-fact row",
  "every value span and its complete contents remain caller-owned",
  "no migrated source retains a raw hud-data-row root or label span",
  "only one CadenceDataRow import is added to each feature source",
  "removing only imports and transparent boundaries reconstructs every immutable base source",
])

assert.equal(
  process.versions.node,
  "24.16.0",
  "readiness/application data-row contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 7)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
const fixtures = [
  {
    filename: "SpacecraftReadiness.vue",
    foundationSha256: "117c68f54968eb7f900226a1f31841abd46a9855c6d38210d0030e2b12146031",
    cardCount: 1,
    boundaries: [
      {
        migratedOpen: `            <CadenceDataRow
              v-for="detail in panel.details"
              :key="detail.label"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="detail.label"
            >`,
        originalOpen: `            <div v-for="detail in panel.details" :key="detail.label" class="hud-data-row">
              <span class="hud-data-label">{{ detail.label }}</span>`,
        migratedClose: "\n            </CadenceDataRow>",
        originalClose: "\n            </div>",
      },
      {
        migratedOpen: `                <CadenceDataRow
                  row-class="hud-data-row"
                  label-class="hud-data-label"
                  :label="application.display_name"
                >`,
        originalOpen: `                <div class="hud-data-row">
                  <span class="hud-data-label">{{ application.display_name }}</span>`,
        migratedClose: "\n                </CadenceDataRow>",
        originalClose: "\n                </div>",
      },
    ],
  },
  {
    filename: "SpacecraftApplications.vue",
    foundationSha256: "3f4a33eb98893bc456f232cf64b00bab0db6bea5d2bc21fcf0f8f8a39392bb73",
    cardCount: 3,
    boundaries: [
      {
        migratedOpen: `            <CadenceDataRow
              v-for="fact in application.status.facts"
              :key="fact.id"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="fact.label"
            >`,
        originalOpen: `            <div v-for="fact in application.status.facts" :key="fact.id" class="hud-data-row">
              <span class="hud-data-label">{{ fact.label }}</span>`,
        migratedClose: "\n            </CadenceDataRow>",
        originalClose: "\n            </div>",
      },
    ],
  },
  {
    filename: "MissionApplications.vue",
    foundationSha256: "5bcfc94dbb88b0ed01fe9b67ea77b6e58d0ca226a93d3255c3416ba3a6a0e49f",
    cardCount: 1,
    boundaries: [
      {
        migratedOpen: `          <CadenceDataRow
            v-for="fact in application.status.facts"
            :key="fact.id"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="fact.label"
          >`,
        originalOpen: `          <div v-for="fact in application.status.facts" :key="fact.id" class="hud-data-row">
            <span class="hud-data-label">{{ fact.label }}</span>`,
        migratedClose: "\n          </CadenceDataRow>",
        originalClose: "\n          </div>",
      },
    ],
  },
]

const occurrences = (source, fragment) => source.split(fragment).length - 1
const multilineCardOpen = /^([ ]*)<CadenceCard$/
const inlineCardOpen = /^([ ]*)<CadenceCard ([^\n]+) body-class="card-body p-6">$/
const cardClose = /^([ ]*)<\/CadenceCard>$/

const reconstructCards = (source, expectedCardCount, filename) => {
  assert.equal(occurrences(source, cardImport), 1, `${filename} has one card import`)
  assert.equal(occurrences(source, "<CadenceCard"), expectedCardCount)
  assert.equal(occurrences(source, "</CadenceCard>"), expectedCardCount)

  const lines = source.replace(cardImport, "").split("\n")
  const reconstructed = []
  let openingCount = 0
  let closingCount = 0

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    const multiline = line.match(multilineCardOpen)
    const inline = line.match(inlineCardOpen)
    const closing = line.match(cardClose)

    if (multiline) {
      const indent = multiline[1]
      const attributes = []

      index += 1
      while (lines[index] !== `${indent}  body-class="card-body p-6"`) {
        assert.ok(
          lines[index]?.startsWith(`${indent}  `),
          `${filename} keeps each multiline card attribute on its boundary`,
        )
        attributes.push(lines[index])
        index += 1
      }

      index += 1
      assert.equal(lines[index], `${indent}>`, `${filename} keeps each card root indentation`)
      assert.ok(attributes.length > 0, `${filename} keeps caller-owned card attributes`)
      reconstructed.push(
        `${indent}<section`,
        ...attributes,
        `${indent}>`,
        `${indent}  <div class="card-body p-6">`,
      )
      openingCount += 1
      continue
    }

    if (inline) {
      const [, indent, attributes] = inline

      reconstructed.push(
        `${indent}<section ${attributes}>`,
        `${indent}  <div class="card-body p-6">`,
      )
      openingCount += 1
      continue
    }

    if (closing) {
      const indent = closing[1]

      reconstructed.push(`${indent}  </div>`, `${indent}</section>`)
      closingCount += 1
      continue
    }

    reconstructed.push(line)
  }

  assert.equal(openingCount, expectedCardCount, `${filename} reconstructs every card opening`)
  assert.equal(closingCount, expectedCardCount, `${filename} reconstructs every card closing`)

  const reconstructedSource = reconstructed.join("\n")

  assert.doesNotMatch(reconstructedSource, /CadenceCard/)

  return reconstructedSource
}

const {parse} = integrationRequire("@vue/compiler-sfc")

assert.equal(fixtures.length, 3, "all three exclusively owned feature sources are inventoried")
assert.equal(
  fixtures.reduce((count, fixture) => count + fixture.boundaries.length, 0),
  4,
  "all four raw data-row roots are inventoried",
)

for (const fixture of fixtures) {
  const componentPath = resolve(testDirectory, `../vue/${fixture.filename}`)
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${fixture.filename} parses with the pinned Vue compiler`)
  assert.equal(occurrences(source, dataRowImport), 1, `${fixture.filename} has one import`)
  assert.equal(
    occurrences(source, "<CadenceDataRow"),
    fixture.boundaries.length,
    `${fixture.filename} has its complete migrated row inventory`,
  )
  assert.equal(
    occurrences(source, "</CadenceDataRow>"),
    fixture.boundaries.length,
    `${fixture.filename} closes every migrated row boundary`,
  )
  assert.equal(
    occurrences(source, '<span class="hud-data-value">'),
    fixture.boundaries.length,
    `${fixture.filename} keeps every complete value node caller-owned`,
  )
  assert.doesNotMatch(
    source,
    /<div\b[^>]*class="hud-data-row"/,
    `${fixture.filename} has no raw hud-data-row roots`,
  )
  assert.doesNotMatch(
    source,
    /<span\b[^>]*class="hud-data-label"/,
    `${fixture.filename} has no raw label spans`,
  )

  let reconstructedSource = reconstructCards(source, fixture.cardCount, fixture.filename).replace(
    dataRowImport,
    "",
  )

  for (const boundary of fixture.boundaries) {
    assert.equal(
      occurrences(reconstructedSource, boundary.migratedOpen),
      1,
      `${fixture.filename} inventories each migrated opening boundary exactly once`,
    )
    reconstructedSource = reconstructedSource.replace(
      boundary.migratedOpen,
      boundary.originalOpen,
    )

    assert.equal(
      occurrences(reconstructedSource, boundary.migratedClose),
      1,
      `${fixture.filename} inventories each migrated closing boundary exactly once`,
    )
    reconstructedSource = reconstructedSource.replace(
      boundary.migratedClose,
      boundary.originalClose,
    )
  }

  assert.doesNotMatch(
    reconstructedSource,
    /CadenceDataRow/,
    `${fixture.filename} reconstruction strips only the new import and boundaries`,
  )
  assert.equal(
    createHash("sha256").update(reconstructedSource).digest("hex"),
    fixture.foundationSha256,
    `${fixture.filename} reconstructs its immutable 608a300 base source byte-for-byte`,
  )
}

console.log(
  `data_row_readiness_apps_migration_test passed (${scenarioLedger.length} semantic scenarios)`,
)
