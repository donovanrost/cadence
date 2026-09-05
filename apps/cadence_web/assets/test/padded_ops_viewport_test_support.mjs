import assert from "node:assert/strict"
import {createHash} from "node:crypto"

export const paddedOpsViewportPredecessorCommit =
  "82403401eb234b29acb3039a32ae447f725c27b0"
export const paddedOpsViewportClass = "p-6"
export const paddedOpsViewportNativeClass =
  "h-full overflow-y-auto bg-base-100 p-6"
export const paddedOpsViewportImport =
  'import CadenceOpsViewport from "./ui/components/CadenceOpsViewport.vue"\n\n'

const adoption = (file, predecessorByteLength, predecessorSha256, idExpression) =>
  Object.freeze({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    predecessorCommit: paddedOpsViewportPredecessorCommit,
    predecessorByteLength,
    predecessorSha256,
    importLine: paddedOpsViewportImport,
    opening: `  <CadenceOpsViewport :id="${idExpression}" class="${paddedOpsViewportClass}">`,
    predecessorOpening: `  <section :id="${idExpression}" class="${paddedOpsViewportNativeClass}">`,
    closing: "  </CadenceOpsViewport>",
    predecessorClosing: "  </section>",
  })

export const paddedOpsViewportMigrations = Object.freeze([
  adoption(
    "OpsDashboardShare.vue",
    1684,
    "92903b435d264e30dcf569631ccdaa0610a696ac8385199a3d389641003ec009",
    "share.id",
  ),
])

export const paddedOpsViewportCallerNames = Object.freeze(
  paddedOpsViewportMigrations.map(({file}) => file),
)

export const paddedOpsViewportSha256 = (source) =>
  createHash("sha256").update(source).digest("hex")

export const paddedOpsViewportMigrationFor = (caller) => {
  const file = caller.replaceAll("\\", "/").split("/").at(-1)
  const migration = paddedOpsViewportMigrations.find((entry) => entry.file === file)

  assert.ok(migration, `${caller} is an audited padded Ops viewport caller`)
  return migration
}

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const peelPaddedOpsViewport = (source, caller) => {
  const migration = paddedOpsViewportMigrationFor(caller)

  assert.equal(occurrences(source, migration.importLine), 1, `${migration.file} viewport import`)
  assert.equal(source.match(/^import CadenceOpsViewport\b/gm)?.length, 1)
  assert.equal(occurrences(source, migration.opening), 1, `${migration.file} viewport opening`)
  assert.equal(occurrences(source, migration.closing), 1, `${migration.file} viewport closing`)
  assert.equal(source.match(/<CadenceOpsViewport\b/g)?.length, 1)
  assert.equal(source.match(/<\/CadenceOpsViewport>/g)?.length, 1)

  const predecessor = source
    .replace(migration.importLine, "")
    .replace(migration.opening, migration.predecessorOpening)
    .replace(migration.closing, migration.predecessorClosing)

  assert.doesNotMatch(predecessor, /CadenceOpsViewport/)
  return predecessor
}
