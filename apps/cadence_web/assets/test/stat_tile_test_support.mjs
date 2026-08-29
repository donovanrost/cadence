import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelLabeledControlFieldsBeforeOlderLayers} from "./labeled_control_field_test_support.mjs"

export const statTilePredecessorCommit = "b9e8c677bf4cb37020107a8d37483117ddf03b94"
export const statTileClass = "border border-base-300 bg-base-200 px-3 py-2"
export const statTileLabelClass = "hud-label"
export const statTileValueClass = "mt-1 font-mono text-xl text-base-content"
export const statTileImport =
  'import CadenceStatTile from "./ui/components/CadenceStatTile.vue"\n'

const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1

const migration = ({
  file,
  predecessorByteLength,
  predecessorSha256,
  predecessorBlobId,
  indent,
  iterator,
  id,
  key,
  labelExpression,
  valueExpression,
}) => {
  const attributeIndent = `${indent}  `
  const childIndent = `${indent}  `
  const attributes = [
    `${attributeIndent}v-for="${iterator}"`,
    ...(id ? [`${attributeIndent}:id="${id}"`] : []),
    `${attributeIndent}:key="${key}"`,
  ]

  return Object.freeze({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    predecessorCommit: statTilePredecessorCommit,
    predecessorByteLength,
    predecessorSha256,
    predecessorBlobId,
    componentOpening: [`${indent}<CadenceStatTile`, ...attributes, `${indent}>`].join("\n"),
    nativeOpening: [
      `${indent}<div`,
      ...attributes,
      `${attributeIndent}class="${statTileClass}"`,
      `${indent}>`,
    ].join("\n"),
    componentLabel: `${childIndent}<template #label>{{ ${labelExpression} }}</template>`,
    nativeLabel: `${childIndent}<p class="${statTileLabelClass}">{{ ${labelExpression} }}</p>`,
    valueLine: `${childIndent}<p class="${statTileValueClass}">{{ ${valueExpression} }}</p>`,
    componentClosing: `${indent}</CadenceStatTile>`,
    nativeClosing: `${indent}</div>`,
  })
}

export const statTileMigrations = Object.freeze([
  migration({
    file: "AdminRuntime.vue",
    predecessorByteLength: 18548,
    predecessorSha256: "f94cf621e27b741d09ee459eda447113f0d6e05802e384afba5b31fbdd12526e",
    predecessorBlobId: "7894d20f30c38ced90cf79bc9f78ed08237c912d",
    indent: "      ",
    iterator: "stat in summary.stats",
    id: "stat.id",
    key: "stat.id",
    labelExpression: "stat.label",
    valueExpression: "stat.value",
  }),
  migration({
    file: "CommsProviderShow.vue",
    predecessorByteLength: 14118,
    predecessorSha256: "2c0a8e64c6f255d03175f939ef03678020cedcb3f30b3a50d93832213928a40f",
    predecessorBlobId: "75dfb59a59fdb9f5884678816f3dc5cd9abf5b21",
    indent: "      ",
    iterator: "summary in provider.summary_tiles",
    id: "summary.id",
    key: "summary.id",
    labelExpression: "summary.label",
    valueExpression: "summary.value",
  }),
  migration({
    file: "CommsTransportShow.vue",
    predecessorByteLength: 6349,
    predecessorSha256: "45e7966c795b8eeae70b85acf81d315afa2fed80b03d451714fcd526cbcec799",
    predecessorBlobId: "4be811557b5b8d4059c90567c176c5ea83cb05ea",
    indent: "      ",
    iterator: "summary in transport.summary_tiles",
    id: "summary.id",
    key: "summary.id",
    labelExpression: "summary.label",
    valueExpression: "summary.value",
  }),
  migration({
    file: "OpsDataSources.vue",
    predecessorByteLength: 66064,
    predecessorSha256: "23c174a941aa96984ac41e165b8af91f45e2f5977721e1ad347adf38b3353f5e",
    predecessorBlobId: "17d6947b0f33ab43ed7bd0e6b34a5e5e55b77e53",
    indent: "              ",
    iterator: "stat in page.header.stats",
    key: "stat.label",
    labelExpression: "stat.label",
    valueExpression: "stat.value",
  }),
  migration({
    file: "ProviderAccountShow.vue",
    predecessorByteLength: 17595,
    predecessorSha256: "76bd3a9e3ab7839f1ca7c41529de51d1361416794a410037f8fb71c97396d399",
    predecessorBlobId: "4a32345d89aa623c016a3372b9459cca1c0a05fd",
    indent: "      ",
    iterator: "stat in stats",
    id: "stat.id",
    key: "stat.id",
    labelExpression: "stat.label",
    valueExpression: "stat.value",
  }),
  migration({
    file: "SpacecraftTelemetryDecom.vue",
    predecessorByteLength: 22585,
    predecessorSha256: "045d2e5a8409eed9bf1b71b6042150cb84241e7248048df50338103dba2266ff",
    predecessorBlobId: "118916996c0d5199fa317fb81eac7696377b8ee1",
    indent: "                  ",
    iterator: "stat in preview.stats",
    id: "stat.id",
    key: "stat.id",
    labelExpression: "stat.label",
    valueExpression: "stat.value",
  }),
])

