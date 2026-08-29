import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelCadenceEmptyStateFrames} from "./empty_state_frame_test_support.mjs"

export const hoverTableRowPredecessor = "437a22f8dde29828bf52e9a709ced2d9d90a04e1"
export const hoverTableRowClass =
  "border-l-2 border-l-transparent transition-colors hover:border-l-primary/60"
export const reorderedHoverTableRowClass =
  "border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"

const importWithoutSemicolon =
  'import CadenceHoverTableRow from "./ui/components/CadenceHoverTableRow.vue"\n'
const importWithSemicolon =
  'import CadenceHoverTableRow from "./ui/components/CadenceHoverTableRow.vue";\n'

export const hoverTableRowMigrations = Object.freeze([
  Object.freeze({
    file: "AdminOrganizationList.vue",
    importLine: importWithoutSemicolon,
    predecessorSha256: "641267b1894daec5790337dd377dec3393808e7cf4822791979bdc1560b788e4",
    openings: Object.freeze([
      Object.freeze({
        component: `      <CadenceHoverTableRow
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
      >`,
        native: `      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="${hoverTableRowClass}"
      >`,
      }),
    ]),
    componentClosing: "      </CadenceHoverTableRow>",
    nativeClosing: "      </tr>",
  }),
  Object.freeze({
    file: "AdminOrganizationShow.vue",
    importLine: importWithoutSemicolon,
    predecessorSha256: "32eb7aeaf8dfc3bac30578e132f24f2cf3ef60399c1c6264267ae5b679ab1def",
    openings: Object.freeze([
      Object.freeze({
        component: `            <CadenceHoverTableRow
              v-for="identity in service_identities"
              :id="identity.id"
              :key="identity.service_identity_id"
            >`,
        native: `            <tr
              v-for="identity in service_identities"
              :id="identity.id"
              :key="identity.service_identity_id"
              class="${hoverTableRowClass}"
            >`,
      }),
    ]),
    componentClosing: "            </CadenceHoverTableRow>",
    nativeClosing: "            </tr>",
  }),
  Object.freeze({
    file: "CatalogDatabaseTable.vue",
    importLine: importWithoutSemicolon,
    predecessorSha256: "57fa491232046550e04700aa31f526075f750b7b1792bf92485464cfda027380",
    openings: Object.freeze([
      Object.freeze({
        component: `      <CadenceHoverTableRow
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
      >`,
        native: `      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="${hoverTableRowClass}"
      >`,
      }),
    ]),
    componentClosing: "      </CadenceHoverTableRow>",
    nativeClosing: "      </tr>",
  }),
  Object.freeze({
    file: "CommsProviderTable.vue",
    importLine: importWithoutSemicolon,
    predecessorSha256: "16f1dcb341de79db74bd613397ab856259dd8e81f77e4258382e2e9f1166ee22",
    openings: Object.freeze([
      Object.freeze({
        component: `      <CadenceHoverTableRow
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
      >`,
        native: `      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="${hoverTableRowClass}"
      >`,
      }),
    ]),
    componentClosing: "      </CadenceHoverTableRow>",
    nativeClosing: "      </tr>",
  }),
  Object.freeze({
    file: "CommsRoutingList.vue",
    importLine: importWithoutSemicolon,
    predecessorSha256: "fb7db53d407aec1bfae4abe7792c8e61b26d24dc5315eff6c89452024f5d3431",
    openings: Object.freeze([
      Object.freeze({
        component: `      <CadenceHoverTableRow
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
      >`,
        native: `      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="${hoverTableRowClass}"
      >`,
      }),
    ]),
    componentClosing: "      </CadenceHoverTableRow>",
    nativeClosing: "      </tr>",
  }),
  Object.freeze({
    file: "CommsTransportList.vue",
    importLine: importWithSemicolon,
    predecessorSha256: "9d8875eb9a7ba4d15c619f2114302e05ce64a71bc76eb58c504351589bcaf33d",
    openings: Object.freeze([
      Object.freeze({
        component: `        <CadenceHoverTableRow
          v-for="row in rows"
          :id="row.id"
          :key="row.id"
        >`,
        native: `        <tr
          v-for="row in rows"
          :id="row.id"
          :key="row.id"
          class="${hoverTableRowClass}"
        >`,
      }),
    ]),
    componentClosing: "        </CadenceHoverTableRow>",
    nativeClosing: "        </tr>",
  }),
  Object.freeze({
    file: "SpacecraftList.vue",
    importLine: importWithoutSemicolon,
    predecessorSha256: "86b1aa94ccdc00204632f46d841546b0a842cb3bd7bc50dde13d69cfa5aba473",
    openings: Object.freeze([
      Object.freeze({
        component: `              <CadenceHoverTableRow
                v-for="row in roster.rows"
                :id="row.id"
                :key="row.id"
              >`,
        native: `              <tr
                v-for="row in roster.rows"
                :id="row.id"
                :key="row.id"
                class="${hoverTableRowClass}"
              >`,
      }),
      Object.freeze({
        component: `              <CadenceHoverTableRow
                v-for="row in profiles.rows"
                :id="row.id"
                :key="row.id"
              >`,
        native: `              <tr
                v-for="row in profiles.rows"
                :id="row.id"
                :key="row.id"
                class="${hoverTableRowClass}"
              >`,
      }),
    ]),
    componentClosing: "              </CadenceHoverTableRow>",
    nativeClosing: "              </tr>",
  }),
  Object.freeze({
    file: "SpacecraftTypeList.vue",
    importLine: importWithoutSemicolon,
    predecessorSha256: "bb6d2cfc727c2c35918aa766c0e872d80d524c02b0ecd6385b8f94d9bc9b7c34",
    openings: Object.freeze([
      Object.freeze({
        component: `      <CadenceHoverTableRow
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
      >`,
        native: `      <tr
        v-for="row in rows"
        :id="row.id"
        :key="row.id"
        class="${hoverTableRowClass}"
      >`,
      }),
    ]),
    componentClosing: "      </CadenceHoverTableRow>",
    nativeClosing: "      </tr>",
  }),
])

