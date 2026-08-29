import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelLabeledControlFieldsBeforeOlderLayers} from "./labeled_control_field_test_support.mjs"
import {peelOpsDataSourcesCadenceFields} from "./ops_data_sources_field_test_support.mjs"

export const peelCadenceFieldsBeforeEmptyStateLayers = (source, caller) => {
  const labeledCompatibleSource = peelLabeledControlFieldsBeforeOlderLayers(source, caller)

  return caller.split("/").at(-1) === "OpsDataSources.vue"
    ? peelOpsDataSourcesCadenceFields(labeledCompatibleSource, caller)
    : labeledCompatibleSource
}

export const emptyStateFramePredecessor = "96e8a4bb542d9abf784de4eb5c9c61492860e937"
export const emptyStateRootClass =
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
export const emptyStateTitleClass = "hud-label"
export const emptyStateDescriptionClass =
  "mx-auto mt-2 max-w-md text-sm text-base-content/70"
export const emptyStateActionContainerClass = "mt-5"
export const emptyStateActionClass = "btn btn-primary btn-sm"
export const emptyStateActionIconClass = "hero-plus -ml-0.5 mr-1 h-4 w-4"

const lines = (...sourceLines) => sourceLines.join("\n")
const occurrences = (source, fragment) => source.split(fragment).length - 1

export const emptyStateSha256 = (source) => createHash("sha256").update(source).digest("hex")

export const emptyStateFrameMigrations = Object.freeze([
  Object.freeze({
    file: "SpacecraftList.vue",
    repositoryPath: "apps/cadence_web/assets/vue/SpacecraftList.vue",
    predecessorByteLength: 15_583,
    predecessorSha256: "676d44782b80b07464e2f8d2772533c5ba81530a380512c41d73548fb9ac2009",
    importLine:
      'import CadenceEmptyStateFrame from "./ui/components/CadenceEmptyStateFrame.vue"\n',
    boundaries: Object.freeze([
      Object.freeze({
        name: "fleet",
        migrated: lines(
          '        <CadenceEmptyStateFrame v-if="roster.fleet_empty">',
          "          <template #title>No spacecraft yet</template>",
          "          <template #description>",
          "            Register the first spacecraft for this mission.",
          "          </template>",
          "          <template #action>",
          "            <a",
          '              :href="roster.new_spacecraft_href"',
          '              data-phx-link="redirect"',
          '              data-phx-link-state="push"',
          '              class="btn btn-primary btn-sm"',
          "            >",
          '              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>',
          "              Register the first spacecraft",
          "            </a>",
          "          </template>",
          "        </CadenceEmptyStateFrame>",
        ),
        predecessor: lines(
          "        <div",
          '          v-if="roster.fleet_empty"',
          `          class="${emptyStateRootClass}"`,
          "        >",
          '          <p class="hud-label">No spacecraft yet</p>',
          `          <p class="${emptyStateDescriptionClass}">`,
          "            Register the first spacecraft for this mission.",
          "          </p>",
          `          <div class="${emptyStateActionContainerClass}">`,
          "            <a",
          '              :href="roster.new_spacecraft_href"',
          '              data-phx-link="redirect"',
          '              data-phx-link-state="push"',
          '              class="btn btn-primary btn-sm"',
          "            >",
          '              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>',
          "              Register the first spacecraft",
          "            </a>",
          "          </div>",
          "        </div>",
        ),
      }),
      Object.freeze({
        name: "profiles",
        migrated: lines(
          '        <CadenceEmptyStateFrame v-if="profiles.empty">',
          "          <template #title>No profiles yet</template>",
          "          <template #description>",
          "            Create a profile to reuse frame and packet interpretation settings across spacecraft.",
          "          </template>",
          "          <template #action>",
          "            <a",
          '              :href="profiles.new_profile_href"',
          '              data-phx-link="redirect"',
          '              data-phx-link-state="push"',
          '              class="btn btn-primary btn-sm"',
          "            >",
          '              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>',
          "              Create the first profile",
          "            </a>",
          "          </template>",
          "        </CadenceEmptyStateFrame>",
        ),
        predecessor: lines(
          "        <div",
          '          v-if="profiles.empty"',
          `          class="${emptyStateRootClass}"`,
          "        >",
          '          <p class="hud-label">No profiles yet</p>',
          `          <p class="${emptyStateDescriptionClass}">`,
          "            Create a profile to reuse frame and packet interpretation settings across spacecraft.",
          "          </p>",
          `          <div class="${emptyStateActionContainerClass}">`,
          "            <a",
          '              :href="profiles.new_profile_href"',
          '              data-phx-link="redirect"',
          '              data-phx-link-state="push"',
          '              class="btn btn-primary btn-sm"',
          "            >",
          '              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>',
          "              Create the first profile",
          "            </a>",
          "          </div>",
          "        </div>",
        ),
      }),
    ]),
  }),
  Object.freeze({
    file: "CommsOverview.vue",
    repositoryPath: "apps/cadence_web/assets/vue/CommsOverview.vue",
    predecessorByteLength: 7_265,
    predecessorSha256: "0ff2f4e068cd320c2af9bba19b2add1af55e99e6685fa024fc490ce0396b110d",
    importLine:
      'import CadenceEmptyStateFrame from "./ui/components/CadenceEmptyStateFrame.vue"\n',
    boundaries: Object.freeze([
      Object.freeze({
        name: "transport",
        migrated: lines(
          "          <CadenceEmptyStateFrame>",
          "            <template #title>{{ overview.transport.empty_state.title }}</template>",
          "            <template #description>",
          "              {{ overview.transport.empty_state.description }}",
          "            </template>",
          "            <template #action>",
          "              <a",
          '                :href="overview.transport.empty_state.action_href"',
          '                data-phx-link="redirect"',
          '                data-phx-link-state="push"',
          '                class="btn btn-primary btn-sm"',
          "              >",
          '                <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>',
          "                {{ overview.transport.empty_state.action_label }}",
          "              </a>",
          "            </template>",
          "          </CadenceEmptyStateFrame>",
        ),
        predecessor: lines(
          `          <div class="${emptyStateRootClass}">`,
          '            <p class="hud-label">{{ overview.transport.empty_state.title }}</p>',
          `            <p class="${emptyStateDescriptionClass}">`,
          "              {{ overview.transport.empty_state.description }}",
          "            </p>",
          `            <div class="${emptyStateActionContainerClass}">`,
          "              <a",
          '                :href="overview.transport.empty_state.action_href"',
          '                data-phx-link="redirect"',
          '                data-phx-link-state="push"',
          '                class="btn btn-primary btn-sm"',
          "              >",
          '                <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>',
          "                {{ overview.transport.empty_state.action_label }}",
          "              </a>",
          "            </div>",
          "          </div>",
        ),
      }),
    ]),
  }),
])

