import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

const foundationBase = "00c264585863a89a76d55484b777a7e73eda7fa5"
const importLine = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
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
  const source = await readFile(componentPath, "utf8")
  const reconstructed = reconstructBaseSource(source, migration.boundaryCount, migration.file)

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

  const parsed = parse(source, {filename: componentPath})
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
