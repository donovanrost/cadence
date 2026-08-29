import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers,
} from "./compact_page_header_body_frame_test_support.mjs"
import {pageTitleCallerNames, peelCadencePageTitle} from "./page_title_test_support.mjs"
import {integrationRequire} from "./reka_adapter_test_support.mjs"
import {peelResidualCadenceCardBeforeOlderLayers} from "./residual_cadence_cards_test_support.mjs"

const foundationBase = "00c264585863a89a76d55484b777a7e73eda7fa5"
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const importLine = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const pageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const tableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const bodyClass = "card-body p-6"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const {compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")

const migrations = Object.freeze([
  Object.freeze({
    file: "CatalogArtifactShow.vue",
    boundaryCount: 2,
    baseSha256: "3b45572e73b7fdc944097ad39a7971fbb44522646f3a8d5e28a96e65a4d5cd8d",
  }),
  Object.freeze({
    file: "CatalogDatabaseShow.vue",
    boundaryCount: 4,
    baseSha256: "9cbf960006731294835272a41f318787a078ec95c02332caeca483a05a0c3ce8",
  }),
  Object.freeze({
    file: "CatalogImportRunShow.vue",
    boundaryCount: 3,
    baseSha256: "6d3987d293ce425bb7513e77d7353c8f03e005f5b21a4189eb252fbc857ac95a",
  }),
  Object.freeze({
    file: "CatalogRevisionShow.vue",
    boundaryCount: 3,
    baseSha256: "9be08e75440da200ecc9f27f51f54712c1b0aa1ce8fb58210dfade2c5cfcc0f9",
  }),
])

const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, value) => source.split(value).length - 1

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

