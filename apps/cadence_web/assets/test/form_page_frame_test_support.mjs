import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelCadenceFormSectionFrameBeforeOlderLayers} from "./form_section_frame_test_support.mjs"

export const formPageFramePredecessorCommit =
  "e41d4381a93779d093788bc4c4200cdcce597f29"
export const formPageFramePath =
  "apps/cadence_web/assets/vue/ui/components/CadenceFormPageFrame.vue"
export const formPageFrameClass = "space-y-6 max-w-2xl"
export const formPageFrameImport =
  'import CadenceFormPageFrame from "./ui/components/CadenceFormPageFrame.vue"\n'

const migration = ({
  file,
  predecessorByteLength,
  predecessorBlobId,
  predecessorSha256,
  opening,
  predecessorOpening,
}) =>
  Object.freeze({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    predecessorByteLength,
    predecessorBlobId,
    predecessorSha256,
    opening,
    predecessorOpening,
    closing: "  </CadenceFormPageFrame>",
    predecessorClosing: "  </div>",
  })

export const formPageFrameMigrations = Object.freeze([
  migration({
    file: "CatalogDatabaseNew.vue",
    predecessorByteLength: 2_461,
    predecessorBlobId: "92e1a6cf6da9d20da0828870a7a52219782e9f64",
    predecessorSha256:
      "e13f68e791358cd0b39dad382fc88b9f68cbf066494fdfa4fe2c8d5129447eaa",
    opening: '  <CadenceFormPageFrame :id="page.id">',
    predecessorOpening: '  <div :id="page.id" class="space-y-6 max-w-2xl">',
  }),
  migration({
    file: "CommsGroundStationForm.vue",
    predecessorByteLength: 10_012,
    predecessorBlobId: "68b9175b40dbd088c2fbf2fe8a35fc0bf1ead974",
    predecessorSha256:
      "edd1ab8aa48a31f0a5aada4ae515fdb2674c5d9f6791dfe9c14c981e045fce53",
    opening: '  <CadenceFormPageFrame :id="page.id" :data-mode="mode">',
    predecessorOpening:
      '  <div :id="page.id" class="space-y-6 max-w-2xl" :data-mode="mode">',
  }),
  migration({
    file: "CommsRoutingNew.vue",
    predecessorByteLength: 11_502,
    predecessorBlobId: "0a8f75e8e19e03bb0a1bbc1e435738080b84b109",
    predecessorSha256:
      "e7105ab001c2b56ff8b95f0aa88420af473ae8a95916341924693688d3016706",
    opening: '  <CadenceFormPageFrame :id="page.id">',
    predecessorOpening: '  <div :id="page.id" class="space-y-6 max-w-2xl">',
  }),
  migration({
    file: "SpacecraftTypeNew.vue",
    predecessorByteLength: 17_686,
    predecessorBlobId: "05f48545e7459ef6e258d7d40a050857479d42a7",
    predecessorSha256:
      "63d684bbd5638bea9ad2ee17e53f052a46a73bb278a79ea8dee7e0c429717fa3",
    opening: '  <CadenceFormPageFrame :id="page.id">',
    predecessorOpening: '  <div :id="page.id" class="space-y-6 max-w-2xl">',
  }),
])

export const formPageFrameCallerNames = Object.freeze(
  formPageFrameMigrations.map(({file}) => file),
)

export const formPageFrameSha256 = source =>
  createHash("sha256").update(source).digest("hex")

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const formPageFrameMigrationFor = caller => {
  const file = caller.split("/").at(-1)
  const migrationEntry = formPageFrameMigrations.find(entry => entry.file === file)

  assert.ok(migrationEntry, `${caller} is an audited CadenceFormPageFrame caller`)
  return migrationEntry
}

export const peelCadenceFormPageFrame = (source, caller) => {
  const migrationEntry = formPageFrameMigrationFor(caller)
  const formSectionFrameCompatibleSource = peelCadenceFormSectionFrameBeforeOlderLayers(
    source,
    caller,
  )

  assert.equal(
    occurrences(formSectionFrameCompatibleSource, formPageFrameImport),
    1,
    `${migrationEntry.file} form page frame import`,
  )
  assert.equal(
    occurrences(formSectionFrameCompatibleSource, migrationEntry.opening),
    1,
    `${migrationEntry.file} form page frame opening`,
  )
  assert.equal(
    occurrences(formSectionFrameCompatibleSource, migrationEntry.closing),
    1,
    `${migrationEntry.file} form page frame closing`,
  )

  const predecessor = formSectionFrameCompatibleSource
    .replace(formPageFrameImport, "")
    .replace(migrationEntry.opening, migrationEntry.predecessorOpening)
    .replace(migrationEntry.closing, migrationEntry.predecessorClosing)

  assert.doesNotMatch(predecessor, /CadenceFormPageFrame/)
  return predecessor
}

export const peelCadenceFormPageFrameBeforeOlderLayers = (source, caller) => {
  const file = caller.split("/").at(-1)
  if (!formPageFrameCallerNames.includes(file)) return source
  if (occurrences(source, formPageFrameImport) === 0) return source
  return peelCadenceFormPageFrame(source, caller)
}
