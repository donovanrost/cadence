import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelLabeledControlFieldsBeforeOlderLayers} from "./labeled_control_field_test_support.mjs"

export const opsListBodyFramePredecessorCommit =
  "e4e532371228cfd7ad08958409e48590b683e5ac"
export const opsListBodyFramePath =
  "apps/cadence_web/assets/vue/ui/components/CadenceOpsListBodyFrame.vue"
export const opsListBodyFrameClass = "mx-auto max-w-[100rem] space-y-4 p-5 lg:p-7"
export const opsListBodyFrameImport =
  'import CadenceOpsListBodyFrame from "./ui/components/CadenceOpsListBodyFrame.vue"\n'

export const opsListBodyFrameMigrations = Object.freeze([
  Object.freeze({
    file: "OpsAlarms.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsAlarms.vue",
    predecessorByteLength: 10_996,
    predecessorBlobId: "2aa9da6a3e38af25b5436081e54b57b32bcd4ef1",
    predecessorSha256: "0fc74068bd384291bb80b8f838e49d2362334a6485dc8d1e6a33ab52dd6c8845",
  }),
  Object.freeze({
    file: "OpsCommands.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsCommands.vue",
    predecessorByteLength: 12_956,
    predecessorBlobId: "22902243d4609e936a7cfdf30136c022ca1f2996",
    predecessorSha256: "e079214a8167047fcd9d5fabafb0aa79ed2d849d2a8e91e0cd91f088ff3f3622",
  }),
])

export const opsListBodyFrameCallerNames = Object.freeze(
  opsListBodyFrameMigrations.map(({file}) => file),
)

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const opsListBodyFrameSha256 = source => createHash("sha256").update(source).digest("hex")

const migrationFor = caller => {
  const file = caller.split("/").at(-1)
  const migration = opsListBodyFrameMigrations.find(entry => entry.file === file)

  assert.ok(migration, `${caller} is an audited CadenceOpsListBodyFrame caller`)
  return migration
}

export const peelCadenceOpsListBodyFrame = (source, caller) => {
  const migration = migrationFor(caller)
  source = peelLabeledControlFieldsBeforeOlderLayers(source, caller)
  const opening = "    <CadenceOpsListBodyFrame>"
  const closing = "    </CadenceOpsListBodyFrame>"
  const predecessorOpening = `    <div class="${opsListBodyFrameClass}">`

  assert.equal(occurrences(source, opsListBodyFrameImport), 1, `${migration.file} body-frame import`)
  assert.equal(occurrences(source, opening), 1, `${migration.file} body-frame opening`)
  assert.equal(occurrences(source, closing), 1, `${migration.file} body-frame closing`)
  assert.equal(source.match(/<CadenceOpsListBodyFrame\b/g)?.length, 1)
  assert.equal(source.match(/<\/CadenceOpsListBodyFrame>/g)?.length, 1)

  const predecessor = source
    .replace(opsListBodyFrameImport, "")
    .replace(opening, predecessorOpening)
    .replace(closing, "    </div>")

  assert.doesNotMatch(predecessor, /CadenceOpsListBodyFrame/)
  return predecessor
}

export const peelCadenceOpsListBodyFrameBeforeOlderLayers = (source, caller) => {
  const file = caller.split("/").at(-1)
  if (!opsListBodyFrameCallerNames.includes(file)) return source
  if (occurrences(source, opsListBodyFrameImport) === 0) return source
  return peelCadenceOpsListBodyFrame(source, caller)
}
