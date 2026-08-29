import assert from "node:assert/strict";

export const compactHeaderBodyBase = "41063fbbb2bcdcb5c509929b6550b0689a210838";
export const compactHeaderBodyFrameClass =
  "flex items-end justify-between gap-4";
export const compactHeaderBodyActionsClass = "flex items-center gap-2";
export const compactHeaderBodyFramePath =
  "apps/cadence_web/assets/vue/ui/components/CadenceCompactPageHeaderBodyFrame.vue";
export const compactHeaderBodyImport =
  'import CadenceCompactPageHeaderBodyFrame from "./ui/components/CadenceCompactPageHeaderBodyFrame.vue"\n';

const migration = (file, byteLength, blobId, sha256) =>
  Object.freeze({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    byteLength,
    blobId,
    sha256,
  });

export const compactHeaderBodyMigrations = Object.freeze([
  migration(
    "AdminRuntime.vue",
    18_580,
    "c144dad384761a2a7c765f9654e82407b56c4559",
    "c2ec39b90c5c7fbd8320f9a46c3f5e34953b63b7e36488d6e767e741083b9197"
  ),
  migration(
    "CatalogDatabaseShow.vue",
    7_729,
    "9f6d688b38518cdab318d5303027e02e5305a697",
    "e53ccd210551222dd582fc54189f9f5d33aaed7f85e2072d6b7943a73886697f"
  ),
  migration(
    "CommsGroundStationShow.vue",
    4_140,
    "659465a90f2e3b43e19105f84930e664d6d76de5",
    "05c2e2545988e476a1d384b8784012e33cf8636b000bbeb301d4dca7868f8e7e"
  ),
  migration(
    "CommsProviderShow.vue",
    14_150,
    "72d4c5bdc58f1fd2b29a76e54e38f6aa668e87bb",
    "fc691ee3fc3bc2f50e0bb832d843230dde8eb7a47efc4445bfb27dbd44b8dd79"
  ),
  migration(
    "CommsRoutingShow.vue",
    4_568,
    "c41b1c72c948793030ac88ad581d0cda7afc1b12",
    "4c126d6d55621b4432ff6b2fee495d4103c1ca65034dae7d9cb08e1655b087ec"
  ),
  migration(
    "CommsValidation.vue",
    4_894,
    "125983640366a369f75df8cbbeb6d6490df7c630",
    "8fc0ad5f36acf76da3bdd81dc719d05a029f3825f8644e761dfdb6ba986adfd4"
  ),
  migration(
    "ProviderAccountShow.vue",
    17_627,
    "7abb3332c0954d0548ef2d1e1d6b5179cd506fe3",
    "8518cddc5ed3fb10dfaf935640a1d3d0658e1b7e5ad371a721a1cffb752da5af"
  ),
  migration(
    "SpacecraftCommanding.vue",
    3_638,
    "84f17c8dd2540c4218a2a6f2d378ee70da6d3ded",
    "df54441a7035eedf582096a394cef7de949a51a20d4a6c99a23e10ccb8fc82ef"
  ),
  migration(
    "SpacecraftReadiness.vue",
    4_909,
    "446fb79eb97f9f9bf3385ca359e23e1fcf22a39c",
    "632f00d7decb18e160ae4b536c475e4fae0c644b14b559535e633ded844163bd"
  ),
  migration(
    "SpacecraftRouting.vue",
    3_567,
    "9d5f7f731907b11d77f7ee069f144704b57bec17",
    "5d279425cfd5f308b8ac30b9cc6971f214607b5b18c1e715e2eb8f972a30e839"
  ),
]);

export const compactHeaderBodyCallerNames = Object.freeze(
  compactHeaderBodyMigrations.map(({ file }) => file)
);

