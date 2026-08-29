import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelLabeledControlFieldsBeforeOlderLayers} from "./labeled_control_field_test_support.mjs"

export const opsPageBodyFramePredecessorCommit =
  "3f461caaca8391f5a7a4388b0098cd46a76c716c"
export const opsPageBodyFramePath =
  "apps/cadence_web/assets/vue/ui/components/CadenceOpsPageBodyFrame.vue"
export const opsPageBodyFrameClass = "mx-auto max-w-[100rem] space-y-5 p-5 lg:p-7"
export const opsPageBodyFrameImport =
  'import CadenceOpsPageBodyFrame from "./ui/components/CadenceOpsPageBodyFrame.vue"\n'

export const opsPageBodyFrameMigrations = Object.freeze([
  Object.freeze({
    file: "OpsDashboardDirectory.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDashboardDirectory.vue",
    predecessorByteLength: 12_658,
    predecessorBlobId: "47616f3d8ea577b4388a07019910362839e1ad27",
    predecessorSha256:
      "305b2c5fbae09713197e2c2ba1cbc9e7a88777142444c18d10b9109269959b5c",
  }),
  Object.freeze({
    file: "OpsFleetPlanning.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsFleetPlanning.vue",
    predecessorByteLength: 11_009,
    predecessorBlobId: "a752c027e56061390b83c34ca4c8f2fbc84db6d0",
    predecessorSha256:
      "a918ee3477e6d5dc4f129daf58563fe05806224a03426c6609f8db2665d35e05",
  }),
])

export const opsPageBodyFrameCallerNames = Object.freeze(
  opsPageBodyFrameMigrations.map(({file}) => file),
)

export const opsPageBodyFrameSha256 = source =>
  createHash("sha256").update(source).digest("hex")

const occurrences = (source, fragment) => source.split(fragment).length - 1

const migrationFor = caller => {
  const file = caller.split("/").at(-1)
  const migration = opsPageBodyFrameMigrations.find(entry => entry.file === file)

  assert.ok(migration, `${caller} is an audited CadenceOpsPageBodyFrame caller`)
  return migration
}

export const peelCadenceOpsPageBodyFrame = (source, caller) => {
  const migration = migrationFor(caller)
  source = peelLabeledControlFieldsBeforeOlderLayers(source, caller)
  const opening = "    <CadenceOpsPageBodyFrame>"
  const closing = "    </CadenceOpsPageBodyFrame>"
  const predecessorOpening = `    <div class="${opsPageBodyFrameClass}">`

  assert.equal(occurrences(source, opsPageBodyFrameImport), 1, `${migration.file} page-body import`)
  assert.equal(occurrences(source, opening), 1, `${migration.file} page-body opening`)
  assert.equal(occurrences(source, closing), 1, `${migration.file} page-body closing`)
  assert.equal(source.match(/<CadenceOpsPageBodyFrame\b/g)?.length, 1)
  assert.equal(source.match(/<\/CadenceOpsPageBodyFrame>/g)?.length, 1)

  const predecessor = source
    .replace(opsPageBodyFrameImport, "")
    .replace(opening, predecessorOpening)
    .replace(closing, "    </div>")

  assert.doesNotMatch(predecessor, /CadenceOpsPageBodyFrame/)
  return predecessor
}

export const peelCadenceOpsPageBodyFrameBeforeOlderLayers = (source, caller) => {
  const file = caller.split("/").at(-1)
  if (!opsPageBodyFrameCallerNames.includes(file)) return source
  if (occurrences(source, opsPageBodyFrameImport) === 0) return source
  return peelCadenceOpsPageBodyFrame(source, caller)
}
