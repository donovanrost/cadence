import assert from "node:assert/strict"
import {
  peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers,
} from "./compact_page_header_body_frame_test_support.mjs"
import {peelCadenceStatTileBeforeOlderLayers} from "./stat_tile_test_support.mjs"

export const compactTableFramePredecessor =
  "0117bf2999f160de2d0ef05ed1d5d8fdb3b2a648"
export const compactTableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'

const boundary = (componentOpening, nativeOpening, componentClosing, nativeClosing) =>
  Object.freeze({componentOpening, nativeOpening, componentClosing, nativeClosing})

export const compactTableFrameMigrations = Object.freeze([
  Object.freeze({
    file: "AdminRuntime.vue",
    repositoryPath: "apps/cadence_web/assets/vue/AdminRuntime.vue",
    predecessorByteLength: 18460,
    predecessorSha256: "ad7cbbc91865bd4dbc2456f830748a155ba1334874e7e1583bf7e75a0371b4ec",
    boundaries: Object.freeze([
      boundary(
        '        <CadenceTableFrame id="admin-runtime-decisions-table" class="table-sm">',
        '        <table id="admin-runtime-decisions-table" class="table table-sm">',
        "        </CadenceTableFrame>",
        "        </table>",
      ),
    ]),
  }),
  Object.freeze({
    file: "ApplicationHost.vue",
    repositoryPath: "apps/cadence_web/assets/vue/ApplicationHost.vue",
    predecessorByteLength: 35555,
    predecessorSha256: "3970225aa801fe5a126d78298b836d4a5531989bc52d197ee0be0aeab171382e",
    boundaries: Object.freeze([
      boundary(
        '                <CadenceTableFrame class="table-xs">',
        '                <table class="table table-xs">',
        "                </CadenceTableFrame>",
        "                </table>",
      ),
      boundary(
        '        <CadenceTableFrame class="table-sm">',
        '        <table class="table table-sm">',
        "        </CadenceTableFrame>",
        "        </table>",
      ),
    ]),
  }),
])

export const compactTableNativeExclusions = Object.freeze([])

export const predecessorCadenceTableFrameCallers = Object.freeze([
  "AdminOrganizationList.vue",
  "AdminOrganizationShow.vue",
  "CatalogArtifactShow.vue",
  "CatalogDatabaseShow.vue",
  "CommsGroundStationList.vue",
  "CommsProviderShow.vue",
  "CommsProviderTable.vue",
  "CommsRoutingList.vue",
  "CommsTransportList.vue",
  "MissionOverview.vue",
  "MissionTable.vue",
  "SpacecraftList.vue",
  "SpacecraftTypeList.vue",
  "SpacecraftTypeShow.vue",
])

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const compactTableFrameMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  return compactTableFrameMigrations.find((entry) => entry.file === file)
}

export const peelCompactTableFrames = (source, caller) => {
  const migration = compactTableFrameMigrationFor(caller)
  if (!migration) return source
  const compactHeaderBodyCompatibleSource =
    peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers(source, caller)
  const statTileCompatibleSource = peelCadenceStatTileBeforeOlderLayers(
    compactHeaderBodyCompatibleSource,
    caller,
  )

  assert.equal(
    occurrences(statTileCompatibleSource, compactTableFrameImport),
    1,
    `${migration.file} compact-table import count`,
  )
  assert.equal(statTileCompatibleSource.match(/^import CadenceTableFrame\b/gm)?.length, 1)
  assert.equal(
    statTileCompatibleSource.match(/<CadenceTableFrame\b/g)?.length,
    migration.boundaries.length,
  )
  assert.equal(
    statTileCompatibleSource.match(/<\/CadenceTableFrame>/g)?.length,
    migration.boundaries.length,
  )

  let predecessor = statTileCompatibleSource.replace(compactTableFrameImport, "")

  for (const [index, entry] of migration.boundaries.entries()) {
    assert.equal(
      occurrences(predecessor, entry.componentOpening),
      1,
      `${migration.file} compact-table opening ${index + 1}`,
    )
    assert.equal(occurrences(predecessor, entry.nativeOpening), 0)
    assert.equal(
      occurrences(predecessor, entry.componentClosing),
      1,
      `${migration.file} compact-table closing ${index + 1}`,
    )
    predecessor = predecessor
      .replace(entry.componentOpening, entry.nativeOpening)
      .replace(entry.componentClosing, entry.nativeClosing)
  }

  assert.doesNotMatch(predecessor, /CadenceTableFrame/)
  return predecessor
}