export const compactHeaderBodyExclusions = Object.freeze([
  migration(
    "AdminHome.vue",
    4_401,
    "e431bc5bec85880603385a76a49333ca6b939ac3",
    "aaa5f4280d134f5d2803abe9672368e2bc448856288405ee36be218943511046"
  ),
  migration(
    "AdminOrganizationInvite.vue",
    6_713,
    "b93f7f64132b69ebf0c7198740e303f3759902d5",
    "8befd265374e5f79cc751541b519ec254a4d5f5923ff2fd5683afd000494bad6"
  ),
  migration(
    "AdminOrganizationNew.vue",
    4_116,
    "ab1461244b559674ff658a2713354725ae12a62e",
    "d6112394e350ad1ae08c45b6aefd7e0577ee530045b1d42ad2f507394cc16bf2"
  ),
  migration(
    "AdminOrganizationShow.vue",
    10_940,
    "f0295491362350daf535e06731bc4b0dd2b0682d",
    "fd8deae26562c2b6b68c186416946d6513ee5134c975daadc7972a3442478a9a"
  ),
  migration(
    "ApplicationHost.vue",
    35_661,
    "5753df2f06de687b622a4aafe0394382d264badf",
    "5e9e6c109b027ab7e05e18ec0dd9dbb1cebd842e6b0682cf3dbcdc4bf580dd62"
  ),
  migration(
    "CatalogDatabaseNew.vue",
    2_461,
    "92e1a6cf6da9d20da0828870a7a52219782e9f64",
    "e13f68e791358cd0b39dad382fc88b9f68cbf066494fdfa4fe2c8d5129447eaa"
  ),
  migration(
    "CatalogImportRunShow.vue",
    5_696,
    "5959b48c0211843e0092d26da6b7901e305b8311",
    "daad787cf196f0f7356259c666c82404a5bfba248e073ff3b27ced3ef7b07d8c"
  ),
  migration(
    "CatalogRevisionShow.vue",
    4_859,
    "ded74a04b18bcf9d316d68e12efeae6293a71434",
    "e852e8fbaaaf43b59d5bc846eeefcf1dfb0c1b6a72f18f0fc309f869669118ab"
  ),
  migration(
    "CommsGroundStationForm.vue",
    10_012,
    "68b9175b40dbd088c2fbf2fe8a35fc0bf1ead974",
    "edd1ab8aa48a31f0a5aada4ae515fdb2674c5d9f6791dfe9c14c981e045fce53"
  ),
  migration(
    "CommsProviderNew.vue",
    14_731,
    "464ec673751eea88f1bbdf3168733d7464c473ca",
    "a2d6937f98d77372226f0f3b3b7224dae00338c963da25cc4628f6801ae3223a"
  ),
  migration(
    "CommsRoutingNew.vue",
    11_502,
    "0a8f75e8e19e03bb0a1bbc1e435738080b84b109",
    "e7105ab001c2b56ff8b95f0aa88420af473ae8a95916341924693688d3016706"
  ),
  migration(
    "CommsTransportNew.vue",
    29_200,
    "5fc0f740a673b7c10d6a43fad1bc209bab0069c7",
    "6aae5a50c304208f1fc95b9419919830dfe5dd181d4662ea08d72075b5f5f8be"
  ),
  migration(
    "CommsTransportShow.vue",
    6_381,
    "08fe71a12f42bbe33e8b27b48957849670d69654",
    "269a5138bf7b01371a036cb6c1e41375b51a554db5a73b936753914fb0dcccf7"
  ),
  migration(
    "MissionNew.vue",
    4_658,
    "ce1250d569d0b6e7a6f4b6d0a4e207030d25b8bf",
    "e37f62e4c1f9233e6dc19447e40710b08d2ac06ed4f34ef4f120870ea14a351e"
  ),
  migration(
    "MissionOverview.vue",
    8_327,
    "6786751ea4dc536abe839dbc4acde5e79a24d9b4",
    "b022e169cb4a4c6447de811069ae1fe1eaab3d73740e51396fc9dad5229440f4"
  ),
  migration(
    "OpsActivationRequests.vue",
    6_169,
    "930db5e43d197d985e5ede1361d8f6bfd29bd1ae",
    "36bc3405332eb8dcfb64b54a35723696025500955db6b0ae8ff8571c72172819"
  ),
  migration(
    "ProviderAccountNew.vue",
    16_832,
    "40e5f623b1bbf58881c5890a3d2f65001b434de8",
    "69d6a4485b685ddf6c1c386baa3b33a1a697f63ed2fd977585a3c8de1a4a407b"
  ),
  migration(
    "SpacecraftEdit.vue",
    7_765,
    "a6bfd5ecaae1f65306918b362ade2fd99608cb7d",
    "bfe056fb735cdfd4b33b217bbb571410cccc5d146218c63471133c74148c08a9"
  ),
  migration(
    "SpacecraftNew.vue",
    8_292,
    "2f35662955e1f4459a7159c3f3386643925d5a48",
    "a8bcc877716b4b055a6b22013d0202c1347c29b1170cc071e1dbe4eaaed8802e"
  ),
  migration(
    "SpacecraftShow.vue",
    11_144,
    "3164157ae0252c30bb2c31ba62878b13f1c066a5",
    "8f7d6aadc771a809abbecd6b684dc80bcadaaaa77b67789e763b5b4a5b57c914"
  ),
  migration(
    "SpacecraftTelemetryDecom.vue",
    22_605,
    "3e0a9a08d825d7cbe299ea92a760e12321e4be48",
    "47ea4ad281b2e36efb1c687cc0c0c7ba81ca5f0e6de2655097095b8317cf5fb8"
  ),
  migration(
    "SpacecraftTypeNew.vue",
    17_686,
    "05f48545e7459ef6e258d7d40a050857479d42a7",
    "63d684bbd5638bea9ad2ee17e53f052a46a73bb278a79ea8dee7e0c429717fa3"
  ),
  migration(
    "SpacecraftTypeShow.vue",
    7_550,
    "145f67104f7ef01640793acb61cfbef2bef6a1c0",
    "a08efbd3af6f67150cc500538d39aaac1b94a7a3d400af864fc850bdda36e380"
  ),
]);

