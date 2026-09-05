import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {
  peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers,
} from "./compact_page_header_body_frame_test_support.mjs"
import {
  peelCadenceDashboardSettingsSectionFrameBeforeOlderLayers,
} from "./dashboard_settings_section_frame_test_support.mjs"
import {peelCompactTableFrames} from "./compact_table_frame_test_support.mjs"
import {peelCadenceDiagnosticsSectionFrame} from "./diagnostics_section_frame_test_support.mjs"
import {peelResidualCadenceCardBeforeOlderLayers} from "./residual_cadence_cards_test_support.mjs"
import {peelCadenceStatTileBeforeOlderLayers} from "./stat_tile_test_support.mjs"
import {peelCadenceFormSectionFrameBeforeOlderLayers} from "./form_section_frame_test_support.mjs"

export const pageTitlePredecessorCommit = "78cf304ae600958a7058c81c369161cb9cb76f52"
export const pageTitleClass = "mt-2 text-2xl font-bold text-base-content tracking-tight"
export const pageTitleImport =
  'import CadencePageTitle from "./ui/components/CadencePageTitle.vue"\n'

const migration = (file, predecessorSha256, predecessorByteLength, indent = "          ") =>
  Object.freeze({
    file,
    predecessorCommit: pageTitlePredecessorCommit,
    predecessorSha256,
    predecessorByteLength,
    importLine: pageTitleImport,
    opening: `${indent}<CadencePageTitle>`,
    predecessorOpening: `${indent}<h1 class="${pageTitleClass}">`,
    closing: `${indent}</CadencePageTitle>`,
    predecessorClosing: `${indent}</h1>`,
  })

export const pageTitleMigrations = Object.freeze([
  migration("AdminHome.vue", "b3e55c1d9eb03b673ca1112b1547a1719fe664a4d6d24e1e905ef621d0501fbd", 4400),
  migration("AdminOrganizationInvite.vue", "b8ef18aa13afa4cadcc0e089d2f483ffe3e9813ce9e3680b744b727367f3b6a9", 6682, "        "),
  migration("AdminRuntime.vue", "f08d69e50a0c21b22a19bb2ed865e5b7c162ea71fb73b6f2eeee2b56177eff4e", 18429),
  migration("CatalogDatabaseNew.vue", "99307f72c2effe78249151277b7cfb9b843fa6081273876f0833580c5a1e7776", 2430),
  migration("CatalogImportRunShow.vue", "8992dbc4498b30bc681157c85ffc60a536cbcced8239fb7f69feacb0dcd2c64b", 5665),
  migration("CommsGroundStationForm.vue", "648335716563fd4c5f7c07ba63aaa3e6e90ef256ccd9a5e543396aa1b5b9bab0", 9981),
  migration("CommsGroundStationShow.vue", "05309beb0d0212fde5d2c966613b9cc3dfc1f5ec76ed3edbc435174f23756a29", 4109),
  migration("CommsProviderShow.vue", "84189165ad50ce3d0fd70f6db674959b6aece25db0fba46177029fec88159106", 14087),
  migration("CommsRoutingNew.vue", "40465145e73c54c04b2e5d8d710f4d1c27786ac239bec656190c3cca35c0ec82", 11471),
  migration("CommsRoutingShow.vue", "abc23dec50d55c61f9f016b38dcdbf917dd549daf1fac0e742affebb45b5866e", 4537),
  migration("CommsTransportNew.vue", "91ed432221a81a7b7aff88c694e91dd0c96b1b3cc24736e5bbc9c5e517ab2d54", 29225),
  migration("CommsTransportShow.vue", "67de9b87da34cc755472c0ea9b39d967b5c0bf766e1b16426c28caf28301923e", 6318, "        "),
  migration("CommsValidation.vue", "ef7f42513c6b2eb45f99d2ec99a7aa130773496839083795815d5b2260dea154", 4863),
  migration("MissionNew.vue", "56f55ae62d140bda6b2b45764688fc628976563b5e9d471f5596e5344eb34081", 4627),
  migration("MissionOverview.vue", "b21d7bf85cd2432098819f2cefd3817a10f607ecabe45c9ce3062dee6f46c7e1", 8296, "        "),
  migration("OpsActivationRequests.vue", "95dd04a4b86d926df793a35685586db24502a7c56b0a321dc072138a2a9af679", 6138),
  migration("ProviderAccountShow.vue", "a801ab2e648379a2ba651cf5d20a794722c7717e3c503985c425ddca328c00fa", 17564),
  migration("SpacecraftCommanding.vue", "d66fe6df0c6caab94c2faa20e0deded9dbab028c24acba69c2fb7e004ea2c8dc", 3607),
  migration("SpacecraftEdit.vue", "659692ad92fd77b7e47de5c5de7c19919da52a67fda1068af426c0e23a205a8f", 7734),
  migration("SpacecraftNew.vue", "f16542ef00308c768b141fd704ec1d1d3c6acb69f47e4d83d7bd6b68427974a5", 8261),
  migration("SpacecraftReadiness.vue", "8320051236b122b3828ca9b5d43b46216854bfd51c849941aa57166eb20e6efe", 4878),
  migration("SpacecraftRouting.vue", "ea231d09402982a686705d898cb4bb090786d8e29c14e4fed45aaaf36166ea89", 3536),
  migration("SpacecraftShow.vue", "bad5d15dcb455ef2eee83f3e2141100b55e836abc05e54b7308ccdd8f219de2a", 11113),
  migration("SpacecraftTelemetryDecom.vue", "56c99ec5256281073c54d10f3c7f7431a469356073d536fb4c5891b36b150ae1", 22597),
  migration("SpacecraftTypeNew.vue", "cdf6d99e7cd67d584569c052cbdb1ea72e9205ae90b12d605cb6d897e21d580e", 17655),
  migration("SpacecraftTypeShow.vue", "b66a08a20679bcd44614dad48dde7858d0bb6222ed135f1a2c8c6fa07d202a21", 7519, "        "),
])