export const cadenceEmptyStateMigration = Object.freeze({
  file: "ui/components/CadenceEmptyState.vue",
  repositoryPath: "apps/cadence_web/assets/vue/ui/components/CadenceEmptyState.vue",
  predecessorByteLength: 673,
  predecessorSha256: "f858d52b71d7c8ad2803402cb18095bc4694a220e1858f45fc17ff8272790763",
  importLine: 'import CadenceEmptyStateFrame from "./CadenceEmptyStateFrame.vue"\n',
  boundaries: Object.freeze([
    Object.freeze({
      migrated: lines(
        "  <CadenceEmptyStateFrame",
        '    :root-attrs="props.emptyState.attrs"',
        '    :title-attrs="props.emptyState.title.attrs"',
        '    :description-attrs="props.emptyState.description.attrs"',
        '    :action-container-attrs="props.emptyState.action_container.attrs"',
        "  >",
        "    <template #title>",
        "      {{ props.emptyState.title.text }}",
        "    </template>",
      ),
      predecessor: lines(
        '  <div v-bind="props.emptyState.attrs">',
        '    <p v-bind="props.emptyState.title.attrs">',
        "      {{ props.emptyState.title.text }}",
        "    </p>",
      ),
    }),
    Object.freeze({
      migrated: lines(
        "    <template #description>",
        "      {{ props.emptyState.description.text }}",
        "    </template>",
      ),
      predecessor: lines(
        '    <p v-bind="props.emptyState.description.attrs">',
        "      {{ props.emptyState.description.text }}",
        "    </p>",
      ),
    }),
    Object.freeze({
      migrated: lines(
        "    <template #action>",
        '      <a v-bind="props.emptyState.action.attrs">',
        '        <span v-bind="props.emptyState.action.icon.attrs"></span>',
        "        {{ props.emptyState.action.text }}",
        "      </a>",
        "    </template>",
        "  </CadenceEmptyStateFrame>",
      ),
      predecessor: lines(
        '    <div v-bind="props.emptyState.action_container.attrs">',
        '      <a v-bind="props.emptyState.action.attrs">',
        '        <span v-bind="props.emptyState.action.icon.attrs"></span>',
        "        {{ props.emptyState.action.text }}",
        "      </a>",
        "    </div>",
        "  </div>",
      ),
    }),
  ]),
})

