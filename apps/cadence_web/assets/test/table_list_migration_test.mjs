import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {peelCadencePaginationFrame} from "./pagination_frame_test_support.mjs"

const predecessor = "c720c80701148764113420bf8f62ddbd07f439e8"
const importWithoutSemicolon =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const importWithBlankLine = `${importWithoutSemicolon}\n`
const importWithSemicolon =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue";\n'
const testDirectory = dirname(fileURLToPath(import.meta.url))
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")

const fixtures = Object.freeze([
  Object.freeze({
    file: "AdminOrganizationList.vue",
    id: "admin-orgs-table",
    indentation: "  ",
    importLine: importWithBlankLine,
    predecessorSha256: "a40163d97f403117e58ccc4e2338c76d1e1c5c5d96cac636e4651d30cf3ebcaf",
  }),
  Object.freeze({
    file: "CatalogDatabaseTable.vue",
    id: "catalog-databases-table",
    indentation: "  ",
    importLine: importWithoutSemicolon,
    predecessorSha256: "97cf3163799f89d80e6f254d5ae84e3ee0177d9992dcd89e9b1b3b12b7dca2fd",
  }),
  Object.freeze({
    file: "CommsRoutingList.vue",
    id: "routing-rules-table",
    indentation: "  ",
    importLine: importWithBlankLine,
    predecessorSha256: "ad0e9cddc6ae751f00f92eac67cd81a6412d75c9d443a21054802ce57eb7bc09",
  }),
  Object.freeze({
    file: "CommsProviderTable.vue",
    id: "mission-providers-table",
    indentation: "  ",
    importLine: importWithoutSemicolon,
    predecessorSha256: "16515b3198ae4f3ebafe6ddce55d0e035a393bd029958576d3a5cb921cfda581",
  }),
  Object.freeze({
    file: "CommsGroundStationList.vue",
    id: "ground-stations-table",
    indentation: "    ",
    importLine: importWithoutSemicolon,
    predecessorSha256: "a30c8122f8314e4e386708e1f2ba6a4bf163dc763a3879bd1f8034894d709a2e",
  }),
  Object.freeze({
    file: "CommsTransportList.vue",
    id: "transports-table",
    indentation: "    ",
    importLine: importWithSemicolon,
    predecessorSha256: "7a9ad282915fd8aa8e9d3ed1f2663a9b7170ce4e89cc2c96ff29acf260c019c3",
  }),
  Object.freeze({
    file: "MissionTable.vue",
    id: "mission-list-table",
    indentation: "  ",
    importLine: importWithoutSemicolon,
    predecessorSha256: "6589381280b0a77895a3a8beaaa6bbad01b247ce91f136624af7fefab64d7a6f",
  }),
  Object.freeze({
    file: "SpacecraftTypeList.vue",
    id: "spacecraft-profiles-table",
    indentation: "  ",
    importLine: importWithBlankLine,
    predecessorSha256: "2537026b313d3dff90a164531a2c100846c0a181658505178b2248f01e32088d",
  }),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")

const replaceExactlyOnce = (source, before, after, label) => {
  assert.equal(occurrences(source, before), 1, `${label} is exact and unique`)
  return source.replace(before, after)
}

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `table-list migration uses pinned Node ${expectedNodeVersion}`,
)
assert.equal(fixtures.length, 8, "the migration ledger contains exactly eight owned callers")

let importerCount = 0
let openingTagCount = 0
let closingTagCount = 0

for (const fixture of fixtures) {
  const componentPath = resolve(testDirectory, `../vue/${fixture.file}`)
  const source = await readFile(componentPath, "utf8")
  const prePaginationSource =
    fixture.file === "CommsGroundStationList.vue" ||
    fixture.file === "CommsTransportList.vue"
      ? peelCadencePaginationFrame(source, fixture.file)
      : source
  const componentOpening =
    `${fixture.indentation}<CadenceTableFrame id="${fixture.id}">`
  const componentClosing = `${fixture.indentation}</CadenceTableFrame>`
  const predecessorOpening =
    `${fixture.indentation}<table id="${fixture.id}" class="table">`
  const predecessorClosing = `${fixture.indentation}</table>`

  assert.equal(
    occurrences(prePaginationSource, fixture.importLine),
    1,
    `${fixture.file} imports CadenceTableFrame exactly once`,
  )
  assert.equal(
    prePaginationSource.match(/^import CadenceTableFrame\b/gm)?.length,
    1,
    `${fixture.file} has exactly one CadenceTableFrame importer`,
  )
  assert.equal(
    occurrences(prePaginationSource, componentOpening),
    1,
    `${fixture.file} has its one exact CadenceTableFrame opening tag`,
  )
  assert.equal(
    occurrences(prePaginationSource, componentClosing),
    1,
    `${fixture.file} has its one exact CadenceTableFrame closing tag`,
  )
  assert.doesNotMatch(
    prePaginationSource,
    /<table\b/i,
    `${fixture.file} has no residual native table`,
  )

  const reconstructed = replaceExactlyOnce(
    replaceExactlyOnce(
      replaceExactlyOnce(
        prePaginationSource,
        fixture.importLine,
        "",
        `${fixture.file} import reconstruction`,
      ),
      componentOpening,
      predecessorOpening,
      `${fixture.file} opening reconstruction`,
    ),
    componentClosing,
    predecessorClosing,
    `${fixture.file} closing reconstruction`,
  )

  assert.doesNotMatch(
    reconstructed,
    /CadenceTableFrame/,
    `${fixture.file} reconstruction peels only the component shell and import`,
  )
  assert.equal(
    sha256(reconstructed),
    fixture.predecessorSha256,
    `${fixture.file} reconstructs exact predecessor ${predecessor}`,
  )

  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${fixture.file} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${fixture.file} keeps its script setup block`)
  assert.ok(parsed.descriptor.template, `${fixture.file} keeps its SFC template`)

  const compiled = compileScript(parsed.descriptor, {
    id: `table-list-migration-${fixture.file}`,
    inlineTemplate: true,
  })

  assert.match(compiled.content, /render|_sfc_render/, `${fixture.file} compiles its actual template`)

  importerCount += 1
  openingTagCount += 1
  closingTagCount += 1
}

assert.equal(importerCount, 8, "exactly eight CadenceTableFrame importers are covered")
assert.equal(openingTagCount, 8, "exactly eight CadenceTableFrame openings are covered")
assert.equal(closingTagCount, 8, "exactly eight CadenceTableFrame closings are covered")

console.log(
  `table_list_migration_test passed (8 compiled SFCs, 8 exact ${predecessor} reconstructions)`,
)
