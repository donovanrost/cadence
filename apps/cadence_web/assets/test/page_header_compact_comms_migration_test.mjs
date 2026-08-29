import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {execFileSync} from "node:child_process"
import {readFileSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import test from "node:test"
import {pageTitleCallerNames, peelCadencePageTitle} from "./page_title_test_support.mjs"
import {peelCadenceNoticeFrames} from "./notice_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  "24.16.0",
  "page header compact comms migration test requires pinned Node 24.16.0",
)

const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const migrationImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const tableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
const frameOpening = '<CadencePageHeaderFrame variant="compact">'
const frameClosing = "</CadencePageHeaderFrame>"
const nativeOpening = '<header class="border-b border-primary/20 pb-4">'
const nativeClosing = "</header>"
const callers = [
  "apps/cadence_web/assets/vue/ProviderAccountNew.vue",
  "apps/cadence_web/assets/vue/ProviderAccountShow.vue",
  "apps/cadence_web/assets/vue/CommsProviderNew.vue",
  "apps/cadence_web/assets/vue/CommsProviderShow.vue",
  "apps/cadence_web/assets/vue/CommsTransportNew.vue",
  "apps/cadence_web/assets/vue/CommsTransportShow.vue",
  "apps/cadence_web/assets/vue/CommsValidation.vue",
  "apps/cadence_web/assets/vue/CommsRoutingNew.vue",
  "apps/cadence_web/assets/vue/CommsRoutingShow.vue",
  "apps/cadence_web/assets/vue/CommsGroundStationForm.vue",
  "apps/cadence_web/assets/vue/CommsGroundStationShow.vue",
]

function occurrences(source, value) {
  return source.split(value).length - 1
}

function sha256(source) {
  return createHash("sha256").update(source).digest("hex")
}

const cadenceDetailsFrameCounts = Object.freeze({
  "CommsProviderShow.vue": 1,
  "CommsRoutingShow.vue": 1,
  "CommsTransportNew.vue": 1,
  "CommsTransportShow.vue": 1,
  "ProviderAccountShow.vue": 1,
})

function peelCadenceDetailsFrames(source, expectedCount, label) {
  const expectedImportCount = expectedCount > 0 ? 1 : 0

  assert.equal(occurrences(source, cadenceDetailsFrameImport), expectedImportCount, `${label} details import count`)
  assert.equal(source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, expectedCount, `${label} details opening count`)
  assert.equal(occurrences(source, "</CadenceDetailsFrame>"), expectedCount, `${label} details closing count`)

  const peeled = source
    .replace(cadenceDetailsFrameImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
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

function peelTableFrames(source, caller) {
  if (!caller.endsWith("/CommsProviderShow.vue")) return source

  const openings = [
    {
      frame: '            <CadenceTableFrame v-else :id="profiles.service.table_id">',
      table: '            <table v-else :id="profiles.service.table_id" class="table">',
    },
    {
      frame: '            <CadenceTableFrame v-else :id="profiles.delivery.table_id">',
      table: '            <table v-else :id="profiles.delivery.table_id" class="table">',
    },
  ]
  const frameClosing = "            </CadenceTableFrame>"
  const tableClosing = "            </table>"

  assert.equal(occurrences(source, tableFrameImport), 1, "expected exactly one table import")
  assert.equal(
    source.match(/^import CadenceTableFrame\b/gm)?.length,
    1,
    "expected exactly one table import declaration",
  )
  assert.equal(
    source.match(/<CadenceTableFrame\b/g)?.length,
    openings.length,
    "expected exactly two table frames",
  )
  assert.equal(
    occurrences(source, frameClosing),
    openings.length,
    "expected exactly two table-frame closings",
  )

  let peeled = source.replace(tableFrameImport, "")

  for (const opening of openings) {
    assert.equal(occurrences(peeled, opening.frame), 1, "expected one exact table opening")
    peeled = peeled.replace(opening.frame, opening.table)
  }

  peeled = peeled.replaceAll(frameClosing, tableClosing)
  assert.doesNotMatch(peeled, /CadenceTableFrame/)
  return peeled
}

for (const caller of callers) {
  test(`${caller} has one compact frame and reconstructs its exact parent source`, () => {
    const source = readFileSync(resolve(repositoryRoot, caller), "utf8")

    assert.equal(occurrences(source, migrationImport), 1, "expected exactly one frame import")
    assert.equal(occurrences(source, frameOpening), 1, "expected exactly one frame opening")
    assert.equal(occurrences(source, frameClosing), 1, "expected exactly one frame closing")
    assert.doesNotMatch(source, /<header\b/, "expected no residual native header")

    const filename = caller.slice(caller.lastIndexOf("/") + 1)
    const pageTitleCompatibleSource = pageTitleCallerNames.includes(filename)
      ? peelCadencePageTitle(source, filename)
      : source
    const reconstructed = peelTableFrames(
      peelCadenceBreadcrumbs(
        peelCadenceDetailsFrames(
          peelCadenceNoticeFrames(pageTitleCompatibleSource, filename),
          cadenceDetailsFrameCounts[filename] ?? 0,
          caller,
        ),
        caller,
      ),
      caller,
    )
      .replace(migrationImport, "")
      .replace(frameOpening, nativeOpening)
      .replace(frameClosing, nativeClosing)
    const parentSource = execFileSync("git", ["-C", repositoryRoot, "show", `${parent}:${caller}`], {
      encoding: "utf8",
    })

    assert.equal(
      sha256(reconstructed),
      sha256(parentSource),
      "reconstructed SHA-256 must match the exact parent source",
    )
  })
}