const occurrences = (source, fragment) => source.split(fragment).length - 1;

export const compactHeaderBodyMigrationFor = (caller) => {
  const file = caller.split("/").at(-1);
  const migrationEntry = compactHeaderBodyMigrations.find(
    (entry) => entry.file === file
  );

  assert.ok(
    migrationEntry,
    `${caller} is an audited compact header-body caller`
  );
  return migrationEntry;
};

export const peelCadenceCompactPageHeaderBodyFrame = (source, caller) => {
  const migrationEntry = compactHeaderBodyMigrationFor(caller);
  const frameOpening = "      <CadenceCompactPageHeaderBodyFrame>";
  const frameClosing = "      </CadenceCompactPageHeaderBodyFrame>";
  const contentOpening = "        <template #content>";
  const actionsOpening = "        <template #actions>";

  assert.equal(
    occurrences(source, compactHeaderBodyImport),
    1,
    `${migrationEntry.file} import`
  );
  assert.equal(
    occurrences(source, frameOpening),
    1,
    `${migrationEntry.file} opening`
  );
  assert.equal(
    occurrences(source, frameClosing),
    1,
    `${migrationEntry.file} closing`
  );

  const frameStart = source.indexOf(frameOpening);
  const frameEnd = source.indexOf(frameClosing, frameStart);
  const prefix = source.slice(0, frameStart);
  const frame = source.slice(frameStart, frameEnd + frameClosing.length);
  const suffix = source.slice(frameEnd + frameClosing.length);

  assert.equal(
    occurrences(frame, contentOpening),
    1,
    `${migrationEntry.file} content slot`
  );
  assert.equal(
    occurrences(frame, actionsOpening),
    1,
    `${migrationEntry.file} actions slot`
  );
  assert.equal(
    frame.match(/^ {8}<\/template>$/gm)?.length,
    2,
    `${migrationEntry.file} slot closings`
  );

  const predecessorFrame = frame
    .replace(frameOpening, `      <div class="${compactHeaderBodyFrameClass}">`)
    .replace(contentOpening, "        <div>")
    .replace(/^ {8}<\/template>$/m, "        </div>")
    .replace(
      actionsOpening,
      `        <div class="${compactHeaderBodyActionsClass}">`
    )
    .replace(/^ {8}<\/template>$/m, "        </div>")
    .replace(frameClosing, "      </div>");
  const predecessor = (prefix + predecessorFrame + suffix).replace(
    compactHeaderBodyImport,
    ""
  );

  assert.doesNotMatch(predecessor, /CadenceCompactPageHeaderBodyFrame/);
  return predecessor;
};

export const peelCadenceCompactPageHeaderBodyFrameBeforeOlderLayers = (
  source,
  caller
) => {
  const file = caller.split("/").at(-1);
  if (!compactHeaderBodyCallerNames.includes(file)) return source;
  if (occurrences(source, compactHeaderBodyImport) === 0) return source;
  return peelCadenceCompactPageHeaderBodyFrame(source, caller);
};
