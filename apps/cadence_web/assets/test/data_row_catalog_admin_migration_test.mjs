import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {pageTitleCallerNames, peelCadencePageTitle} from "./page_title_test_support.mjs"

assert.equal(
  process.versions.node,
  "24.16.0",
  "catalog/admin data-row contracts use pinned Node 24.16.0",
)

const base = "608a300628437af68efa8d20941a2d9e8e5ea5ba"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const cardBodyClass = "card-body p-6"
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const panelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const panelHeaderClass =
  "flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"

const occurrences = (source, fragment) => source.split(fragment).length - 1

const peelCadenceBreadcrumbs = (source, label) => {
  const importCount = occurrences(source, breadcrumbsImport)
  const openingCount = occurrences(source, "<CadenceBreadcrumbs>")
  const closingCount = occurrences(source, "</CadenceBreadcrumbs>")

  if (importCount === 0) {
    assert.equal(openingCount, 0, `${label} has no unimported breadcrumb opening`)
    assert.equal(closingCount, 0, `${label} has no unimported breadcrumb closing`)
    return source
  }

  assert.equal(importCount, 1, `${label} has one exact breadcrumb import`)
  assert.equal(openingCount, 1, `${label} has one exact breadcrumb opening`)
  assert.equal(closingCount, 1, `${label} has one exact breadcrumb closing`)

  const openingMatch = source.match(/^( *)<CadenceBreadcrumbs>$/m)
  assert.ok(openingMatch, `${label} has an explicitly bounded breadcrumb opening`)
  const indent = openingMatch[1]
  const wrapperOpening = `${indent}<CadenceBreadcrumbs>`
  const wrapperClosing = `${indent}</CadenceBreadcrumbs>`
  const nativeOpening = `${indent}<nav
${indent}  aria-label="Breadcrumb"
${indent}  class="${breadcrumbNavClass}"
${indent}>`

  assert.equal(occurrences(source, wrapperOpening), 1, `${label} opening indentation is exact`)
  assert.equal(occurrences(source, wrapperClosing), 1, `${label} closing indentation is exact`)

  const peeled = source
    .replace(breadcrumbsImport, "")
    .replace(wrapperOpening, nativeOpening)
    .replace(wrapperClosing, `${indent}</nav>`)

  assert.equal(occurrences(peeled, "CadenceBreadcrumbs"), 0, `${label} breadcrumb peel is exact`)
  return peeled
}