export const hoverTableRowCallerNames = Object.freeze(
  hoverTableRowMigrations.map(({file}) => file),
)

export const excludedHoverTableRowFiles = Object.freeze([
  Object.freeze({
    file: "CommsGroundStationList.vue",
    sha256: "81397c02bd76c6fecd8cc2e6130a3a82fb4f34612dda0bb57bf8ba25f4ab7349",
    fragments: Object.freeze([reorderedHoverTableRowClass]),
  }),
  Object.freeze({
    file: "MissionOverview.vue",
    sha256: "b21d7bf85cd2432098819f2cefd3817a10f607ecabe45c9ce3062dee6f46c7e1",
    fragments: Object.freeze([reorderedHoverTableRowClass]),
  }),
  Object.freeze({
    file: "MissionTable.vue",
    sha256: "081659d5426e45df0a63a95c0d0403dde957d5fceb6b101cd4dfa6fc3bc2ece2",
    fragments: Object.freeze([reorderedHoverTableRowClass]),
  }),
  Object.freeze({
    file: "CommsProviderShow.vue",
    sha256: "84189165ad50ce3d0fd70f6db674959b6aece25db0fba46177029fec88159106",
    fragments: Object.freeze([reorderedHoverTableRowClass, reorderedHoverTableRowClass]),
  }),
  Object.freeze({
    file: "WidgetRows.vue",
    sha256: "5ab4b5078f7e01aeb8497c58c64cf958aecb26a3ebf66d57f093c84b99ae7eec",
    fragments: Object.freeze([
      '<tr :class="presentation.head.row_class">',
      `      <tr
        v-for="row in presentation.rows"
        :key="row.key"
        :class="row.class"
        v-bind="row.attrs"
      >`,
    ]),
  }),
  Object.freeze({
    file: "ApplicationHost.vue",
    sha256: "3970225aa801fe5a126d78298b836d4a5531989bc52d197ee0be0aeab171382e",
    fragments: Object.freeze([
      `:class="resource.resource_kind === 'binary_region' && 'border-l-4 border-l-base-content/25'"`,
    ]),
  }),
  Object.freeze({
    file: "OpsTelemetryExplore.vue",
    sha256: "7d61c8875dfafc93ed211cea87b914d89c1a0ff6b8d8746cbff2de741ef991f5",
    fragments: Object.freeze([
      `:class="sample.selected && 'bg-primary/10 outline outline-1 outline-primary/40'"`,
    ]),
  }),
])

export const sha256 = (source) => createHash("sha256").update(source).digest("hex")

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const hoverTableRowMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const migration = hoverTableRowMigrations.find((entry) => entry.file === file)

  assert.ok(migration, `${caller} is an audited CadenceHoverTableRow caller`)
  return migration
}

export const peelCadenceHoverTableRows = (source, caller) => {
  const migration = hoverTableRowMigrationFor(caller)
  const expectedBoundaries = migration.openings.length
  const predecessorCompatibleSource =
    migration.file === "SpacecraftList.vue"
      ? peelCadenceEmptyStateFrames(source, migration.file)
      : source

  assert.equal(
    occurrences(predecessorCompatibleSource, migration.importLine),
    1,
    `${migration.file} exact import count`,
  )
  assert.equal(
    predecessorCompatibleSource.match(/^import CadenceHoverTableRow\b/gm)?.length,
    1,
    `${migration.file} import declaration count`,
  )
  assert.equal(
    predecessorCompatibleSource.match(/<CadenceHoverTableRow\b/g)?.length,
    expectedBoundaries,
    `${migration.file} opening boundary count`,
  )
  assert.equal(
    occurrences(predecessorCompatibleSource, migration.componentClosing),
    expectedBoundaries,
    `${migration.file} closing boundary count`,
  )
  assert.equal(
    occurrences(predecessorCompatibleSource, hoverTableRowClass),
    0,
    `${migration.file} transfers the fixed class out of the caller`,
  )

  let predecessor = predecessorCompatibleSource.replace(migration.importLine, "")

  for (const [index, opening] of migration.openings.entries()) {
    assert.equal(
      occurrences(predecessor, opening.component),
      1,
      `${migration.file} opening mapping ${index + 1} is exact`,
    )
    assert.equal(
      occurrences(predecessor, opening.native),
      0,
      `${migration.file} native opening ${index + 1} is absent before reconstruction`,
    )
    predecessor = predecessor.replace(opening.component, opening.native)
    assert.equal(
      occurrences(predecessor, opening.native),
      1,
      `${migration.file} native opening ${index + 1} reconstructs exactly once`,
    )
  }

  predecessor = predecessor.split(migration.componentClosing).join(migration.nativeClosing)

  assert.doesNotMatch(
    predecessor,
    /CadenceHoverTableRow/,
    `${migration.file} predecessor has zero residual component tokens`,
  )
  assert.equal(
    sha256(predecessor),
    migration.predecessorSha256,
    `${migration.file} reconstructs frozen ${hoverTableRowPredecessor} bytes`,
  )
  return predecessor
}
