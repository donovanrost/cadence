import assert from "node:assert/strict"
import {createHash} from "node:crypto"

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
    "OpsAlarms.vue",
    10906,
    "3f42ec1bf7bb8689619502dc217c85cc4a23ac564e59960ce44a4b4097ff7eb3",
  ),
  migration(
    "OpsCommands.vue",
    12866,
    "ab14e929b2a5ed4ad6d4ee7550334d09e1e55b19e47500797f6ff7e85d71e663",
  ),
  migration(
    "OpsContactDetail.vue",
    24272,
    "a7904263feaae824be7ce19a11fa723795aea7f47bf1c651042f7abe5a7cc1fc",
  ),
  migration(
    "OpsContactPlanShow.vue",
    19311,
    "63a66b7e958fbea0b3169be56947e7863c750eeb61af13d32dc65e6a291255bf",
  ),
  migration(
    "OpsContactRequirementList.vue",
    5448,
    "5724202fe66d9f0bc1fb7cb7835fd58c61fdee88e66da8ee17c94a1c54cf1e58",
  ),
  migration(
    "OpsContactRequirementNew.vue",
    22708,
    "b0497574fc871c28ccf770f0e5e348cab9dd10210c013a7e5427ab8349cdc22e",
  ),
  migration(
    "OpsContactRequirementShow.vue",
    13957,
    "2949c1786da80a62900cfb8d9405b2df204243024d1801757680058f98a1b6a8",
  ),
  migration(
    "OpsContactRequirementTemplate.vue",
    33179,
    "ee6459debfa08e045c8fd0d66cb26353abb14828815b86ed47615f396819f474",
  ),
  migration(
    "OpsContactSchedule.vue",
    25545,
    "734bccee8aba69d6a4339f402f98a2e875c6b5c49e1e279d823da79bf3780480",
  ),
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
  migration(
    "OpsFleetPlanning.vue",
    10958,
    "07bd6f32a75c65ffdb79fbecc2e6d378943fa50c8fd1da0c00e50a1222aca401",
  ),
  migration(
    "OpsFleetPlanningNew.vue",
    10027,
    "925446942fa5dfc46ab0673d744de5f3406892f7b6cbf95d2a3b426dbeb7c58d",
    '  <CadenceOpsViewport :id="header.id">',
    `  <section :id="header.id" class="${opsViewportClass}">`,
  ),
  migration(
    "OpsFleetPlanningRun.vue",
    22517,
    "144610c87b58a1fd3868bbee07eba8cacf02e9152ecf20edf7be12175da3a766",
    '  <CadenceOpsViewport\n    :id="page.id"\n    :aria-busy="planning"\n  >',
    `  <section\n    :id="page.id"\n    :aria-busy="planning"\n    class="${opsViewportClass}"\n  >`,
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
  exclusion(
    "OpsDashboardSnapshot.vue",
    1637,
    "8c2ec5ea8553a18e09f0829ce3c2773922a010d080bdab3dd7147d7e118e5cfe",
    '  <section :id="snapshot.id" class="h-full overflow-y-auto bg-base-100 p-6">',
    "p-6 padded snapshot viewport is a distinct layout variant",
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

  assert.equal(occurrences(source, entry.importLine), 1, `${entry.file} viewport import count`)
  assert.equal(source.match(/^import CadenceOpsViewport\b/gm)?.length, 1)
  assert.equal(occurrences(source, entry.opening), 1, `${entry.file} exact viewport opening`)
  assert.equal(occurrences(source, entry.closing), 1, `${entry.file} exact viewport closing`)
  assert.equal(source.match(/<CadenceOpsViewport\b/g)?.length, 1)
  assert.equal(source.match(/<\/CadenceOpsViewport>/g)?.length, 1)

  const predecessor = source
    .replace(entry.importLine, "")
    .replace(entry.opening, entry.predecessorOpening)
    .replace(entry.closing, entry.predecessorClosing)

  assert.doesNotMatch(predecessor, /CadenceOpsViewport/)
  return predecessor
}