const peelCadencePageHeaderFrame = source =>
  source
    .replace(pageHeaderImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")

const peelCadencePanels = (source, file) => {
  if (file !== "AdminRuntime.vue") return source

  return source
    .replace(panelImport, "")
    .replaceAll(
      `    <CadencePanel
      class="card bg-base-200 border border-base-300"
      header-class="${panelHeaderClass}"
    >
      <template #header>`,
      `    <section class="card bg-base-200 border border-base-300">
      <div class="${panelHeaderClass}">`,
    )
    .replace(
      `    <CadencePanel
      v-if="selection.detail"
      :id="selection.detail.id"
      class="card bg-base-200 border border-base-300"
      header-class="${panelHeaderClass}"
    >
      <template #header>`,
      `    <section
      v-if="selection.detail"
      :id="selection.detail.id"
      class="card bg-base-200 border border-base-300"
    >
      <div class="${panelHeaderClass}">`,
    )
    .replaceAll("      </template>", "      </div>")
    .replaceAll("    </CadencePanel>", "    </section>")
}

const boundary = ({indent, directives = [], labelAttribute, labelMarkup, valueBinding}) => {
  const attributes = [
    ...directives,
    'row-class="hud-data-row"',
    'label-class="hud-data-label"',
    labelAttribute,
  ]

  return Object.freeze({
    opening: `${indent}<CadenceDataRow\n${attributes
      .map((attribute) => `${indent}  ${attribute}`)
      .join("\n")}\n${indent}>\n`,
    closing: `\n${indent}</CadenceDataRow>`,
    indent,
    labelMarkup,
    originalOpening: `${indent}<div${
      directives.length === 0 ? "" : ` ${directives.join(" ")}`
    } class="hud-data-row">`,
    valueBinding,
  })
}

const foundations = Object.freeze([
  {
    file: "CatalogImportRunShow.vue",
    sha256: "1ac3fba753c110efca7b751dc43795dc5b7b758c4dbda7e9729875d83d18ae55",
    cardBoundaryCount: 3,
    importBlock: dataRowImport,
    boundaries: [
      boundary({
        indent: "          ",
        labelAttribute: 'label="Revision"',
        labelMarkup: "Revision",
        valueBinding: "{{ mission_model.revision_id }}",
      }),
      boundary({
        indent: "          ",
        labelAttribute: 'label="Declarations"',
        labelMarkup: "Declarations",
        valueBinding: "{{ mission_model.declaration_count }}",
      }),
      boundary({
        indent: "          ",
        labelAttribute: 'label="Plans"',
        labelMarkup: "Plans",
        valueBinding: "{{ mission_model.plan_count }}",
      }),
    ],
  },
  {
    file: "CatalogRevisionShow.vue",
    sha256: "24952f5d2db70ceac1768bdb2255b96568cd5ffe00ef0847fc449ec80990c0b7",
    cardBoundaryCount: 3,
    importBlock: `${dataRowImport}\n`,
    boundaries: [
      boundary({
        indent: "            ",
        directives: ['v-for="row in provenance.rows"', ':key="row.label"'],
        labelAttribute: ':label="row.label"',
        labelMarkup: "{{ row.label }}",
        valueBinding: "row.value",
      }),
      boundary({
        indent: "          ",
        directives: ['v-for="row in mission_model.rows"', ':key="row.label"'],
        labelAttribute: ':label="row.label"',
        labelMarkup: "{{ row.label }}",
        valueBinding: "row.value",
      }),
    ],
  },
  {
    file: "AdminRuntime.vue",
    sha256: "e319d75441cd0ad9fe7e33c4f131edea3471283859b426d177e0b1aa8f0ea7e9",
    cardBoundaryCount: 0,
    importBlock: dataRowImport,
    boundaries: [
      boundary({
        indent: "              ",
        directives: ['v-for="fact in group.facts"', ':key="fact.key"'],
        labelAttribute: ':label="fact.label"',
        labelMarkup: "{{ fact.label }}",
        valueBinding: "{{ fact.value }}",
      }),
      boundary({
        indent: "              ",
        directives: ['v-for="pair in section.pairs"', ':key="pair.key"'],
        labelAttribute: ':label="pair.label"',
        labelMarkup: "{{ pair.label }}",
        valueBinding: "{{ pair.value }}",
      }),
    ],
  },
])

const count = (source, pattern) => source.match(pattern)?.length ?? 0
const digest = (source) => createHash("sha256").update(source).digest("hex")
let reconstructedBoundaryCount = 0

for (const foundation of foundations) {
  const source = await readFile(resolve(vueDirectory, foundation.file), "utf8")
  const pageTitleCompatibleSource = pageTitleCallerNames.includes(foundation.file)
    ? peelCadencePageTitle(source, foundation.file)
    : source
  const expectedCardImportCount = foundation.cardBoundaryCount === 0 ? 0 : 1

  assert.equal(
    source.split(cardImport).length - 1,
    expectedCardImportCount,
    `${foundation.file} has its exact CadenceCard import count`,
  )
  assert.equal(
    count(source, /^import CadenceCard\b/gm),
    expectedCardImportCount,
    `${foundation.file} has its exact CadenceCard import declaration count`,
  )

  let cardOpeningCount = 0
  let dataRowSource = peelCadencePanels(
    peelCadencePageHeaderFrame(
      peelCadenceBreadcrumbs(pageTitleCompatibleSource, foundation.file),
    ),
    foundation.file,
  ).replace(cardImport, "")

  dataRowSource = dataRowSource.replace(
    /^([ \t]*)<CadenceCard\b([\s\S]*?)>$/gm,
    (_opening, indentation, attributes) => {
      const bodyAttributePattern = /(?:\n[ \t]*| )body-class="card-body p-6"/

      assert.match(
        attributes,
        bodyAttributePattern,
        `${foundation.file} CadenceCard boundary ${cardOpeningCount + 1} has the exact body class`,
      )
      assert.equal(
        attributes.match(/body-class=/g)?.length,
        1,
        `${foundation.file} CadenceCard boundary ${cardOpeningCount + 1} has one body-class prop`,
      )

      cardOpeningCount += 1

      return `${indentation}<section${attributes.replace(bodyAttributePattern, "")}>\n${indentation}  <div class="${cardBodyClass}">`
    },
  )

  let cardClosingCount = 0
  dataRowSource = dataRowSource.replace(
    /^([ \t]*)<\/CadenceCard>$/gm,
    (_closing, indentation) => {
      cardClosingCount += 1
      return `${indentation}  </div>\n${indentation}</section>`
    },
  )

  assert.equal(
    cardOpeningCount,
    foundation.cardBoundaryCount,
    `${foundation.file} has its exact p-6 card opening-boundary count`,
  )
  assert.equal(
    cardClosingCount,
    foundation.cardBoundaryCount,
    `${foundation.file} has its exact p-6 card closing-boundary count`,
  )
  assert.doesNotMatch(
    dataRowSource,
    /CadenceCard/,
    `${foundation.file} card reconstruction strips only its exact import and boundaries`,
  )

  assert.equal(
    dataRowSource.split(foundation.importBlock).length - 1,
    1,
    `${foundation.file} imports CadenceDataRow exactly once`,
  )
  assert.equal(
    count(dataRowSource, /<CadenceDataRow\b/g),
    foundation.boundaries.length,
    `${foundation.file} has exactly its expected CadenceDataRow boundaries`,
  )
  assert.equal(
    count(dataRowSource, /row-class="hud-data-row"/g),
    foundation.boundaries.length,
    `${foundation.file} keeps every row class caller-authored`,
  )
  assert.equal(
    count(dataRowSource, /label-class="hud-data-label"/g),
    foundation.boundaries.length,
    `${foundation.file} keeps every label class caller-authored`,
  )
  assert.doesNotMatch(
    dataRowSource,
    /<div\b[^>]*class="[^"]*\bhud-data-row\b[^"]*"[^>]*>/,
    `${foundation.file} has no raw hud-data-row root`,
  )

  let reconstructed = dataRowSource.replace(foundation.importBlock, "")

  for (const expectedBoundary of foundation.boundaries) {
    const openingCount = reconstructed.split(expectedBoundary.opening).length - 1
    assert.equal(openingCount, 1, `${foundation.file} boundary opening is exact and unique`)

    const openingIndex = reconstructed.indexOf(expectedBoundary.opening)
    const slotStart = openingIndex + expectedBoundary.opening.length
    const closingIndex = reconstructed.indexOf(expectedBoundary.closing, slotStart)
    assert.ok(closingIndex > slotStart, `${foundation.file} boundary closing follows its opening`)

    const callerSlot = reconstructed.slice(slotStart, closingIndex)
    assert.match(
      callerSlot,
      /^\s*<span class="hud-data-value(?: |")/,
      `${foundation.file} value root remains physically caller-owned`,
    )
    assert.ok(
      callerSlot.includes(expectedBoundary.valueBinding),
      `${foundation.file} value binding remains physically caller-owned`,
    )

    const original =
      `${expectedBoundary.originalOpening}\n` +
      `${expectedBoundary.indent}  <span class="hud-data-label">` +
      `${expectedBoundary.labelMarkup}</span>\n${callerSlot}\n` +
      `${expectedBoundary.indent}</div>`

    reconstructed =
      reconstructed.slice(0, openingIndex) +
      original +
      reconstructed.slice(closingIndex + expectedBoundary.closing.length)
    reconstructedBoundaryCount += 1
  }

  assert.doesNotMatch(
    reconstructed,
    /CadenceDataRow/,
    `${foundation.file} reconstruction strips only the import and expected boundaries`,
  )
  assert.equal(
    digest(reconstructed),
    foundation.sha256,
    `${foundation.file} reconstructs exact base ${base}`,
  )
}

assert.equal(foundations.length, 3, "exactly three owned Vue files are migrated")
assert.equal(reconstructedBoundaryCount, 7, "exactly seven data-row boundaries reconstruct")

console.log("data_row_catalog_admin_migration_test passed (3 files, 7 boundaries)")