export const cadenceEmptyStateConsumers = Object.freeze([
  Object.freeze({
    file: "AdminOrganizationListPage.vue",
    repositoryPath: "apps/cadence_web/assets/vue/AdminOrganizationListPage.vue",
    byteLength: 3_095,
    sha256: "be8ccb29a9ddc84a2da1e2d1805b46a3a0ea0bdd1cf9ffe7cf4df54578475b31",
  }),
  Object.freeze({
    file: "CommsGroundStationListPage.vue",
    repositoryPath: "apps/cadence_web/assets/vue/CommsGroundStationListPage.vue",
    byteLength: 2_431,
    sha256: "2ae24a9c5293e520246ec60965020a0e1bf2c5e5debb03480a7489538c172563",
  }),
  Object.freeze({
    file: "CommsRoutingListPage.vue",
    repositoryPath: "apps/cadence_web/assets/vue/CommsRoutingListPage.vue",
    byteLength: 1_541,
    sha256: "dac57e791b02b4e16ea28270c0809c5d8fd88f8d011eabda164b7ec2bf047c15",
  }),
  Object.freeze({
    file: "CommsTransportListPage.vue",
    repositoryPath: "apps/cadence_web/assets/vue/CommsTransportListPage.vue",
    byteLength: 1_587,
    sha256: "483c4d676708981ae3d158c16ce9939e84dde3f095cc798009cb89aa69df2b5c",
  }),
  Object.freeze({
    file: "SpacecraftTypeListPage.vue",
    repositoryPath: "apps/cadence_web/assets/vue/SpacecraftTypeListPage.vue",
    byteLength: 1_559,
    sha256: "ac8180c29ea44c68dcb69096e895f2f2c037a8d5bc0c9b440e51956051840560",
  }),
])

export const emptyStateVariantLedger = Object.freeze([
  Object.freeze({
    file: "SpacecraftList.vue",
    repositoryPath: "apps/cadence_web/assets/vue/SpacecraftList.vue",
    count: 2,
    classification: "migrate exact action-bearing fleet and profiles cohort",
  }),
  Object.freeze({
    file: "CommsOverview.vue",
    repositoryPath: "apps/cadence_web/assets/vue/CommsOverview.vue",
    count: 2,
    classification: "migrate transport; exclude validation because it has no action",
  }),
  Object.freeze({
    file: "MissionOverview.vue",
    repositoryPath: "apps/cadence_web/assets/vue/MissionOverview.vue",
    byteLength: 8_327,
    sha256: "b022e169cb4a4c6447de811069ae1fe1eaab3d73740e51396fc9dad5229440f4",
    count: 1,
    classification: "exclude action-bearing shape without the canonical description",
  }),
  Object.freeze({
    file: "SpacecraftRouting.vue",
    repositoryPath: "apps/cadence_web/assets/vue/SpacecraftRouting.vue",
    byteLength: 3_567,
    sha256: "5d279425cfd5f308b8ac30b9cc6971f214607b5b18c1e715e2eb8f972a30e839",
    count: 1,
    classification: "exclude no-action variant with reordered description classes",
  }),
  Object.freeze({
    file: "CommsValidation.vue",
    repositoryPath: "apps/cadence_web/assets/vue/CommsValidation.vue",
    byteLength: 4_894,
    sha256: "8fc0ad5f36acf76da3bdd81dc719d05a029f3825f8644e761dfdb6ba986adfd4",
    count: 1,
    classification: "exclude no-action variant with reordered description classes",
  }),
  Object.freeze({
    file: "AdminOrganizationShow.vue",
    repositoryPath: "apps/cadence_web/assets/vue/AdminOrganizationShow.vue",
    byteLength: 10_940,
    sha256: "fd8deae26562c2b6b68c186416946d6513ee5134c975daadc7972a3442478a9a",
    count: 1,
    classification: "exclude no-action root without rounded",
  }),
  Object.freeze({
    file: "OpsContactRequirementList.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsContactRequirementList.vue",
    byteLength: 5_499,
    sha256: "878390e2432063248890c76d599feec4e0695f1e049d59c8ca77da6312cd1ad8",
    count: 1,
    classification: "exclude different root classes and shape",
  }),
  Object.freeze({
    file: "OpsDashboardActivity.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDashboardActivity.vue",
    byteLength: 8_087,
    sha256: "8aaf5a4277bfb5b9ef8e0f74eb09b90ded26f9ee3f7bdf08daf4d7fb6cf77ce6",
    count: 1,
    classification: "exclude stream-only paragraph shape",
  }),
  Object.freeze({
    file: "OpsDashboardDirectory.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDashboardDirectory.vue",
    byteLength: 12_658,
    sha256: "305b2c5fbae09713197e2c2ba1cbc9e7a88777142444c18d10b9109269959b5c",
    count: 1,
    classification: "exclude stream-only flex shape",
  }),
  Object.freeze({
    file: "OpsDashboardLibrary.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDashboardLibrary.vue",
    byteLength: 21_114,
    sha256: "0c522ba61f458a97064d22bd246e70b76cc08e592315a22494e784d04df36883",
    count: 1,
    classification: "exclude stream-only single-copy shape",
  }),
  Object.freeze({
    file: "OpsDashboardPlaylists.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDashboardPlaylists.vue",
    byteLength: 8_915,
    sha256: "4084749b4e50c73fd43f24f73d19c1b49914f73e2146ab7b2d4e38fb0338c510",
    count: 1,
    classification: "exclude stream-only single-copy shape",
  }),
  Object.freeze({
    file: "OpsDataSources.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDataSources.vue",
    byteLength: 65_754,
    sha256: "216d258ab5725d7b7a6d5fe2f5cd79a9c091a42548c1b9611de214942a10c6ff",
    count: 1,
    classification: "exclude different padding and single-copy shape",
  }),
])

