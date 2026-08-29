import assert from "node:assert/strict"
import {createHash} from "node:crypto"

export const narrowFormPageFramePredecessorCommit =
  "6756759839c403dd0e9d5f7203105fcfa76c0340"
export const narrowFormPageFramePath =
  "apps/cadence_web/assets/vue/ui/components/CadenceNarrowFormPageFrame.vue"
export const narrowFormPageFrameClass = "space-y-6 max-w-xl"
export const narrowFormPageFrameImport =
  'import CadenceNarrowFormPageFrame from "./ui/components/CadenceNarrowFormPageFrame.vue"\n'

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
    closing: "  </CadenceNarrowFormPageFrame>",
    predecessorClosing: "  </div>",
  })

export const narrowFormPageFrameMigrations = Object.freeze([
  migration({
    file: "AdminOrganizationInvite.vue",
    predecessorByteLength: 6_713,
    predecessorBlobId: "b93f7f64132b69ebf0c7198740e303f3759902d5",
    predecessorSha256:
      "8befd265374e5f79cc751541b519ec254a4d5f5923ff2fd5683afd000494bad6",
    opening: '  <CadenceNarrowFormPageFrame id="admin-organization-invite-page">',
    predecessorOpening:
      '  <div id="admin-organization-invite-page" class="space-y-6 max-w-xl">',
  }),
  migration({
    file: "AdminOrganizationNew.vue",
    predecessorByteLength: 4_116,
    predecessorBlobId: "ab1461244b559674ff658a2713354725ae12a62e",
    predecessorSha256:
      "d6112394e350ad1ae08c45b6aefd7e0577ee530045b1d42ad2f507394cc16bf2",
    opening: '  <CadenceNarrowFormPageFrame id="admin-organization-new-page">',
    predecessorOpening:
      '  <div id="admin-organization-new-page" class="space-y-6 max-w-xl">',
  }),
  migration({
    file: "MissionNew.vue",
    predecessorByteLength: 4_658,
    predecessorBlobId: "ce1250d569d0b6e7a6f4b6d0a4e207030d25b8bf",
    predecessorSha256:
      "e37f62e4c1f9233e6dc19447e40710b08d2ac06ed4f34ef4f120870ea14a351e",
    opening: '  <CadenceNarrowFormPageFrame :id="page.id">',
    predecessorOpening: '  <div :id="page.id" class="space-y-6 max-w-xl">',
  }),
  migration({
    file: "SpacecraftEdit.vue",
    predecessorByteLength: 7_765,
    predecessorBlobId: "a6bfd5ecaae1f65306918b362ade2fd99608cb7d",
    predecessorSha256:
      "bfe056fb735cdfd4b33b217bbb571410cccc5d146218c63471133c74148c08a9",
    opening: '  <CadenceNarrowFormPageFrame :id="page.id">',
    predecessorOpening: '  <div :id="page.id" class="space-y-6 max-w-xl">',
  }),
  migration({
    file: "SpacecraftNew.vue",
    predecessorByteLength: 8_292,
    predecessorBlobId: "2f35662955e1f4459a7159c3f3386643925d5a48",
    predecessorSha256:
      "a8bcc877716b4b055a6b22013d0202c1347c29b1170cc071e1dbe4eaaed8802e",
    opening: '  <CadenceNarrowFormPageFrame :id="page.id">',
    predecessorOpening: '  <div :id="page.id" class="space-y-6 max-w-xl">',
  }),
])

export const narrowFormPageFrameCallerNames = Object.freeze(
  narrowFormPageFrameMigrations.map(({file}) => file),
)

export const narrowFormPageFrameSha256 = source =>
  createHash("sha256").update(source).digest("hex")

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const narrowFormPageFrameMigrationFor = caller => {
  const file = caller.split("/").at(-1)
  const migrationEntry = narrowFormPageFrameMigrations.find(entry => entry.file === file)

  assert.ok(migrationEntry, `${caller} is an audited CadenceNarrowFormPageFrame caller`)
  return migrationEntry
}

export const peelCadenceNarrowFormPageFrame = (source, caller) => {
  const migrationEntry = narrowFormPageFrameMigrationFor(caller)

  assert.equal(
    occurrences(source, narrowFormPageFrameImport),
    1,
    `${migrationEntry.file} narrow form frame import`,
  )
  assert.equal(
    occurrences(source, migrationEntry.opening),
    1,
    `${migrationEntry.file} narrow form frame opening`,
  )
  assert.equal(
    occurrences(source, migrationEntry.closing),
    1,
    `${migrationEntry.file} narrow form frame closing`,
  )

  const predecessor = source
    .replace(narrowFormPageFrameImport, "")
    .replace(migrationEntry.opening, migrationEntry.predecessorOpening)
    .replace(migrationEntry.closing, migrationEntry.predecessorClosing)

  assert.doesNotMatch(predecessor, /CadenceNarrowFormPageFrame/)
  return predecessor
}

export const peelCadenceNarrowFormPageFrameBeforeOlderLayers = (source, caller) => {
  const file = caller.split("/").at(-1)
  if (!narrowFormPageFrameCallerNames.includes(file)) return source
  if (occurrences(source, narrowFormPageFrameImport) === 0) return source
  return peelCadenceNarrowFormPageFrame(source, caller)
}
