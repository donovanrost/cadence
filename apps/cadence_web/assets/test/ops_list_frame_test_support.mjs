import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelCadenceOpsListBodyFrameBeforeOlderLayers} from "./ops_list_body_frame_test_support.mjs"

export const opsListFramePredecessorCommit = "37435982d75e0d23b4b102d6e8d371686b27d5f3"
export const opsListFrameClass = "overflow-hidden border border-base-300 bg-base-100"
export const opsListFrameImport =
  'import CadenceOpsListFrame from "./ui/components/CadenceOpsListFrame.vue"\n'

export const opsListFrameMigrations = Object.freeze([
  Object.freeze({
    file: "OpsAlarms.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsAlarms.vue",
    predecessorByteLength: 10957,
    predecessorSha256: "c578acb49a55a1f4f7d21b14a1ab993187ea05284795c5f6a10385afa633ba4a",
    opening: "      <CadenceOpsListFrame>",
    predecessorOpening: `      <section class="${opsListFrameClass}">`,
    closing: "      </CadenceOpsListFrame>",
    predecessorClosing: "      </section>",
  }),
  Object.freeze({
    file: "OpsCommands.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsCommands.vue",
    predecessorByteLength: 12917,
    predecessorSha256: "ff0c6f16403b8af9161a560efcae707f2fc9f30334ddc6a2ac16f73c7d8f5058",
    opening: "      <CadenceOpsListFrame>",
    predecessorOpening: `      <section class="${opsListFrameClass}">`,
    closing: "      </CadenceOpsListFrame>",
    predecessorClosing: "      </section>",
  }),
])

export const opsListFrameCallerNames = Object.freeze(
  opsListFrameMigrations.map(({file}) => file),
)

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const opsListFrameSha256 = source => createHash("sha256").update(source).digest("hex")

export const opsListFrameMigrationFor = caller => {
  const file = caller.split("/").at(-1)
  const migration = opsListFrameMigrations.find(entry => entry.file === file)

  assert.ok(migration, `${caller} is an audited CadenceOpsListFrame caller`)
  return migration
}

export const peelCadenceOpsListFrame = (source, caller) => {
  const migration = opsListFrameMigrationFor(caller)
  source = peelCadenceOpsListBodyFrameBeforeOlderLayers(source, caller)

  assert.equal(
    occurrences(source, opsListFrameImport),
    1,
    `${migration.file} has one exact CadenceOpsListFrame import`,
  )
  assert.equal(
    source.match(/^import CadenceOpsListFrame\b/gm)?.length,
    1,
    `${migration.file} has one CadenceOpsListFrame import declaration`,
  )
  assert.equal(
    occurrences(source, migration.opening),
    1,
    `${migration.file} has one exact CadenceOpsListFrame opening`,
  )
  assert.equal(
    occurrences(source, migration.closing),
    1,
    `${migration.file} has one exact CadenceOpsListFrame closing`,
  )
  assert.equal(source.match(/<CadenceOpsListFrame\b/g)?.length, 1)
  assert.equal(source.match(/<\/CadenceOpsListFrame>/g)?.length, 1)

  const predecessor = source
    .replace(opsListFrameImport, "")
    .replace(migration.opening, migration.predecessorOpening)
    .replace(migration.closing, migration.predecessorClosing)

  assert.doesNotMatch(
    predecessor,
    /CadenceOpsListFrame/,
    `${migration.file} list-frame peel leaves no residual frame`,
  )
  return predecessor
}
