import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {
  peelCadenceDashboardSettingsSectionFrameBeforeOlderLayers,
} from "./dashboard_settings_section_frame_test_support.mjs"
import {peelCadenceOpsPageBodyFrameBeforeOlderLayers} from "./ops_page_body_frame_test_support.mjs"
import {peelLabeledControlFieldsBeforeOlderLayers} from "./labeled_control_field_test_support.mjs"

export const opsViewportPredecessorCommit = "fef20d7c72b5842b3dcae3e99630a1795b5791b3"
export const opsViewportClass = "h-full overflow-y-auto bg-base-100"
export const opsViewportImport =
  'import CadenceOpsViewport from "./ui/components/CadenceOpsViewport.vue"\n'

const pageOpening = '  <CadenceOpsViewport :id="page.id">'
const nativePageOpening = `  <section :id="page.id" class="${opsViewportClass}">`
const componentClosing = "  </CadenceOpsViewport>"
const nativeClosing = "  </section>"

const migration = (
  file,
  predecessorByteLength,
  predecessorSha256,
  opening = pageOpening,
  predecessorOpening = nativePageOpening,
) =>
  Object.freeze({
    file,
    predecessorCommit: opsViewportPredecessorCommit,
    predecessorByteLength,
    predecessorSha256,
    importLine: opsViewportImport,
    opening,
    predecessorOpening,
    closing: componentClosing,
    predecessorClosing: nativeClosing,
  })

export const opsViewportMigrations = Object.freeze([
  migration(
    "OpsDashboardDirectory.vue",
    12607,
    "95fcf3572a69ad44b90d82c018323b2b6e54e616c78ff340db35c86149b3e468",
  ),
  migration(
    "OpsDashboardLibrary.vue",
    21063,
    "4580ffd9942e653ebed6f8ddcc8098074e35418bacabaa64a050b4c051ddb56e",
  ),
  migration(
    "OpsDashboardNew.vue",
    6630,
    "1927f51f06f1e3a02ae5e5cf2829c6ea4f56d22f5029961ca201220a16bc333f",
  ),
  migration(
    "OpsDashboardPlaylists.vue",
    8864,
    "8a4fcc04ba7e1643f82e47ce8e42bbcff5b2354b38fffc28131e676d3f6232bc",
  ),
  migration(
    "OpsDashboardSettings.vue",
    19272,
    "2c936e742eab32cc55c3fe95979750b885aefb71ebe6cb1c20a57791e9bfd31d",
  ),
])

export const opsViewportCallerNames = Object.freeze(
  opsViewportMigrations.map(({file}) => file),
)

const exclusion = (file, byteLength, sha256, opening, reason) =>
  Object.freeze({file, byteLength, sha256, opening, reason, count: 1})

export const excludedOpsViewportVariants = Object.freeze([
  exclusion(
    "OpsDashboardShare.vue",
    1684,
    "92903b435d264e30dcf569631ccdaa0610a696ac8385199a3d389641003ec009",
    '  <section :id="share.id" class="h-full overflow-y-auto bg-base-100 p-6">',
    "p-6 padded share viewport is a distinct layout variant",
  ),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const opsViewportSha256 = (source) =>
  createHash("sha256").update(source).digest("hex")

export const opsViewportMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const found = opsViewportMigrations.find((entry) => entry.file === file)

  assert.ok(found, `${caller} is an audited CadenceOpsViewport caller`)
  return found
}

export const peelCadenceOpsViewport = (source, caller) => {
  const entry = opsViewportMigrationFor(caller)
  source = peelLabeledControlFieldsBeforeOlderLayers(source, caller)
  const dashboardSettingsCompatibleSource =
    peelCadenceDashboardSettingsSectionFrameBeforeOlderLayers(source, caller)
  const pageBodyCompatibleSource = peelCadenceOpsPageBodyFrameBeforeOlderLayers(
    dashboardSettingsCompatibleSource,
    caller,
  )

  assert.equal(occurrences(pageBodyCompatibleSource, entry.importLine), 1, `${entry.file} viewport import count`)
  assert.equal(pageBodyCompatibleSource.match(/^import CadenceOpsViewport\b/gm)?.length, 1)
  assert.equal(occurrences(pageBodyCompatibleSource, entry.opening), 1, `${entry.file} exact viewport opening`)
  assert.equal(occurrences(pageBodyCompatibleSource, entry.closing), 1, `${entry.file} exact viewport closing`)
  assert.equal(pageBodyCompatibleSource.match(/<CadenceOpsViewport\b/g)?.length, 1)
  assert.equal(pageBodyCompatibleSource.match(/<\/CadenceOpsViewport>/g)?.length, 1)

  const predecessor = pageBodyCompatibleSource
    .replace(entry.importLine, "")
    .replace(entry.opening, entry.predecessorOpening)
    .replace(entry.closing, entry.predecessorClosing)

  assert.doesNotMatch(predecessor, /CadenceOpsViewport/)
  return predecessor
}