export const pageTitleCallerNames = Object.freeze(
  pageTitleMigrations.map(({file}) => file),
)

const exclusion = (file, sha256, reason, opening) =>
  Object.freeze({file, sha256, reason, opening, count: 1})

export const excludedPageTitles = Object.freeze([
  exclusion("AdminModePage.vue", "632a04a5c74b4ab590d408fafd0cb31b9b3ded997ca7c5f9837e880a3d4ab5b8", "dynamic", '<h1 v-bind="presentation.header.heading.attrs">'),
  exclusion("AdminOrganizationNew.vue", "d6112394e350ad1ae08c45b6aefd7e0577ee530045b1d42ad2f507394cc16bf2", "reordered-token", '<h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">'),
  exclusion("AdminOrganizationShow.vue", "fd8deae26562c2b6b68c186416946d6513ee5134c975daadc7972a3442478a9a", "reduced-or-structural", '<h1 class="text-2xl font-bold tracking-tight text-base-content">'),
  exclusion("ApplicationHost.vue", "3970225aa801fe5a126d78298b836d4a5531989bc52d197ee0be0aeab171382e", "reduced-or-structural", '<h1 class="text-2xl font-bold tracking-tight text-base-content">'),
  exclusion("CatalogArtifactShowPage.vue", "e0957d7ea8c5bd9be2df14e41fe37ee00b530e8809fb24f4f70bcb36cc32cb27", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("CatalogDatabaseShow.vue", "e53ccd210551222dd582fc54189f9f5d33aaed7f85e2072d6b7943a73886697f", "reordered-token", '<h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">'),
  exclusion("CatalogIndex.vue", "4c8c514813f8e90f756048880d1f3bbd6eacfbfb27fd1a565cb3564f169f819c", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("CatalogRevisionShow.vue", "e852e8fbaaaf43b59d5bc846eeefcf1dfb0c1b6a72f18f0fc309f869669118ab", "reordered-token", '<h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">'),
  exclusion("CommsOverviewPage.vue", "9ba5c8d437a30b921bd9c127b3974c99d95fdf587b8204f2a5d59c7123bb1459", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("CommsProviderList.vue", "c440d997fa54dd9d7f75acb3e31b81688be3ff8b72ad4f51b6388d7dc2ef113f", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("CommsProviderNew.vue", "a2d6937f98d77372226f0f3b3b7224dae00338c963da25cc4628f6801ae3223a", "reordered-token", '<h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">'),
  exclusion("MissionApplicationsPage.vue", "27312a2349986804b5359d7b7159a798e482b9b314f2576898663d7a8e06e537", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("MissionList.vue", "fe5b2278303ae0ba0a6f806f654bcc848c833b857a3b4dd35723f76f131387c2", "dynamic", '<h1 :class="presentation.header.title.class">'),
  exclusion("NoOrganizationPage.vue", "60e0dda5f3cbddbb542a34e6aa3ce7b66d85e031bc5cc9e474ff18c0ac5536b4", "dynamic", '<h1 v-bind="presentation.heading.attrs">'),
  exclusion("NotificationsPage.vue", "6d0cfbf7bfc192f3db85cdfa52e90948d5bbe150decbee111a5ce3e77f24941a", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("OpsDashboardDirectory.vue", "95fcf3572a69ad44b90d82c018323b2b6e54e616c78ff340db35c86149b3e468", "ops-mt-1", '<h1 class="mt-1 text-2xl font-bold tracking-tight">'),
  exclusion("OpsDashboardLibrary.vue", "4580ffd9942e653ebed6f8ddcc8098074e35418bacabaa64a050b4c051ddb56e", "ops-mt-1", '<h1 class="mt-1 text-2xl font-semibold">'),
  exclusion("OpsDashboardNew.vue", "1927f51f06f1e3a02ae5e5cf2829c6ea4f56d22f5029961ca201220a16bc333f", "ops-mt-1", '<h1 class="mt-1 text-2xl font-bold tracking-tight">'),
  exclusion("OpsDashboardPlaylists.vue", "8a4fcc04ba7e1643f82e47ce8e42bbcff5b2354b38fffc28131e676d3f6232bc", "ops-mt-1", '<h1 class="mt-1 text-2xl font-semibold">'),
  exclusion("OpsDashboardSettings.vue", "2c936e742eab32cc55c3fe95979750b885aefb71ebe6cb1c20a57791e9bfd31d", "ops-mt-1", '<h1 class="mt-1 text-2xl font-bold tracking-tight">'),
  exclusion("OpsDashboardShare.vue", "92903b435d264e30dcf569631ccdaa0610a696ac8385199a3d389641003ec009", "reduced-or-structural", '<h1 class="mt-2 text-2xl font-semibold">'),
  exclusion("OrganizationHome.vue", "60790fdad5a54a7e65c465b6e3c16c0d3eb1c699d40d98590d6e466033ce8af3", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("OrganizationInvitationPage.vue", "3494611ebed9b230a1281a6a926a54204cf0582d47bfc1fbd1c94ae838f220fb", "dynamic", '<h1 v-bind="presentation.header.heading.attrs">'),
  exclusion("ProviderAccountListPage.vue", "8455584179159d7913ae2ff7a976ee03450e59388a591c97463943d6cf4f3d6b", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("ProviderAccountNew.vue", "69d6a4485b685ddf6c1c386baa3b33a1a697f63ed2fd977585a3c8de1a4a407b", "reordered-token", '<h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">'),
  exclusion("SpacecraftApplicationsPage.vue", "e5206e8c690a9a53f9577659ebf3ad75ce274785ac065ccbb07b97f0a33f3afb", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("SpacecraftListPage.vue", "d8a30f2d054e4028e1b01176e3189e532386094073c8b8b5d482550b062d3c7e", "dynamic", '<h1 v-bind="props.presentation.header.title.attrs">'),
  exclusion("UserSession.vue", "648ccfb67f73e7731866d67dbb598d084237213485775caa47ed00b39090597f", "reduced-or-structural", '<h1 class="mt-3 text-xl font-bold text-base-content">'),
  exclusion("ui/components/CadencePageHeader.vue", "63b50b02aa688d224c901f6ae27eda2d2825862d5719304f476d9b40dc9f6414", "dynamic", '<h1 v-bind="props.header.title.attrs">'),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const sha256 = (source) => createHash("sha256").update(source).digest("hex")

export const pageTitleMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const found = pageTitleMigrations.find((entry) => entry.file === file)

  assert.ok(found, `${caller} is an audited CadencePageTitle caller`)
  return found
}

export const peelCadencePageTitle = (source, caller) => {
  const entry = pageTitleMigrationFor(caller)
  const formSectionFrameCompatibleSource = peelCadenceFormSectionFrameBeforeOlderLayers(
    source,
    caller,
  )
  const dashboardSettingsCompatibleSource =
    peelCadenceDashboardSettingsSectionFrameBeforeOlderLayers(
      formSectionFrameCompatibleSource,
      caller,
    )
  const compactHeaderBodyCompatibleSource =
    peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers(
      dashboardSettingsCompatibleSource,
      caller,
    )
  const statTileCompatibleSource = peelCadenceStatTileBeforeOlderLayers(
    compactHeaderBodyCompatibleSource,
    caller,
  )
  const residualCardCompatibleSource = peelResidualCadenceCardBeforeOlderLayers(
    statTileCompatibleSource,
    caller,
  )
  const diagnosticsCompatibleSource = peelCadenceDiagnosticsSectionFrame(
    residualCardCompatibleSource,
    caller,
  )
  const predecessorCompatibleSource = peelCompactTableFrames(diagnosticsCompatibleSource, caller)

  assert.equal(
    occurrences(predecessorCompatibleSource, entry.importLine),
    1,
    `${entry.file} title import count`,
  )
  assert.equal(predecessorCompatibleSource.match(/^import CadencePageTitle\b/gm)?.length, 1)
  assert.equal(
    occurrences(predecessorCompatibleSource, entry.opening),
    1,
    `${entry.file} exact title opening`,
  )
  assert.equal(
    occurrences(predecessorCompatibleSource, entry.closing),
    1,
    `${entry.file} exact title closing`,
  )
  assert.equal(predecessorCompatibleSource.match(/<CadencePageTitle\b/g)?.length, 1)
  assert.equal(predecessorCompatibleSource.match(/<\/CadencePageTitle>/g)?.length, 1)

  const predecessor = predecessorCompatibleSource
    .replace(entry.importLine, "")
    .replace(entry.opening, entry.predecessorOpening)
    .replace(entry.closing, entry.predecessorClosing)

  assert.doesNotMatch(predecessor, /CadencePageTitle/)
  return predecessor
}
