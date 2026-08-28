import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {installDom, loadSfc} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  "24.16.0",
  "comms card migration contracts use pinned Node 24.16.0",
)

const base = "00c264585863a89a76d55484b777a7e73eda7fa5"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const panelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const pageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const panelHeaderClass =
  "flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
const digest = (value) => createHash("sha256").update(value).digest("hex")
const count = (value, pattern) => value.match(pattern)?.length ?? 0
const occurrenceCount = (value, token) => value.split(token).length - 1
const replaceExactlyOnce = (value, current, replacement, label) => {
  assert.equal(occurrenceCount(value, current), 1, `${label} occurs exactly once`)
  return value.replace(current, replacement)
}
const lines = (...sourceLines) => sourceLines.join("\n")
const peelPageHeaderFrame = (source) =>
  source
    .replace(pageHeaderFrameImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")
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
  if (filename === "CommsValidation.vue") {
    let peeled = replaceExactlyOnce(source, panelImport, "", "CommsValidation.vue import reconstruction")

    peeled = replaceExactlyOnce(
      peeled,
      lines(
        "      <CadencePanel",
        '        v-for="group in validation.finding_groups"',
        '        :id="group.id"',
        '        :key="group.id"',
        '        class="card bg-base-200 border border-base-300"',
        `        header-class="${panelHeaderClass}"`,
        "      >",
        "        <template #header>",
      ),
      lines(
        "      <section",
        '        v-for="group in validation.finding_groups"',
        '        :id="group.id"',
        '        :key="group.id"',
        '        class="card bg-base-200 border border-base-300"',
        "      >",
        `        <div class="${panelHeaderClass}">`,
      ),
      "CommsValidation.vue opening reconstruction",
    )
    peeled = replaceExactlyOnce(
      peeled,
      '        </template>\n        <div class="card-body p-0">',
      '        </div>\n        <div class="card-body p-0">',
      "CommsValidation.vue header close reconstruction",
    )
    peeled = replaceExactlyOnce(
      peeled,
      "      </CadencePanel>",
      "      </section>",
      "CommsValidation.vue panel close reconstruction",
    )

    assert.doesNotMatch(peeled, /CadencePanel/)
    return peeled
  }

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

const contracts = Object.freeze([
  Object.freeze({
    filename: "CommsProviderShow.vue",
    cardCount: 3,
    baseSha256: "781f097d6465c5503eef3c913ac7a4504b20d1880120e865bd0bd3ccbece9ce1",
  }),
  Object.freeze({
    filename: "CommsGroundStationShow.vue",
    cardCount: 2,
    baseSha256: "9b388648c7e93939d892858a8f46452e562a7b1abf0f4d643095daa8a638b915",
  }),
  Object.freeze({
    filename: "CommsOverview.vue",
    cardCount: 2,
    baseSha256: "2c377d7c0f5904311de59a10dd517b21175ecef95eb1b5d8df5a6474932d9a96",
  }),
  Object.freeze({
    filename: "CommsRoutingShow.vue",
    cardCount: 2,
    baseSha256: "c9fc2890c048adfd25867ef001d6f9bf7b9498c5c8c29925b69f3ee731713648",
  }),
  Object.freeze({
    filename: "CommsTransportShow.vue",
    cardCount: 2,
    baseSha256: "a44430ea8b4745330958cc548ed5f778faf54f5b550887c57c7448b257a1c400",
  }),
  Object.freeze({
    filename: "CommsTransportNew.vue",
    cardCount: 1,
    baseSha256: "5f041f98099cfca066bf4ffc1b5b89566e52252a98ac259c3461a82e2ddcf1ba",
  }),
  Object.freeze({
    filename: "CommsValidation.vue",
    cardCount: 1,
    baseSha256: "cc0e873a0497b17647ea706bcf9dc2b0d02e7ca5cfcfb1708c7fdf00f1ec51a2",
  }),
])

assert.deepEqual(
  contracts.map(({cardCount}) => cardCount),
  [3, 2, 2, 2, 2, 1, 1],
  "the authoritative per-file comms card ledger is frozen",
)
assert.equal(
  contracts.reduce((total, {cardCount}) => total + cardCount, 0),
  13,
  "the comms slice owns exactly thirteen immediate card shells",
)

const sources = new Map()

for (const contract of contracts) {
  const componentPath = resolve(testDirectory, `../vue/${contract.filename}`)
  const source = await readFile(componentPath, "utf8")
  sources.set(contract.filename, {componentPath, source})

  assert.equal(
    source.split(cardImport).length - 1,
    1,
    `${contract.filename} imports CadenceCard exactly once`,
  )
  assert.equal(
    count(source, /<CadenceCard\b/g),
    contract.cardCount,
    `${contract.filename} has its exact CadenceCard opening count`,
  )
  assert.equal(
    count(source, /<\/CadenceCard>/g),
    contract.cardCount,
    `${contract.filename} has its exact CadenceCard closing count`,
  )
  assert.equal(
    count(source, /body-class="card-body p-6"/g),
    contract.cardCount,
    `${contract.filename} assigns the exact body class to every migrated card`,
  )
  assert.doesNotMatch(
    source,
    /<section\b[^>]*\bclass="[^"]*\bcard\b[^"]*"[^>]*>\s*<div class="card-body p-6">/,
    `${contract.filename} has no conventional raw immediate p-6 shell`,
  )

  const predecessorSource = peelCadencePanels(
    peelPageHeaderFrame(source),
    contract.filename,
  )
  let openingCount = 0
  let reconstructed = predecessorSource.replace(cardImport, "")

  reconstructed = reconstructed.replace(
    /^([ \t]*)<CadenceCard\b([^>]*)>\n/gm,
    (_opening, indentation, rawAttributes) => {
      openingCount += 1
      assert.equal(
        count(rawAttributes, /body-class="card-body p-6"/g),
        1,
        `${contract.filename} boundary ${openingCount} owns one exact body-class`,
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

  assert.equal(openingCount, contract.cardCount)

  let closingCount = 0
  reconstructed = reconstructed.replace(/^([ \t]*)<\/CadenceCard>$/gm, (_closing, indentation) => {
    closingCount += 1
    return `${indentation}  </div>\n${indentation}</section>`
  })

  assert.equal(closingCount, contract.cardCount)
  assert.doesNotMatch(reconstructed, /CadenceCard/)
  assert.equal(
    digest(reconstructed),
    contract.baseSha256,
    `${contract.filename} reconstructs its immutable source at base ${base}`,
  )
}

const transportNewSource = sources.get("CommsTransportNew.vue").source
const rawReviewShell = `        <section
          :id="form.review.configuration_summary_id"
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body p-0">`

assert.equal(
  transportNewSource.split(rawReviewShell).length - 1,
  1,
  "CommsTransportNew keeps its p-0 review table card raw and unchanged",
)

installDom()

for (const contract of contracts) {
  const {componentPath} = sources.get(contract.filename)
  const compiled = await loadSfc(componentPath)

  assert.ok(compiled.descriptor.template, `${contract.filename} retains an SFC template`)
  assert.equal(
    typeof compiled.component.setup,
    "function",
    `${contract.filename} template parses and compiles with the pinned Vue compiler`,
  )
}

console.log("card_comms_migration_test passed (13 boundaries, 7 exact base reconstructions)")