export const emptyStateFrameMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const migration = emptyStateFrameMigrations.find((entry) => entry.file === file)

  assert.ok(migration, `${caller} is an audited CadenceEmptyStateFrame caller`)
  return migration
}

export const peelCadenceEmptyStateFrames = (source, caller) => {
  const migration = emptyStateFrameMigrationFor(caller)

  assert.equal(occurrences(source, migration.importLine), 1, `${migration.file} exact import count`)
  assert.equal(
    source.match(/^import CadenceEmptyStateFrame\b/gm)?.length,
    1,
    `${migration.file} import declaration count`,
  )
  assert.equal(
    source.match(/<CadenceEmptyStateFrame\b/g)?.length,
    migration.boundaries.length,
    `${migration.file} exact opening count`,
  )
  assert.equal(
    occurrences(source, "</CadenceEmptyStateFrame>"),
    migration.boundaries.length,
    `${migration.file} exact closing count`,
  )

  let predecessor = source.replace(migration.importLine, "")

  for (const boundary of migration.boundaries) {
    assert.equal(
      occurrences(predecessor, boundary.migrated),
      1,
      `${migration.file} ${boundary.name} migrated boundary is exact and unique`,
    )
    assert.equal(occurrences(predecessor, boundary.predecessor), 0)
    predecessor = predecessor.replace(boundary.migrated, boundary.predecessor)
  }

  assert.doesNotMatch(predecessor, /CadenceEmptyStateFrame/)
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(emptyStateSha256(predecessor), migration.predecessorSha256)
  return predecessor
}

export const peelCadenceEmptyStateComponent = (source) => {
  const migration = cadenceEmptyStateMigration

  assert.equal(occurrences(source, migration.importLine), 1)
  assert.equal(source.match(/<CadenceEmptyStateFrame\b/g)?.length, 1)
  assert.equal(occurrences(source, "</CadenceEmptyStateFrame>"), 1)

  let predecessor = source.replace(migration.importLine, "")

  for (const [index, boundary] of migration.boundaries.entries()) {
    assert.equal(
      occurrences(predecessor, boundary.migrated),
      1,
      `CadenceEmptyState.vue boundary ${index + 1} is exact and unique`,
    )
    predecessor = predecessor.replace(boundary.migrated, boundary.predecessor)
  }

  assert.doesNotMatch(predecessor, /CadenceEmptyStateFrame/)
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(emptyStateSha256(predecessor), migration.predecessorSha256)
  return predecessor
}