export const statTileCallerNames = Object.freeze(statTileMigrations.map(({file}) => file))

export const statTileKnownExclusions = Object.freeze([
  Object.freeze({
    file: "OpsDataSources.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDataSources.vue",
    classification: "semantic-readiness-policy-near-variant",
    reason:
      "the root adds text-right and data-source readiness semantics, and its value typography differs",
    opening: `            <div
              :id="page.header.readiness_policy.id"
              class="${statTileClass} text-right"
              :data-source-readiness-policy-id="page.header.readiness_policy.policy_id"
              :data-source-readiness-block-health="page.header.readiness_policy.block_source_health"
              :data-source-readiness-block-freshness="page.header.readiness_policy.block_freshness"
              :data-source-readiness-block-connection-test="page.header.readiness_policy.block_connection_test"
            >`,
    closing: "            </div>",
  }),
])

export const statTileMigrationFor = (caller) => {
  const file = caller.replaceAll("\\", "/").split("/").at(-1)
  return statTileMigrations.find((entry) => entry.file === file)
}

export const peelCadenceStatTile = (source, caller) => {
  const entry = statTileMigrationFor(caller)
  assert.ok(entry, `${caller} is an audited CadenceStatTile caller`)
  source = peelLabeledControlFieldsBeforeOlderLayers(source, caller)

  assert.equal(occurrences(source, statTileImport), 1, `${entry.file} stat-tile import count`)
  assert.equal(source.match(/^import CadenceStatTile\b/gm)?.length, 1)
  assert.equal(occurrences(source, entry.componentOpening), 1, `${entry.file} stat-tile opening`)
  assert.equal(occurrences(source, entry.componentLabel), 1, `${entry.file} label slot`)
  assert.equal(occurrences(source, entry.valueLine), 1, `${entry.file} caller-owned value node`)
  assert.equal(occurrences(source, entry.componentClosing), 1, `${entry.file} stat-tile closing`)

  const predecessor = source
    .replace(statTileImport, "")
    .replace(entry.componentOpening, entry.nativeOpening)
    .replace(entry.componentLabel, entry.nativeLabel)
    .replace(entry.componentClosing, entry.nativeClosing)

  assert.doesNotMatch(predecessor, /CadenceStatTile/)
  assert.equal(Buffer.byteLength(predecessor), entry.predecessorByteLength)
  assert.equal(
    sha256(predecessor),
    entry.predecessorSha256,
    `${entry.file} reconstructs its frozen immediate predecessor SHA-256`,
  )
  return predecessor
}

export const peelCadenceStatTileBeforeOlderLayers = (source, caller) => {
  const labeledCompatibleSource = peelLabeledControlFieldsBeforeOlderLayers(source, caller)
  const entry = statTileMigrationFor(caller)
  if (!entry || occurrences(labeledCompatibleSource, statTileImport) === 0) {
    return labeledCompatibleSource
  }
  return peelCadenceStatTile(labeledCompatibleSource, caller)
}
