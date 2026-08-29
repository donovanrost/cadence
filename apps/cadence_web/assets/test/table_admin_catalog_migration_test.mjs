import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFileSync, realpathSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

const baseCommit = "c720c80701148764113420bf8f62ddbd07f439e8"
const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const importLine = 'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const componentClosing = "</CadenceTableFrame>"
const nativeClosing = "</table>"
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")

const callers = Object.freeze([
  Object.freeze({
    path: "apps/cadence_web/assets/vue/CatalogArtifactShow.vue",
    baseSha256: "0705b89ff6c96c0aae798158abe005312dfc49f529bce6ca8c2ba0b66b082138",
    boundaries: Object.freeze([
      Object.freeze({
        componentOpening: '          <CadenceTableFrame id="catalog-artifact-runs-table">',
        nativeOpening: '          <table id="catalog-artifact-runs-table" class="table">',
      }),
    ]),
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/CatalogDatabaseShow.vue",
    baseSha256: "0d3c7454831b7685b68b9d7664567efa0810a6b45a13b4f66cdf15771a3b21ea",
    boundaries: Object.freeze([
      Object.freeze({
        componentOpening: '        <CadenceTableFrame v-else id="catalog-revisions-table">',
        nativeOpening: '        <table v-else id="catalog-revisions-table" class="table">',
      }),
      Object.freeze({
        componentOpening: '        <CadenceTableFrame v-else id="catalog-import-runs-table">',
        nativeOpening: '        <table v-else id="catalog-import-runs-table" class="table">',
      }),
    ]),
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/AdminOrganizationShow.vue",
    baseSha256: "9e49be6256869cf80cca614dc6ad911d4acba1220dda5db013dc2e8ac2bc3ab0",
    boundaries: Object.freeze([
      Object.freeze({
        componentOpening: '          <CadenceTableFrame id="org-members-table">',
        nativeOpening: '          <table id="org-members-table" class="table">',
      }),
      Object.freeze({
        componentOpening: '        <CadenceTableFrame id="service-identities-table">',
        nativeOpening: '        <table id="service-identities-table" class="table">',
      }),
    ]),
  }),
])

const occurrences = (source, value) => source.split(value).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")

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

assert.equal(process.versions.node, "24.16.0", "migration proof requires Node 24.16.0")
assert.equal(
  realpathSync(process.execPath),
  realpathSync(pinnedNode),
  `migration proof must run with ${pinnedNode}`,
)
assert.equal(callers.length, 3, "the immutable ledger contains exactly three importers")
assert.equal(
  callers.reduce((count, caller) => count + caller.boundaries.length, 0),
  5,
  "the immutable ledger contains exactly five table frames",
)

for (const caller of callers) {
  const componentPath = resolve(repositoryRoot, caller.path)
  const source = readFileSync(componentPath, "utf8")

  assert.equal(occurrences(source, importLine), 1, `${caller.path} imports the frame once`)
  assert.equal(
    source.match(/^import CadenceTableFrame\b/gm)?.length,
    1,
    `${caller.path} has one frame import declaration`,
  )
  assert.equal(
    source.match(/<CadenceTableFrame\b/g)?.length,
    caller.boundaries.length,
    `${caller.path} has its frozen frame count`,
  )
  assert.equal(
    occurrences(source, componentClosing),
    caller.boundaries.length,
    `${caller.path} closes every frame`,
  )
  assert.doesNotMatch(source, /<table\b|<\/table>/, `${caller.path} has no residual native table`)
  assert.doesNotMatch(
    source,
    /<CadenceTableFrame\b[^>]*\bclass="table"/,
    `${caller.path} omits the redundant table class`,
  )

  let reconstructed = peelCadenceBreadcrumbs(source, caller.path).replace(importLine, "")

  for (const boundary of caller.boundaries) {
    assert.equal(
      occurrences(reconstructed, boundary.componentOpening),
      1,
      `${caller.path} keeps each expected component opening exactly once`,
    )
    reconstructed = reconstructed.replace(boundary.componentOpening, boundary.nativeOpening)
  }

  reconstructed = reconstructed.replaceAll(componentClosing, nativeClosing)
  assert.doesNotMatch(
    reconstructed,
    /CadenceTableFrame/,
    `${caller.path} reconstruction peels only the frame shells and import`,
  )

  const baseSource = execFileSync("git", ["show", `${baseCommit}:${caller.path}`], {
    cwd: repositoryRoot,
    encoding: "utf8",
  })

  assert.equal(sha256(baseSource), caller.baseSha256, `${caller.path} pins the immutable base bytes`)
  assert.equal(
    sha256(reconstructed),
    caller.baseSha256,
    `${caller.path} reconstructs ${baseCommit} byte-for-byte`,
  )

  const parsed = parse(source, {filename: componentPath})
  assert.deepEqual(parsed.errors, [], `${caller.path} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${caller.path} retains its script setup block`)
  assert.ok(parsed.descriptor.template, `${caller.path} retains its template block`)
  assert.doesNotThrow(
    () =>
      compileScript(parsed.descriptor, {
        id: `table-admin-catalog-${caller.path}`,
        inlineTemplate: true,
      }),
    `${caller.path} compiles as an actual SFC`,
  )
}

console.log("table_admin_catalog_migration_test passed (3 importers, 5 reconstructed tables)")
