import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {execFileSync} from "node:child_process"
import {readFileSync, realpathSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {pageTitleCallerNames, peelCadencePageTitle} from "./page_title_test_support.mjs"
import {
  hoverTableRowCallerNames,
  peelCadenceHoverTableRows,
} from "./hover_table_row_test_support.mjs"
import {peelCadencePaginationFrame} from "./pagination_frame_test_support.mjs"

const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const importLine =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const tableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const validationMessageImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const frameOpening = '<CadencePageHeaderFrame variant="compact">'
const frameClosing = "</CadencePageHeaderFrame>"
const nativeOpening = '<header class="border-b border-primary/20 pb-4">'
const nativeClosing = "</header>"
const hoverTableRowCallers = new Set(hoverTableRowCallerNames)
const callers = [
  "apps/cadence_web/assets/vue/CatalogDatabaseNew.vue",
  "apps/cadence_web/assets/vue/CatalogImportRunShow.vue",
  "apps/cadence_web/assets/vue/CatalogRevisionShow.vue",
  "apps/cadence_web/assets/vue/CatalogDatabaseShow.vue",
  "apps/cadence_web/assets/vue/AdminOrganizationInvite.vue",
  "apps/cadence_web/assets/vue/AdminOrganizationNew.vue",
  "apps/cadence_web/assets/vue/AdminRuntime.vue",
  "apps/cadence_web/assets/vue/AdminOrganizationShow.vue",
  "apps/cadence_web/assets/vue/ApplicationHost.vue"
]
const tableFrameBoundaries = Object.freeze({
  "apps/cadence_web/assets/vue/CatalogDatabaseShow.vue": Object.freeze({
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
  "apps/cadence_web/assets/vue/AdminOrganizationShow.vue": Object.freeze({
    openings: Object.freeze([
      Object.freeze({
        frame: '          <CadenceTableFrame id="org-members-table">',
        table: '          <table id="org-members-table" class="table">',
      }),
      Object.freeze({
        frame: '        <CadenceTableFrame id="service-identities-table">',
        table: '        <table id="service-identities-table" class="table">',
      }),
    ]),
    closings: Object.freeze([
      Object.freeze({frame: "          </CadenceTableFrame>", table: "          </table>"}),
      Object.freeze({frame: "        </CadenceTableFrame>", table: "        </table>"}),
    ]),
  }),
})

function occurrences(source, value) {
  return source.split(value).length - 1
}

function sha256(source) {
  return createHash("sha256").update(source).digest("hex")
}

function peelCadenceBreadcrumbs(source, label) {
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

function peelValidationMessage(source, caller) {
  if (caller !== "apps/cadence_web/assets/vue/ApplicationHost.vue") return source

  return source
    .replace(validationMessageImport, "")
    .replace(
      `                <CadenceValidationMessage
                  v-for="error in field.errors"
                  :key="error"
                >`,
      `                <p
                  v-for="error in field.errors"
                  :key="error"
                  class="mt-1.5 text-sm text-error"
                >`
    )
    .replace(
      "                >{{ error }}</CadenceValidationMessage>",
      "                >{{ error }}</p>"
    )
}

function peelTableFrames(source, caller) {
  const boundary = tableFrameBoundaries[caller]
  if (!boundary) return source

  assert.equal(occurrences(source, tableFrameImport), 1, `${caller} must have one table import`)
  assert.equal(
    source.match(/^import CadenceTableFrame\b/gm)?.length,
    1,
    `${caller} must have one table import declaration`
  )
  assert.equal(
    source.match(/<CadenceTableFrame\b/g)?.length,
    boundary.openings.length,
    `${caller} must have its exact table-frame count`
  )
  assert.equal(
    source.match(/<\/CadenceTableFrame>/g)?.length,
    boundary.openings.length,
    `${caller} must close every table frame`
  )

  let peeled = source.replace(tableFrameImport, "")

  for (const opening of boundary.openings) {
    assert.equal(occurrences(peeled, opening.frame), 1, `${caller} table opening must be exact`)
    peeled = peeled.replace(opening.frame, opening.table)
  }

  if (boundary.closings) {
    for (const closing of boundary.closings) {
      assert.equal(occurrences(peeled, closing.frame), 1, `${caller} table closing must be exact`)
      peeled = peeled.replace(closing.frame, closing.table)
    }
  } else {
    assert.equal(
      occurrences(peeled, boundary.frameClosing),
      boundary.openings.length,
      `${caller} table closings must be exact`
    )
    peeled = peeled.replaceAll(boundary.frameClosing, boundary.tableClosing)
  }

  assert.doesNotMatch(peeled, /CadenceTableFrame/)
  return peeled
}

assert.equal(process.versions.node, "24.16.0", "migration proof requires Node 24.16.0")
assert.equal(
  realpathSync(process.execPath),
  realpathSync(pinnedNode),
  `migration proof must run with ${pinnedNode}`
)

for (const caller of callers) {
  const source = readFileSync(resolve(repositoryRoot, caller), "utf8")
  const file = caller.split("/").at(-1)
  const pageTitleCompatibleSource = pageTitleCallerNames.includes(file)
    ? peelCadencePageTitle(source, file)
    : source
  const preHoverTableRowSource = hoverTableRowCallers.has(file)
    ? peelCadenceHoverTableRows(pageTitleCompatibleSource, file)
    : pageTitleCompatibleSource
  const prePaginationSource =
    caller === "apps/cadence_web/assets/vue/ApplicationHost.vue"
      ? peelCadencePaginationFrame(preHoverTableRowSource, caller)
      : preHoverTableRowSource

  assert.equal(occurrences(source, importLine), 1, `${caller} must have one frame import`)
  assert.equal(occurrences(source, frameOpening), 1, `${caller} must have one compact frame`)
  assert.equal(occurrences(source, frameClosing), 1, `${caller} must close one compact frame`)
  assert.equal(
    occurrences(source, nativeOpening),
    0,
    `${caller} must have no residual native compact page header`
  )

  const reconstructed = peelTableFrames(
    peelValidationMessage(peelCadenceBreadcrumbs(prePaginationSource, caller), caller),
    caller
  )
    .replace(importLine, "")
    .replace(frameOpening, nativeOpening)
    .replace(frameClosing, nativeClosing)
  const parentSource = execFileSync("git", ["show", `${parent}:${caller}`], {
    cwd: repositoryRoot
  })

  assert.equal(
    sha256(Buffer.from(reconstructed, "utf8")),
    sha256(parentSource),
    `${caller} must reconstruct byte-for-byte to ${parent}`
  )
}

console.log(`ok - ${callers.length} compact admin/catalog page-header migrations reconstruct ${parent}`)