const tableFrameBoundaries = Object.freeze({
  "CatalogArtifactShow.vue": Object.freeze({
    openings: Object.freeze([
      Object.freeze({
        frame: '          <CadenceTableFrame id="catalog-artifact-runs-table">',
        table: '          <table id="catalog-artifact-runs-table" class="table">',
      }),
    ]),
    frameClosing: "          </CadenceTableFrame>",
    tableClosing: "          </table>",
  }),
  "CatalogDatabaseShow.vue": Object.freeze({
    openings: Object.freeze([
      Object.freeze({
        frame: '        <CadenceTableFrame v-else id="catalog-revisions-table">',
        table: '        <table v-else id="catalog-revisions-table" class="table">',
      }),
      Object.freeze({
        frame: '        <CadenceTableFrame v-else id="catalog-import-runs-table">',
        table: '        <table v-else id="catalog-import-runs-table" class="table">',
      }),
    ]),
    frameClosing: "        </CadenceTableFrame>",
    tableClosing: "        </table>",
  }),
})
const peelTableFrames = (source, file) => {
  const boundary = tableFrameBoundaries[file]
  if (!boundary) return source

  assert.equal(occurrences(source, tableFrameImport), 1, `${file} imports CadenceTableFrame once`)
  assert.equal(
    source.match(/^import CadenceTableFrame\b/gm)?.length,
    1,
    `${file} has exactly one CadenceTableFrame import declaration`,
  )
  assert.equal(
    source.match(/<CadenceTableFrame\b/g)?.length,
    boundary.openings.length,
    `${file} has its exact table-frame opening count`,
  )
  assert.equal(
    occurrences(source, boundary.frameClosing),
    boundary.openings.length,
    `${file} has its exact table-frame closing count`,
  )

  let peeled = source.replace(tableFrameImport, "")

  for (const opening of boundary.openings) {
    assert.equal(occurrences(peeled, opening.frame), 1, `${file} table-frame opening is exact`)
    peeled = peeled.replace(opening.frame, opening.table)
  }

  peeled = peeled.replaceAll(boundary.frameClosing, boundary.tableClosing)
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

const reconstructBaseSource = (source, boundaryCount, file) => {
  assert.equal(
    source.split(importLine).length - 1,
    1,
    `${file} imports CadenceCard exactly once`,
  )
  assert.equal(
    source.match(/^import CadenceCard\b/gm)?.length,
    1,
    `${file} has exactly one CadenceCard import declaration`,
  )

  let openingCount = 0
  let reconstructed = source.replace(importLine, "")

  reconstructed = reconstructed.replace(
    /^([ \t]*)<CadenceCard\b([\s\S]*?)>$/gm,
    (_opening, indentation, attributes) => {
      const bodyAttributePattern = /(?:\n[ \t]*| )body-class="card-body p-6"/

      assert.match(
        attributes,
        bodyAttributePattern,
        `${file} CadenceCard boundary ${openingCount + 1} has the exact body class`,
      )
      assert.equal(
        attributes.match(/body-class=/g)?.length,
        1,
        `${file} CadenceCard boundary ${openingCount + 1} has one body-class prop`,
      )

      openingCount += 1

      return `${indentation}<section${attributes.replace(bodyAttributePattern, "")}>\n${indentation}  <div class="${bodyClass}">`
    },
  )

  let closingCount = 0
  reconstructed = reconstructed.replace(/^([ \t]*)<\/CadenceCard>$/gm, (_closing, indentation) => {
    closingCount += 1
    return `${indentation}  </div>\n${indentation}</section>`
  })

  assert.equal(openingCount, boundaryCount, `${file} has the frozen opening-boundary count`)
  assert.equal(closingCount, boundaryCount, `${file} has the frozen closing-boundary count`)

  return reconstructed
}

assert.equal(process.versions.node, "24.16.0", "catalog card migration uses pinned Node 24.16.0")
assert.equal(
  migrations.reduce((count, migration) => count + migration.boundaryCount, 0),
  12,
  "the immutable catalog ledger contains exactly 12 conventional shells",
)

const sources = new Map()

for (const migration of migrations) {
  const componentPath = resolve(testDirectory, `../vue/${migration.file}`)
  const currentSource = await readFile(componentPath, "utf8")
  const compactHeaderBodyCompatibleSource =
    peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers(currentSource, migration.file)
  const source = peelResidualCadenceCardBeforeOlderLayers(
    compactHeaderBodyCompatibleSource,
    migration.file,
  )
  const pageTitleCompatibleSource = pageTitleCallerNames.includes(migration.file)
    ? peelCadencePageTitle(source, migration.file)
    : source
  const reconstructed = reconstructBaseSource(
    peelPageHeaderFrame(
      peelTableFrames(
        peelCadenceBreadcrumbs(pageTitleCompatibleSource, migration.file),
        migration.file,
      ),
    ),
    migration.boundaryCount,
    migration.file,
  )

  assert.equal(
    sha256(reconstructed),
    migration.baseSha256,
    `${migration.file} reconstructs base ${foundationBase} byte-for-byte`,
  )
  assert.doesNotMatch(
    source,
    /<section\b[^>]*\bclass="[^"]*\bcard\b[^"]*"[^>]*>\n[ \t]*<div class="card-body p-6">/,
    `${migration.file} leaves no conventional raw p-6 card shell`,
  )

  const parsed = parse(currentSource, {filename: componentPath})
  assert.deepEqual(parsed.errors, [], `${migration.file} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.template, `${migration.file} retains an SFC template`)

  const compiled = compileTemplate({
    id: `card-catalog-${migration.file}`,
    filename: componentPath,
    source: parsed.descriptor.template.content,
  })

  assert.deepEqual(compiled.errors, [], `${migration.file} template compiles`)
  sources.set(migration.file, source)
}

const artifactSource = sources.get("CatalogArtifactShow.vue")

assert.equal(
  artifactSource.match(
    /<section\n        v-else\n        id="catalog-artifact-runs-card"\n        class="card border border-base-300 bg-base-200"\n      >\n        <div class="card-body p-0">/g,
  )?.length,
  1,
  "CatalogArtifactShow keeps the p-0 runs table card raw and unchanged",
)

console.log(
  `card_catalog_migration_test passed (12 boundaries across ${migrations.length} compiled templates)`,
)
