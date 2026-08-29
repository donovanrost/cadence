import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelLabeledControlFieldsBeforeOlderLayers} from "./labeled_control_field_test_support.mjs"

export const opsAuthorHeaderPredecessorCommit =
  "6f707c14d35944c203c25fcdb26593c0a5419ca8"
export const opsAuthorHeaderClass =
  "border-b border-primary/20 bg-base-200/70 px-6 py-5 hud-grid"
export const opsAuthorHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'

const migration = ({
  file,
  predecessorByteLength,
  predecessorSha256,
  predecessorBlob,
  opening,
  predecessorOpening,
}) =>
  Object.freeze({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    predecessorCommit: opsAuthorHeaderPredecessorCommit,
    predecessorByteLength,
    predecessorSha256,
    predecessorBlob,
    importLine: opsAuthorHeaderImport,
    opening,
    predecessorOpening,
    closing: "    </CadencePageHeaderFrame>",
    predecessorClosing: "    </header>",
  })

export const opsAuthorHeaderMigrations = Object.freeze([
  migration({
    file: "OpsDashboardLibrary.vue",
    predecessorByteLength: 21_114,
    predecessorSha256: "0c522ba61f458a97064d22bd246e70b76cc08e592315a22494e784d04df36883",
    predecessorBlob: "442575c10c35c1bd290ac7926c9ba621258f6406",
    opening: [
      "    <CadencePageHeaderFrame",
      '      :id="page.header.id"',
      '      variant="ops-author"',
      "    >",
    ].join("\n"),
    predecessorOpening: [
      "    <header",
      '      :id="page.header.id"',
      `      class="${opsAuthorHeaderClass}"`,
      "    >",
    ].join("\n"),
  }),
  migration({
    file: "OpsDashboardPlaylists.vue",
    predecessorByteLength: 8_915,
    predecessorSha256: "4084749b4e50c73fd43f24f73d19c1b49914f73e2146ab7b2d4e38fb0338c510",
    predecessorBlob: "5c3fe7cfcce416f911250a11712e93c2f2b60846",
    opening: '    <CadencePageHeaderFrame variant="ops-author">',
    predecessorOpening: `    <header class="${opsAuthorHeaderClass}">`,
  }),
])

export const opsAuthorHeaderCallerNames = Object.freeze(
  opsAuthorHeaderMigrations.map(({file}) => file),
)

export const opsAuthorHeaderPrimitivePredecessor = Object.freeze({
  repositoryPath:
    "apps/cadence_web/assets/vue/ui/components/CadencePageHeaderFrame.vue",
  predecessorCommit: opsAuthorHeaderPredecessorCommit,
  predecessorByteLength: 1_138,
  predecessorSha256: "89d6b921328b126065314d275c3aeb5a4e74fef9f5d678c8ee8a2101c75e4457",
  predecessorBlob: "f8f02875bbc84c8c6e1e51159bfb7d2c53d2c763",
})

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const opsAuthorHeaderSha256 = (source) =>
  createHash("sha256").update(source).digest("hex")

export const opsAuthorHeaderMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const found = opsAuthorHeaderMigrations.find((entry) => entry.file === file)

  assert.ok(found, `${caller} is an audited ops-author page-header caller`)
  return found
}

export const peelCadenceOpsAuthorHeader = (source, caller) => {
  const entry = opsAuthorHeaderMigrationFor(caller)
  source = peelLabeledControlFieldsBeforeOlderLayers(source, caller)

  assert.equal(occurrences(source, entry.importLine), 1, `${entry.file} exact import count`)
  assert.equal(source.match(/^import CadencePageHeaderFrame\b/gm)?.length, 1)
  assert.equal(occurrences(source, entry.opening), 1, `${entry.file} exact frame opening`)
  assert.equal(occurrences(source, entry.closing), 1, `${entry.file} exact frame closing`)
  assert.equal(source.match(/<CadencePageHeaderFrame\b/g)?.length, 1)
  assert.equal(source.match(/<\/CadencePageHeaderFrame>/g)?.length, 1)
  assert.equal(occurrences(source, `class="${opsAuthorHeaderClass}"`), 0)

  const predecessor = source
    .replace(entry.importLine, "")
    .replace(entry.opening, entry.predecessorOpening)
    .replace(entry.closing, entry.predecessorClosing)

  assert.doesNotMatch(predecessor, /CadencePageHeaderFrame/)
  assert.equal(Buffer.byteLength(predecessor), entry.predecessorByteLength)
  assert.equal(opsAuthorHeaderSha256(predecessor), entry.predecessorSha256)
  return predecessor
}

export const peelOpsAuthorVariantFromPrimitive = (source) => {
  const predecessor = source
    .replace(
      'type Variant = "compact" | "ops" | "ops-author"',
      'type Variant = "compact" | "ops"',
    )
    .replace(`  "ops-author": "${opsAuthorHeaderClass}",\n`, "")
    .replace(
      [
        "      validator: (value: string) =>",
        '        value === "compact" || value === "ops" || value === "ops-author",',
      ].join("\n"),
      '      validator: (value: string) => value === "compact" || value === "ops",',
    )

  assert.equal(occurrences(predecessor, "ops-author"), 0)
  assert.equal(
    Buffer.byteLength(predecessor),
    opsAuthorHeaderPrimitivePredecessor.predecessorByteLength,
  )
  assert.equal(
    opsAuthorHeaderSha256(predecessor),
    opsAuthorHeaderPrimitivePredecessor.predecessorSha256,
  )
  return predecessor
}
