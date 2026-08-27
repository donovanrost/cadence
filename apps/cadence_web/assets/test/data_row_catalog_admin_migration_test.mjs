import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(
  process.versions.node,
  "24.16.0",
  "catalog/admin data-row contracts use pinned Node 24.16.0",
)

const base = "608a300628437af68efa8d20941a2d9e8e5ea5ba"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'

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

  assert.equal(
    source.split(foundation.importBlock).length - 1,
    1,
    `${foundation.file} imports CadenceDataRow exactly once`,
  )
  assert.equal(
    count(source, /<CadenceDataRow\b/g),
    foundation.boundaries.length,
    `${foundation.file} has exactly its expected CadenceDataRow boundaries`,
  )
  assert.equal(
    count(source, /row-class="hud-data-row"/g),
    foundation.boundaries.length,
    `${foundation.file} keeps every row class caller-authored`,
  )
  assert.equal(
    count(source, /label-class="hud-data-label"/g),
    foundation.boundaries.length,
    `${foundation.file} keeps every label class caller-authored`,
  )
  assert.doesNotMatch(
    source,
    /<div\b[^>]*class="[^"]*\bhud-data-row\b[^"]*"[^>]*>/,
    `${foundation.file} has no raw hud-data-row root`,
  )

  let reconstructed = source.replace(foundation.importBlock, "")

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
