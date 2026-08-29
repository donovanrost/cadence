#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {expectedNodeVersion, integrationRequire} from "./reka_adapter_test_support.mjs"
import {peelCadenceListToolbarFrame} from "./list_toolbar_frame_test_support.mjs"
import {peelCadencePaginationFrame} from "./pagination_frame_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const predecessor = "c720c80701148764113420bf8f62ddbd07f439e8"
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const tableImport = 'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const testDirectory = dirname(fileURLToPath(import.meta.url))
const {compileScript, compileTemplate, parse} = integrationRequire("@vue/compiler-sfc")

assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `table migration contracts use pinned Node ${expectedNodeVersion}`,
)

const occurrenceCount = (source, fragment) => source.split(fragment).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const peelCadenceDetailsFrames = (source, expectedCount, label) => {
  const expectedImportCount = expectedCount > 0 ? 1 : 0

  assert.equal(occurrenceCount(source, cadenceDetailsFrameImport), expectedImportCount, `${label} details import count`)
  assert.equal(source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, expectedCount, `${label} details opening count`)
  assert.equal(occurrenceCount(source, "</CadenceDetailsFrame>"), expectedCount, `${label} details closing count`)

  const peeled = source
    .replace(cadenceDetailsFrameImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
}

const peelCadenceBreadcrumbs = (source, label) => {
  const importCount = occurrenceCount(source, breadcrumbsImport)
  const openingCount = occurrenceCount(source, "<CadenceBreadcrumbs>")
  const closingCount = occurrenceCount(source, "</CadenceBreadcrumbs>")

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

  assert.equal(
    occurrenceCount(source, wrapperOpening),
    1,
    `${label} opening indentation is exact`,
  )
  assert.equal(
    occurrenceCount(source, wrapperClosing),
    1,
    `${label} closing indentation is exact`,
  )

  const peeled = source
    .replace(breadcrumbsImport, "")
    .replace(wrapperOpening, nativeOpening)
    .replace(wrapperClosing, `${indent}</nav>`)

  assert.equal(
    occurrenceCount(peeled, "CadenceBreadcrumbs"),
    0,
    `${label} breadcrumb peel is exact`,
  )
  return peeled
}

const replaceExact = (source, migrated, base, expectedCount, label) => {
  assert.equal(occurrenceCount(source, migrated), expectedCount, label)
  return source.split(migrated).join(base)
}

const fixtures = Object.freeze([
  Object.freeze({
    filename: "SpacecraftList.vue",
    instances: 2,
    predecessorSha256: "326e13217f78374848f1180d06c296faaaa1ccc458ea2f4d824cb6c938699b01",
    openings: Object.freeze([
      Object.freeze({
        migrated: '          <CadenceTableFrame id="spacecraft-vehicles-table">',
        base: '          <table id="spacecraft-vehicles-table" class="table">',
      }),
      Object.freeze({
        migrated: '          <CadenceTableFrame id="spacecraft-profiles-preview-table">',
        base: '          <table id="spacecraft-profiles-preview-table" class="table">',
      }),
    ]),
    closing: Object.freeze({
      migrated: "          </CadenceTableFrame>",
      base: "          </table>",
    }),
  }),
  Object.freeze({
    filename: "SpacecraftTypeShow.vue",
    instances: 1,
    predecessorSha256: "f5702cc3e3c2442b0ca336191af42702d8868cf07d5b4f611cdede6fa8e34e7a",
    openings: Object.freeze([
      Object.freeze({
        migrated:
          '        <CadenceTableFrame id="spacecraft-profile-version-history" class="mt-3">',
        base: '        <table id="spacecraft-profile-version-history" class="table mt-3">',
      }),
    ]),
    closing: Object.freeze({
      migrated: "        </CadenceTableFrame>",
      base: "        </table>",
    }),
  }),
  Object.freeze({
    filename: "MissionOverview.vue",
    instances: 1,
    predecessorSha256: "0b7715971ab577e9f39cc1be3dab540f4a5e43f75b12af54022f67e635483450",
    openings: Object.freeze([
      Object.freeze({
        migrated: '        <CadenceTableFrame v-else id="mission-spacecraft-readiness">',
        base: '        <table v-else id="mission-spacecraft-readiness" class="table">',
      }),
    ]),
    closing: Object.freeze({
      migrated: "        </CadenceTableFrame>",
      base: "        </table>",
    }),
  }),
  Object.freeze({
    filename: "CommsProviderShow.vue",
    instances: 2,
    predecessorSha256: "62423c3eabeba1dc03c02ad3830e5ff5433575a8037395dcebb04f2fc97433f8",
    openings: Object.freeze([
      Object.freeze({
        migrated: '            <CadenceTableFrame v-else :id="profiles.service.table_id">',
        base: '            <table v-else :id="profiles.service.table_id" class="table">',
      }),
      Object.freeze({
        migrated: '            <CadenceTableFrame v-else :id="profiles.delivery.table_id">',
        base: '            <table v-else :id="profiles.delivery.table_id" class="table">',
      }),
    ]),
    closing: Object.freeze({
      migrated: "            </CadenceTableFrame>",
      base: "            </table>",
    }),
  }),
])

let importerCount = 0
let instanceCount = 0

for (const fixture of fixtures) {
  const componentPath = resolve(testDirectory, `../vue/${fixture.filename}`)
  const source = await readFile(componentPath, "utf8")
  const prePaginationSource =
    fixture.filename === "SpacecraftList.vue"
      ? peelCadencePaginationFrame(
          peelCadenceListToolbarFrame(source, fixture.filename),
          fixture.filename,
        )
      : source

  assert.equal(
    occurrenceCount(prePaginationSource, tableImport),
    1,
    `${fixture.filename} import count`,
  )
  importerCount += 1

  assert.equal(
    occurrenceCount(prePaginationSource, "<CadenceTableFrame"),
    fixture.instances,
    `${fixture.filename} opening count`,
  )
  assert.equal(
    occurrenceCount(prePaginationSource, "</CadenceTableFrame>"),
    fixture.instances,
    `${fixture.filename} closing count`,
  )
  assert.doesNotMatch(
    prePaginationSource,
    /<\/?table\b/,
    `${fixture.filename} has no residual native table`,
  )
  instanceCount += fixture.instances

  let reconstructed = replaceExact(
    peelCadenceBreadcrumbs(
      peelCadenceDetailsFrames(
        prePaginationSource,
        fixture.filename === "CommsProviderShow.vue" ? 1 : 0,
        fixture.filename,
      ),
      fixture.filename,
    ),
    tableImport,
    "",
    1,
    `${fixture.filename} import reconstruction`,
  )

  for (const [index, opening] of fixture.openings.entries()) {
    reconstructed = replaceExact(
      reconstructed,
      opening.migrated,
      opening.base,
      1,
      `${fixture.filename} opening ${index + 1} reconstruction`,
    )
  }

  reconstructed = replaceExact(
    reconstructed,
    fixture.closing.migrated,
    fixture.closing.base,
    fixture.instances,
    `${fixture.filename} closing reconstruction`,
  )

  assert.doesNotMatch(reconstructed, /CadenceTableFrame/)
  assert.equal(
    sha256(reconstructed),
    fixture.predecessorSha256,
    `${fixture.filename} reconstructs its exact source at ${predecessor}`,
  )

  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${fixture.filename} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${fixture.filename} keeps its script setup block`)
  assert.ok(parsed.descriptor.template, `${fixture.filename} keeps its template block`)

  const compiledScript = compileScript(parsed.descriptor, {
    id: `table-spacecraft-provider-${fixture.filename}`,
  })
  const compiledTemplate = compileTemplate({
    source: parsed.descriptor.template.content,
    filename: componentPath,
    id: `table-spacecraft-provider-${fixture.filename}`,
  })

  assert.match(compiledScript.content, /defineComponent|_defineComponent/)
  assert.deepEqual(compiledTemplate.errors, [], `${fixture.filename} template compiles`)
  assert.match(compiledTemplate.code, /render|_sfc_render/)
}

assert.equal(importerCount, 4, "the cohort has exactly four CadenceTableFrame importers")
assert.equal(instanceCount, 6, "the cohort has exactly six CadenceTableFrame instances")

console.log(
  "table_spacecraft_provider_migration_test passed (4 importers, 6 exact shell reconstructions)",
)
