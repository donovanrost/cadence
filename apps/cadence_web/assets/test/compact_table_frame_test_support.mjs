import assert from "node:assert/strict"
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
  Object.freeze({
    file: "OpsTelemetryExplore.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsTelemetryExplore.vue",
    predecessorByteLength: 41104,
    predecessorSha256: "7d61c8875dfafc93ed211cea87b914d89c1a0ff6b8d8746cbff2de741ef991f5",
    boundaries: Object.freeze([
      boundary(
        '              <CadenceTableFrame id="telemetry-explore-samples" class="table-xs">',
        '              <table id="telemetry-explore-samples" class="table table-xs">',
        "              </CadenceTableFrame>",
        "              </table>",
      ),
    ]),
  }),
])

export const compactTableNativeExclusions = Object.freeze([
  Object.freeze({
    file: "WidgetRows.vue",
    repositoryPath: "apps/cadence_web/assets/vue/WidgetRows.vue",
    predecessorByteLength: 7832,
    predecessorSha256: "5ab4b5078f7e01aeb8497c58c64cf958aecb26a3ebf66d57f093c84b99ae7eec",
    classification: "dynamic-compact-presentation-boundary",
    reason: "the table root class is a server-owned presentation value for two widget kinds",
    opening: `  <table
    v-if="presentation.kind === 'status_matrix' || presentation.kind === 'data_table'"
    :class="presentation.root.class"
  >`,
    closing: "  </table>",
    producerPath:
      "apps/cadence_web/lib/cadence_web/live/ops_dashboard_show_live/widget_row_components.ex",
    producerFragment: 'root: %{class: "table table-xs w-full"}',
  }),
  Object.freeze({
    file: "WidgetInspectPanel.vue",
    repositoryPath: "apps/cadence_web/assets/vue/WidgetInspectPanel.vue",
    predecessorByteLength: 4747,
    predecessorSha256: "a315d22f4433521e8c2783e583d3802a2529f8acbffe67c0983c63a367f9193f",
    classification: "dynamic-compact-presentation-boundary",
    reason: "the table root class is owned by the widget-inspection presentation DTO",
    opening: '          <table :class="props.presentation.table.table_class">',
    closing: "          </table>",
    producerPath:
      "apps/cadence_web/lib/cadence_web/live/ops_dashboard_show_live/widget_inspect_panel_components.ex",
    producerFragment: 'table_class: "table table-xs"',
  }),
  Object.freeze({
    file: "OpsContactDetail.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsContactDetail.vue",
    predecessorByteLength: 24323,
    predecessorSha256: "7df770134d5dcf5ef546e08383d41ed72c6c8ddda5271e37e690d4c27634fdc1",
    classification: "near-variant-custom-utility-table",
    reason: "text-xs controls typography; this root has neither the table class nor a table size variant",
    opening:
      '            <table class="w-full min-w-[48rem] table-fixed border-collapse text-left text-xs">',
    closing: "            </table>",
  }),
])

export const predecessorCadenceTableFrameCallers = Object.freeze([
  "AdminOrganizationList.vue",
  "AdminOrganizationShow.vue",
  "CatalogArtifactShow.vue",
  "CatalogDatabaseShow.vue",
  "CatalogDatabaseTable.vue",
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
  const statTileCompatibleSource = peelCadenceStatTileBeforeOlderLayers(source, caller)

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
