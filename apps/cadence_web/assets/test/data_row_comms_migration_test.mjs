import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "comms data-row contracts use pinned Node 24.16.0")

const lines = (...sourceLines) => sourceLines.join("\n")
const boundary = (migrated, base) => Object.freeze({migrated, base})
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const panelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const panelHeaderClass =
  "flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
const rawReviewShell = `        <section
          :id="form.review.configuration_summary_id"
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body p-0">`
const testDirectory = dirname(fileURLToPath(import.meta.url))

const peelCadencePageHeaderFrame = source =>
  source
    .replace(pageHeaderImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")

const contracts = Object.freeze([
  Object.freeze({
    filename: "CommsProviderShow.vue",
    baseSha256: "157d7b85c82e4d1479815fa0641259e3e55396c4044c8c40c5d8c98b2d4658a0",
    cardCount: 3,
    rowCount: 3,
    importInsertion: dataRowImport,
    boundaries: Object.freeze([
      boundary(
        lines(
          "              <CadenceDataRow",
          '                v-for="row in card.rows"',
          '                :key="row.label"',
          '                row-class="hud-data-row"',
          '                label-class="hud-data-label"',
          '                :label="row.label"',
          "              >",
        ),
        lines(
          '              <div v-for="row in card.rows" :key="row.label" class="hud-data-row">',
          '                <span class="hud-data-label">{{ row.label }}</span>',
        ),
      ),
      boundary(
        lines(
          "                <CadenceDataRow",
          '                  row-class="hud-data-row"',
          '                  label-class="hud-data-label"',
          '                  :label="`v${version.version}`"',
          "                >",
        ),
        lines(
          '                <div class="hud-data-row">',
          '                  <span class="hud-data-label">v{{ version.version }}</span>',
        ),
      ),
      boundary(
        lines(
          "          <CadenceDataRow",
          '            v-for="row in diagnostics.rows"',
          '            :key="row.label"',
          '            row-class="hud-data-row"',
          '            label-class="hud-data-label"',
          '            :label="row.label"',
          "          >",
        ),
        lines(
          '          <div v-for="row in diagnostics.rows" :key="row.label" class="hud-data-row">',
          '            <span class="hud-data-label">{{ row.label }}</span>',
        ),
      ),
    ]),
  }),
  Object.freeze({
    filename: "CommsTransportShow.vue",
    baseSha256: "6130fc910f199cc63f132cd5de9e21b4a8500b20f617ed42391600017739cea1",
    cardCount: 2,
    rowCount: 2,
    importInsertion: `${dataRowImport}\n`,
    boundaries: Object.freeze([
      boundary(
        lines(
          "            <CadenceDataRow",
          '              v-for="detail in transport.capability.details"',
          '              :key="detail.label"',
          '              row-class="hud-data-row"',
          '              label-class="hud-data-label"',
          '              :label="detail.label"',
          "            >",
        ),
        lines(
          "            <div",
          '              v-for="detail in transport.capability.details"',
          '              :key="detail.label"',
          '              class="hud-data-row"',
          "            >",
          '              <span class="hud-data-label">{{ detail.label }}</span>',
        ),
      ),
      boundary(
        lines(
          "              <CadenceDataRow",
          '                row-class="hud-data-row"',
          '                label-class="hud-data-label"',
          '                :label="version.label"',
          "              >",
        ),
        lines(
          '              <div class="hud-data-row">',
          '                <span class="hud-data-label">{{ version.label }}</span>',
        ),
      ),
    ]),
  }),
  Object.freeze({
    filename: "CommsRoutingShow.vue",
    baseSha256: "cc8afdb990f092f21b813b909c77ce09f8258f6f4f589d812e04727d510e594b",
    cardCount: 2,
    rowCount: 2,
    importInsertion: dataRowImport,
    boundaries: Object.freeze([
      boundary(
        lines(
          "            <CadenceDataRow",
          '              v-for="detail in rule.details"',
          '              :key="detail.label"',
          '              row-class="hud-data-row"',
          '              label-class="hud-data-label"',
          '              :label="detail.label"',
          "            >",
        ),
        lines(
          '            <div v-for="detail in rule.details" :key="detail.label" class="hud-data-row">',
          '              <span class="hud-data-label">{{ detail.label }}</span>',
        ),
      ),
      boundary(
        lines(
          "              <CadenceDataRow",
          '                v-for="artifact in rule.runtime_artifacts"',
          '                :key="artifact.label"',
          '                row-class="hud-data-row"',
          '                label-class="hud-data-label"',
          '                :label="artifact.label"',
          "              >",
        ),
        lines(
          "              <div",
          '                v-for="artifact in rule.runtime_artifacts"',
          '                :key="artifact.label"',
          '                class="hud-data-row"',
          "              >",
          '                <span class="hud-data-label">{{ artifact.label }}</span>',
        ),
      ),
    ]),
  }),
  Object.freeze({
    filename: "CommsGroundStationShow.vue",
    baseSha256: "0af998eb9dec77dcc9572f163b83456bb249284e2a4bb9bb78c46bab2febfd70",
    cardCount: 2,
    rowCount: 1,
    importInsertion: `${dataRowImport}\n`,
    boundaries: Object.freeze([
      boundary(
        lines(
          "            <CadenceDataRow",
          '              v-for="detail in ground_station.details"',
          '              :key="detail.label"',
          '              row-class="hud-data-row"',
          '              label-class="hud-data-label"',
          '              :label="detail.label"',
          "            >",
        ),
        lines(
          '            <div v-for="detail in ground_station.details" :key="detail.label" class="hud-data-row">',
          '              <span class="hud-data-label">{{ detail.label }}</span>',
        ),
      ),
    ]),
  }),
  Object.freeze({
    filename: "CommsTransportNew.vue",
    baseSha256: "9aea9fcec003ae7713a636184b312812193f5f6d99de8d6d81c7b75e75b58e23",
    cardCount: 1,
    rowCount: 1,
    importInsertion: dataRowImport,
    boundaries: Object.freeze([
      boundary(
        lines(
          "                <CadenceDataRow",
          '                  v-for="row in form.provider_derived.configuration.rows"',
          '                  :key="row.label"',
          '                  row-class="hud-data-row"',
          '                  label-class="hud-data-label"',
          '                  :label="row.label"',
          "                >",
        ),
        lines(
          "                <div",
          '                  v-for="row in form.provider_derived.configuration.rows"',
          '                  :key="row.label"',
          '                  class="hud-data-row"',
          "                >",
          '                  <span class="hud-data-label">{{ row.label }}</span>',
        ),
      ),
    ]),
  }),
])

assert.equal(
  contracts.reduce((total, contract) => total + contract.rowCount, 0),
  9,
  "the comms slice owns exactly nine data rows",
)

const occurrenceCount = (source, token) => source.split(token).length - 1
const replaceExactlyOnce = (source, current, replacement, label) => {
  assert.equal(occurrenceCount(source, current), 1, `${label} occurs exactly once`)
  return source.replace(current, replacement)
}
const panelBoundaries = Object.freeze([
  Object.freeze({
    label: "service profile panel",
    migrated: lines(
      "        <CadencePanel",
      '          :id="profiles.service.id"',
      '          class="card bg-base-200 border border-base-300"',
      `          header-class="${panelHeaderClass}"`,
      "        >",
      "          <template #header>",
    ),
    base: lines(
      '        <section :id="profiles.service.id" class="card bg-base-200 border border-base-300">',
      `          <div class="${panelHeaderClass}">`,
    ),
  }),
  Object.freeze({
    label: "delivery profile panel",
    migrated: lines(
      "        <CadencePanel",
      '          :id="profiles.delivery.id"',
      '          class="card bg-base-200 border border-base-300"',
      `          header-class="${panelHeaderClass}"`,
      "        >",
      "          <template #header>",
    ),
    base: lines(
      '        <section :id="profiles.delivery.id" class="card bg-base-200 border border-base-300">',
      `          <div class="${panelHeaderClass}">`,
    ),
  }),
])

const peelCadencePanels = (source, filename) => {
  if (filename !== "CommsProviderShow.vue") return source

  let peeled = replaceExactlyOnce(source, panelImport, "", "CadencePanel import")

  for (const panelBoundary of panelBoundaries) {
    peeled = replaceExactlyOnce(
      peeled,
      panelBoundary.migrated,
      panelBoundary.base,
      panelBoundary.label,
    )
  }

  const headerClosing = '          </template>\n          <div class="card-body p-0">'
  assert.equal(occurrenceCount(peeled, headerClosing), 2, "exactly two header slot closings peel")
  peeled = peeled.replaceAll(
    headerClosing,
    '          </div>\n          <div class="card-body p-0">',
  )

  assert.equal(
    occurrenceCount(peeled, "        </CadencePanel>"),
    2,
    "exactly two panel closings peel",
  )
  peeled = peeled.replaceAll("        </CadencePanel>", "        </section>")

  assert.doesNotMatch(peeled, /CadencePanel/)
  return peeled
}

const reconstructCards = (source, contract) => {
  assert.equal(
    occurrenceCount(source, cardImport),
    1,
    `${contract.filename} imports CadenceCard exactly once`,
  )
  assert.equal(
    source.match(/<CadenceCard\b/g)?.length ?? 0,
    contract.cardCount,
    `${contract.filename} has its exact CadenceCard opening count`,
  )
  assert.equal(
    occurrenceCount(source, "</CadenceCard>"),
    contract.cardCount,
    `${contract.filename} has its exact CadenceCard closing count`,
  )
  assert.equal(
    occurrenceCount(source, 'body-class="card-body p-6"'),
    contract.cardCount,
    `${contract.filename} has one exact p-6 body boundary per card`,
  )

  if (contract.filename === "CommsTransportNew.vue") {
    assert.equal(occurrenceCount(source, rawReviewShell), 1, "the raw p-0 review card stays exact")
  }

  let openingCount = 0
  let reconstructed = source.replace(cardImport, "")

  reconstructed = reconstructed.replace(
    /^([ \t]*)<CadenceCard\b([^>]*)>\n/gm,
    (_opening, indentation, rawAttributes) => {
      openingCount += 1
      assert.equal(
        occurrenceCount(rawAttributes, 'body-class="card-body p-6"'),
        1,
        `${contract.filename} card boundary ${openingCount} owns one exact body class`,
      )

      const sectionAttributes = rawAttributes
        .replace(/\n[ \t]*body-class="card-body p-6"/, "")
        .replace(/ body-class="card-body p-6"/, "")

      assert.doesNotMatch(sectionAttributes, /body-class=/)
      return (
        `${indentation}<section${sectionAttributes}>\n` +
        `${indentation}  <div class="card-body p-6">\n`
      )
    },
  )

  assert.equal(openingCount, contract.cardCount, `${contract.filename} reconstructs every card opening`)

  let closingCount = 0
  reconstructed = reconstructed.replace(/^([ \t]*)<\/CadenceCard>$/gm, (_closing, indentation) => {
    closingCount += 1
    return `${indentation}  </div>\n${indentation}</section>`
  })

  assert.equal(closingCount, contract.cardCount, `${contract.filename} reconstructs every card closing`)

  if (contract.filename === "CommsTransportNew.vue") {
    assert.equal(
      occurrenceCount(reconstructed, rawReviewShell),
      1,
      "the pre-card source keeps the raw p-0 review card",
    )
  }

  assert.doesNotMatch(
    reconstructed,
    /CadenceCard/,
    `${contract.filename} pre-card source has no residual primitive`,
  )
  return reconstructed
}

for (const contract of contracts) {
  const componentPath = resolve(testDirectory, `../vue/${contract.filename}`)
  const source = await readFile(componentPath, "utf8")

  assert.equal(occurrenceCount(source, dataRowImport), 1, `${contract.filename} imports CadenceDataRow once`)
  assert.equal(
    source.match(/<CadenceDataRow\b/g)?.length ?? 0,
    contract.rowCount,
    `${contract.filename} has its expected opening row boundaries`,
  )
  assert.equal(
    occurrenceCount(source, "</CadenceDataRow>"),
    contract.rowCount,
    `${contract.filename} has its expected closing row boundaries`,
  )
  assert.equal(
    occurrenceCount(source, 'row-class="hud-data-row"'),
    contract.rowCount,
    `${contract.filename} preserves every row class through the primitive`,
  )
  assert.equal(
    occurrenceCount(source, 'label-class="hud-data-label"'),
    contract.rowCount,
    `${contract.filename} preserves every label class through the primitive`,
  )
  assert.doesNotMatch(
    source,
    /<div\b[^>]*\bclass="hud-data-row"/,
    `${contract.filename} has no raw hud-data-row root`,
  )
  assert.equal(
    contract.boundaries.length,
    contract.rowCount,
    `${contract.filename} declares every migrated row boundary`,
  )

  const predecessorSource = peelCadencePanels(
    peelCadencePageHeaderFrame(source),
    contract.filename,
  )
  let reconstructedBase = replaceExactlyOnce(
    reconstructCards(predecessorSource, contract),
    contract.importInsertion,
    "",
    `${contract.filename} import insertion`,
  )

  for (const [index, rowBoundary] of contract.boundaries.entries()) {
    reconstructedBase = replaceExactlyOnce(
      reconstructedBase,
      rowBoundary.migrated,
      rowBoundary.base,
      `${contract.filename} row boundary ${index + 1}`,
    )
  }

  reconstructedBase = reconstructedBase.replaceAll("</CadenceDataRow>", "</div>")

  assert.doesNotMatch(reconstructedBase, /CadenceDataRow/)
  assert.equal(
    createHash("sha256").update(reconstructedBase).digest("hex"),
    contract.baseSha256,
    `${contract.filename} reconstructs its immutable base after removing only the import and expected boundaries`,
  )
}
