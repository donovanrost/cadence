import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  compactHeaderBodyActionsClass,
  compactHeaderBodyBase,
  compactHeaderBodyCallerNames,
  compactHeaderBodyExclusions,
  compactHeaderBodyFrameClass,
  compactHeaderBodyFramePath,
  compactHeaderBodyImport,
  compactHeaderBodyMigrations,
  peelCadenceCompactPageHeaderBodyFrame,
} from "./compact_page_header_body_frame_test_support.mjs";
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs";

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `compact header-body migration contracts use pinned Node ${expectedNodeVersion}`
);

const testDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(testDirectory, "../../../..");
const vueDirectory = resolve(testDirectory, "../vue");
const componentPath = resolve(repositoryRoot, compactHeaderBodyFramePath);
const sha256 = (source) => createHash("sha256").update(source).digest("hex");
const occurrences = (source, fragment) => source.split(fragment).length - 1;
const git = (args, options = {}) =>
  execFileSync("git", args, {
    cwd: repositoryRoot,
    encoding: "utf8",
    ...options,
  });

assert.equal(
  git(["rev-parse", "--verify", `${compactHeaderBodyBase}^{commit}`]).trim(),
  compactHeaderBodyBase,
  "the frozen predecessor resolves to its exact commit object"
);
assert.doesNotThrow(
  () => git(["merge-base", "--is-ancestor", compactHeaderBodyBase, "HEAD"]),
  "the frozen predecessor is an ancestor of current HEAD"
);
assert.equal(compactHeaderBodyMigrations.length, 10);
assert.equal(compactHeaderBodyExclusions.length, 23);

const predecessorVuePaths = git([
  "ls-tree",
  "-r",
  "--name-only",
  compactHeaderBodyBase,
  "--",
  "apps/cadence_web/assets/vue",
])
  .trim()
  .split("\n")
  .filter((path) => path.endsWith(".vue"))
  .sort();
const successorVuePaths = (await readdir(vueDirectory, { recursive: true }))
  .filter((path) => path.endsWith(".vue"))
  .map((path) => `apps/cadence_web/assets/vue/${path}`)
  .sort();

assert.equal(
  predecessorVuePaths.length,
  225,
  "the exact predecessor owns 225 Vue SFCs"
);
assert.equal(successorVuePaths.length, 226, "the successor owns 226 Vue SFCs");
assert.deepEqual(
  successorVuePaths.filter((path) => !predecessorVuePaths.includes(path)),
  [compactHeaderBodyFramePath],
  "the frame is the sole added Vue path"
);
assert.deepEqual(
  predecessorVuePaths.filter((path) => !successorVuePaths.includes(path)),
  [],
  "the migration removes no predecessor Vue path"
);

const nativeOpening = `<div class="${compactHeaderBodyFrameClass}">`;
const predecessorNativeMatches = git([
  "grep",
  "-n",
  "-F",
  nativeOpening,
  compactHeaderBodyBase,
  "--",
  "apps/cadence_web/assets/vue",
])
  .trim()
  .split("\n")
  .filter(Boolean);
const expectedRepositoryPaths = compactHeaderBodyMigrations
  .map(({ repositoryPath }) => repositoryPath)
  .sort();

assert.equal(
  predecessorNativeMatches.length,
  10,
  "the predecessor has ten native matches"
);
assert.deepEqual(
  predecessorNativeMatches.map((match) => match.split(":")[1]).sort(),
  expectedRepositoryPaths,
  "the predecessor native inventory is exactly the audited cohort"
);

const successorSources = await Promise.all(
  successorVuePaths.map(async (repositoryPath) => ({
    repositoryPath,
    source: await readFile(resolve(repositoryRoot, repositoryPath), "utf8"),
  }))
);
const migratedSources = successorSources.filter(({ source }) =>
  source.includes("<CadenceCompactPageHeaderBodyFrame>")
);

assert.deepEqual(
  migratedSources.map(({ repositoryPath }) => repositoryPath).sort(),
  expectedRepositoryPaths,
  "exactly the ten audited callers use the new frame"
);
assert.equal(
  successorSources.reduce(
    (count, { source }) =>
      count +
      (source.match(/^import CadenceCompactPageHeaderBodyFrame\b/gm)?.length ??
        0),
    0
  ),
  10,
  "the successor has ten exact component imports"
);
assert.equal(
  successorSources.reduce(
    (count, { source }) =>
      count +
      (source.match(/<CadenceCompactPageHeaderBodyFrame>/g)?.length ?? 0),
    0
  ),
  10,
  "the successor has ten component openings"
);
assert.equal(
  successorSources.reduce(
    (count, { source }) =>
      count +
      (source.match(/<\/CadenceCompactPageHeaderBodyFrame>/g)?.length ?? 0),
    0
  ),
  10,
  "the successor has ten component closings"
);
assert.equal(
  successorSources.reduce(
    (count, { source }) => count + occurrences(source, nativeOpening),
    0
  ),
  0,
  "the successor has no residual exact native shell"
);

const predecessorSources = new Map();

for (const migration of compactHeaderBodyMigrations) {
  const predecessor = git([
    "show",
    `${compactHeaderBodyBase}:${migration.repositoryPath}`,
  ]);
  const current = await readFile(
    resolve(repositoryRoot, migration.repositoryPath),
    "utf8"
  );
  const reconstructed = peelCadenceCompactPageHeaderBodyFrame(
    current,
    migration.file
  );

  assert.equal(
    Buffer.byteLength(predecessor),
    migration.byteLength,
    `${migration.file} bytes`
  );
  assert.equal(
    git([
      "rev-parse",
      `${compactHeaderBodyBase}:${migration.repositoryPath}`,
    ]).trim(),
    migration.blobId,
    `${migration.file} blob`
  );
  assert.equal(
    sha256(predecessor),
    migration.sha256,
    `${migration.file} SHA-256`
  );
  assert.equal(
    reconstructed,
    predecessor,
    `${migration.file} reconstructs byte-for-byte first`
  );
  assert.equal(
    sha256(reconstructed),
    migration.sha256,
    `${migration.file} reconstructed SHA-256`
  );
  predecessorSources.set(migration.file, predecessor);
}

for (const exclusion of compactHeaderBodyExclusions) {
  const predecessor = git([
    "show",
    `${compactHeaderBodyBase}:${exclusion.repositoryPath}`,
  ]);
  const current = await readFile(
    resolve(repositoryRoot, exclusion.repositoryPath)
  );
  const currentBlob = git(["hash-object", "--stdin"], {
    input: current,
  }).trim();

  assert.equal(
    current.byteLength,
    exclusion.byteLength,
    `${exclusion.file} excluded bytes`
  );
  assert.equal(
    currentBlob,
    exclusion.blobId,
    `${exclusion.file} excluded blob`
  );
  assert.equal(
    sha256(current),
    exclusion.sha256,
    `${exclusion.file} excluded SHA-256`
  );
  assert.equal(
    current.toString("utf8"),
    predecessor,
    `${exclusion.file} stays byte-identical`
  );
  assert.doesNotMatch(
    current.toString("utf8"),
    /CadenceCompactPageHeaderBodyFrame/
  );
}

const componentSource = await readFile(componentPath, "utf8");
const dom = installDom(
  '<main id="compact-header-body-contract"></main><main id="compact-header-body-callers"></main>'
);

for (const globalName of [
  "File",
  "FileList",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLTextAreaElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  });
}

const { compileScript, parse } = integrationRequire("@vue/compiler-sfc");
const { transformSync } = integrationRequire("esbuild");
const parsedFrame = parse(componentSource, { filename: componentPath });

assert.deepEqual(
  parsedFrame.errors,
  [],
  "the real frame parses with the pinned compiler"
);
assert.ok(
  parsedFrame.descriptor.script,
  "the frame keeps a typed render-function script"
);
assert.equal(parsedFrame.descriptor.script.lang, "ts");
assert.equal(parsedFrame.descriptor.scriptSetup, null);
assert.equal(
  parsedFrame.descriptor.template,
  null,
  "the frame introduces no template anchors"
);

const compiledFrame = compileScript(parsedFrame.descriptor, {
  id: "cadence-compact-page-header-body-frame-contract",
});
const transformedFrame = transformSync(compiledFrame.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
});
const loadedFrame = { exports: {} };

new Function("require", "module", "exports", transformedFrame.code)(
  integrationRequire,
  loadedFrame,
  loadedFrame.exports
);

const CadenceCompactPageHeaderBodyFrame = loadedFrame.exports.default;
const { Fragment, createApp, defineComponent, h, nextTick, reactive, ref } =
  integrationRequire("vue");

assert.equal(CadenceCompactPageHeaderBodyFrame.inheritAttrs, false);
assert.equal(CadenceCompactPageHeaderBodyFrame.props, undefined);
assert.equal(CadenceCompactPageHeaderBodyFrame.emits, undefined);
assert.equal(
  componentSource.match(/h\(\s*"div"/g)?.length,
  3,
  "the frame owns exactly three divs"
);
assert.match(componentSource, /slots\.content\?\.\(\)/);
assert.match(componentSource, /slots\.actions\?\.\(\)/);
assert.match(componentSource, /Array\.isArray\(child\)/);
assert.match(componentSource, /child\.type === Fragment/);
assert.match(componentSource, /cloneVNode\(child/);
assert.match(componentSource, /child\.key \?\? inheritedKey/);
assert.doesNotMatch(
  componentSource,
  /<template|<header|<nav|<a\b|<button|<input|<form|defineProps|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(|\b(?:id|href|disabled|role|aria-[\w-]+)\s*:/,
  "the frame owns no behavior, state, semantic values, props, controls, or events"
);

const contractOrder = ref(["content-a", "content-b"]);
const contractActions = ref(["action-a", "action-b"]);
const contractId = ref("caller-compact-header-body");
const contractClass = ref("caller-compact-header-class");
const contractNodes = new Map();
let forwardedClicks = 0;

const rememberContractNode = (id) => (element) => {
  if (element) contractNodes.set(id, element);
};
const contentNode = (id) =>
  id === "content-a"
    ? h(
        "a",
        { ref: rememberContractNode(id), id, href: "/content-a" },
        "Content A"
      )
    : h("span", { ref: rememberContractNode(id), id }, "Content B");
const contentDetailNode = (id) =>
  h(
    "small",
    {
      ref: rememberContractNode(`${id}-detail`),
      id: `${id}-detail`,
    },
    id === "content-a" ? "Content A detail" : "Content B detail"
  );
const actionNode = (id) =>
  h(
    "button",
    {
      ref: rememberContractNode(id),
      id,
      type: "button",
      disabled: id === "action-b",
    },
    id === "action-a" ? "Action A" : "Action B"
  );

const FrameContract = defineComponent({
  name: "CadenceCompactPageHeaderBodyFrameContract",
  setup() {
    return () =>
      h(
        CadenceCompactPageHeaderBodyFrame,
        {
          id: contractId.value,
          class: contractClass.value,
          "data-owner": "caller",
          "aria-label": "Compact header body",
          onClick: () => {
            forwardedClicks += 1;
          },
        },
        {
          content: () => [
            h(Fragment, { key: "content-outer-fragment" }, [
              [
                h(Fragment, { key: "content-inner-fragment" }, [
                  contractOrder.value.map((id) =>
                    h(Fragment, { key: `content-fragment-${id}` }, [
                      contentNode(id),
                      contentDetailNode(id),
                    ])
                  ),
                ]),
              ],
            ]),
          ],
          actions: () => [
            [
              h(Fragment, { key: "actions-outer-fragment" }, [
                [
                  contractActions.value.map((id) =>
                    h(Fragment, { key: `action-fragment-${id}` }, [
                      actionNode(id),
                    ])
                  ),
                ],
              ]),
            ],
          ],
        }
      );
  },
});

for (const id of contractOrder.value) {
  assert.equal(contentNode(id).key, null);
  assert.equal(contentDetailNode(id).key, null);
}
for (const id of contractActions.value) assert.equal(actionNode(id).key, null);

const contractHost = dom.window.document.querySelector(
  "#compact-header-body-contract"
);
const contractApp = createApp(FrameContract);
contractApp.mount(contractHost);
await flushVue(nextTick);

const contractRoot = contractHost.firstElementChild;
const originalContractNodes = Object.fromEntries(contractNodes);

assert.equal(
  contractHost.childNodes.length,
  1,
  "the frame adds no wrapper or sibling"
);
assert.equal(
  contractRoot.outerHTML,
  `<div id="caller-compact-header-body" class="${compactHeaderBodyFrameClass} caller-compact-header-class" data-owner="caller" aria-label="Compact header body"><div><a id="content-a" href="/content-a">Content A</a><small id="content-a-detail">Content A detail</small><span id="content-b">Content B</span><small id="content-b-detail">Content B detail</small></div><div class="${compactHeaderBodyActionsClass}"><button id="action-a" type="button">Action A</button><button id="action-b" type="button" disabled="">Action B</button></div></div>`
);
assert.deepEqual(elementAttributes(contractRoot), {
  "aria-label": "Compact header body",
  class: `${compactHeaderBodyFrameClass} caller-compact-header-class`,
  "data-owner": "caller",
  id: "caller-compact-header-body",
});
assert.deepEqual(
  [...contractRoot.children].map((element) => element.tagName),
  ["DIV", "DIV"]
);
assert.equal(contractRoot.children[1].className, compactHeaderBodyActionsClass);

contractNodes.get("action-a").click();
assert.equal(forwardedClicks, 1, "caller listeners forward to the outer div");

contractOrder.value = [...contractOrder.value].reverse();
contractActions.value = [...contractActions.value].reverse();
contractId.value = "caller-compact-header-body-updated";
contractClass.value = "caller-updated-class";
await flushVue(nextTick);

assert.strictEqual(contractHost.firstElementChild, contractRoot);
assert.deepEqual(
  [...contractRoot.children[0].children].map(({ id }) => id),
  ["content-b", "content-b-detail", "content-a", "content-a-detail"]
);
assert.deepEqual(
  [...contractRoot.children[1].children].map(({ id }) => id),
  ["action-b", "action-a"]
);
for (const [id, element] of Object.entries(originalContractNodes)) {
  assert.strictEqual(
    contractNodes.get(id),
    element,
    `${id} keeps native identity through its keyed Fragment wrapper`
  );
}
assert.deepEqual(elementAttributes(contractRoot), {
  "aria-label": "Compact header body",
  class: `${compactHeaderBodyFrameClass} caller-updated-class`,
  "data-owner": "caller",
  id: "caller-compact-header-body-updated",
});

const localRequire = createRequire(resolve(repositoryRoot, "package.json"));
const predecessorModuleCache = new Map();

const loadPredecessorModule = (modulePath, sourceOverride) => {
  const cacheKey =
    sourceOverride === undefined ? modulePath : `${modulePath}:predecessor`;
  if (predecessorModuleCache.has(cacheKey)) {
    return predecessorModuleCache.get(cacheKey).exports;
  }

  const loadedModule = { exports: {} };
  predecessorModuleCache.set(cacheKey, loadedModule);
  let moduleSource = sourceOverride ?? readFileSync(modulePath, "utf8");
  let loader = extname(modulePath) === ".ts" ? "ts" : "js";

  if (extname(modulePath) === ".vue") {
    const parsed = parse(moduleSource, { filename: modulePath });
    assert.deepEqual(parsed.errors, [], `${modulePath} predecessor parses`);
    moduleSource = compileScript(parsed.descriptor, {
      id: `compact-header-body-predecessor-${modulePath.split("/").at(-1)}`,
      inlineTemplate: true,
    }).content;
    loader = "ts";
  }

  const transformed = transformSync(moduleSource, {
    format: "cjs",
    loader,
    platform: "node",
    target: "node24",
  });
  const requireFromModule = (specifier) => {
    if (specifier.startsWith(".")) {
      return loadPredecessorModule(resolve(dirname(modulePath), specifier));
    }

    if (specifier === "live_vue") {
      return {
        useLiveUpload: () => ({
          entries: ref([]),
          progress: ref(0),
          addFiles: () => {},
          submit: () => {},
          clear: () => {},
          inputEl: ref(null),
          valid: ref(true),
        }),
      };
    }

    try {
      return integrationRequire(specifier);
    } catch {
      return localRequire(specifier);
    }
  };

  new Function("require", "module", "exports", transformed.code)(
    requireFromModule,
    loadedModule,
    loadedModule.exports
  );
  return loadedModule.exports;
};

const breadcrumbSet = () => [
  { label: "Mission Alpha", href: "/missions/alpha" },
  { label: "Current", href: null },
];
const status = (label = "Ready", tone = "ready") => ({ label, tone });
const detailCard = (id, title) => ({ id, title, rows: [] });
const profileSection = (id) => ({
  id,
  heading: `${id} heading`,
  subtitle: `${id} subtitle`,
  empty: true,
  empty_copy: `No ${id}`,
  table_id: `${id}-table`,
  table_body_id: `${id}-table-body`,
  columns: [],
});
const emptyGrantField = (key) => ({
  key,
  id: `grant-${key}`,
  name: `grant[${key}]`,
  type: key === "mission_id" ? "select" : "text",
  label: key,
  value: "",
  required: false,
  min: null,
  placeholder: null,
  options: [],
});
const grantFieldKeys = [
  "mission_id",
  "allowed_services",
  "allowed_stations",
  "max_quota",
  "grant_reason",
];

const fixtures = Object.freeze([
  Object.freeze({
    file: "AdminRuntime.vue",
    props: {
      summary: {
        decision_count: 3,
        status_summary: "ready",
        refresh_summary: "fresh",
        source_summary: "runtime",
        selected_decision_state: "none",
        empty_state: { id: "runtime-empty", copy: "No decisions" },
        stats: [],
      },
      filters: {
        values: {
          dashboard_id: "",
          mission_id: "",
          boundary: "",
          context_reason: "",
          replay_run_id: "",
          affected_placement_id: "",
        },
        fields: [],
        clear_href: "/admin/runtime",
      },
      decisions: [],
      selection: {
        state: "none",
        decision_key: null,
        missing: false,
        outside_results: false,
        context_href: null,
        detail: null,
      },
      navigation: { admin_href: "/admin" },
    },
  }),
  Object.freeze({
    file: "CatalogDatabaseShow.vue",
    props: {
      database: {
        id: "database-1",
        name: "Flight Catalog",
        slug: "flight-catalog",
        description: "Catalog description",
        runtime_usage_summary: "Not in use",
      },
      navigation: {
        mission: { label: "Mission Alpha", href: "/missions/alpha" },
        catalog: { label: "Catalog", href: "/missions/alpha/catalog" },
        current: { label: "Flight Catalog" },
      },
      revision_form_open: false,
      revision_form: {
        id: "revision-form",
        name: "catalog_revision",
        class: "space-y-4",
        card: {
          id: null,
          class: "",
          body_class: "",
          title: "Upload",
          title_class: "hud-label",
        },
        content_class: null,
        description: null,
        primary_fields_class: "",
        primary_fields: [],
        secondary_fields: [],
        file_input: {
          id: "upload",
          name: "upload",
          class: "",
          wrapper_class: null,
        },
        entries: {
          list_class: "",
          item_class: "",
          name_class: "",
          progress_class: "",
          remove_class: "",
          remove_label: "Remove",
        },
        error_class: "",
        importer: {
          detected_class: "",
          icon_class: "",
          name_class: "",
          empty_class: "",
        },
        actions_class: null,
        submit: { id: null, label: "Upload", class: "" },
      },
      upload: {
        ref: "catalog-upload-ref",
        name: "artifact",
        accept: false,
        max_entries: 1,
        max_file_size: 52_428_800,
        auto_upload: false,
        entries: [],
        errors: [],
      },
      detected_importer: { status: "empty", display_name: null },
      submit_disabled: true,
      revisions: [],
      import_runs: [],
    },
  }),
  Object.freeze({
    file: "CommsGroundStationShow.vue",
    props: {
      navigation: { breadcrumbs: breadcrumbSet() },
      ground_station: {
        display_name: "Goldstone",
        ground_station_id: "ground-1",
        lifecycle_state: "ACTIVE",
        details_title: "Details",
        description: "Ground station description",
        details: [],
        metadata_title: "Metadata",
        metadata_json: "{}",
      },
      actions: {
        edit: { id: "ground-edit", label: "Edit", href: "/ground/edit" },
        archive: {
          id: "ground-archive",
          label: "Archive",
          confirm: "Archive?",
        },
      },
    },
  }),
  Object.freeze({
    file: "CommsProviderShow.vue",
    props: {
      navigation: { breadcrumbs: breadcrumbSet() },
      provider: {
        page_id: "provider-page",
        display_name: "Provider One",
        provider_id: "provider-1",
        simulated_badge: { id: "provider-simulated", label: "Simulated" },
        version: "v1",
        summary_tiles: [],
      },
      actions: {
        validate: {
          id: "provider-validate",
          label: "Validate",
          disabled: true,
        },
        sync: { id: "provider-sync", label: "Sync", disabled: false },
        archive: {
          id: "provider-archive",
          label: "Archive",
          disabled: false,
          confirm: "Archive provider?",
        },
      },
      profiles: {
        service: profileSection("service"),
        delivery: profileSection("delivery"),
      },
      details: {
        configuration: detailCard("provider-config", "Configuration"),
        delivery_policy: detailCard("provider-policy", "Delivery policy"),
        capabilities: {
          id: "provider-capabilities",
          title: "Capabilities",
          empty: true,
          empty_copy: "No capabilities",
          items: [],
        },
        version_history: {
          id: "provider-versions",
          title: "Versions",
          stream_id: "provider-version-stream",
        },
      },
      diagnostics: {
        id: "provider-diagnostics",
        label: "Diagnostics",
        json_id: "provider-json",
        rows: [],
        json: "{}",
      },
      service_profiles: [],
      delivery_profiles: [],
      provider_versions: [],
    },
  }),
  Object.freeze({
    file: "CommsRoutingShow.vue",
    props: {
      navigation: { breadcrumbs: breadcrumbSet() },
      rule: {
        display_name: "Downlink routing",
        routing_rule_id: "rule-1",
        state: status("Enabled"),
        section_title: "Routing rule",
        description: "Routing description",
        details: [],
        runtime_artifacts_title: "Artifacts",
        runtime_artifacts: [],
      },
      events: [],
    },
  }),
  Object.freeze({
    file: "CommsValidation.vue",
    props: {
      validation: {
        id: "validation-page",
        title: "Comms validation",
        subtitle: "Validation subtitle",
        breadcrumbs: breadcrumbSet(),
        finding_count_suffix: "0 findings",
        status: status("Ready"),
        empty: true,
        empty_state: {
          id: "validation-empty",
          title: "No findings",
          description: "Everything is ready",
        },
        findings_id: "validation-findings",
        finding_groups: [],
      },
    },
  }),
  Object.freeze({
    file: "ProviderAccountShow.vue",
    props: {
      page: {
        id: "provider-account-page",
        header: {
          title: "Provider Account",
          subtitle: "Account subtitle",
          config_label: "CONFIGURED",
          breadcrumbs: breadcrumbSet(),
        },
        grants: {
          card_id: "grants-card",
          heading: "Grants",
          subtitle: "Grant subtitle",
          stream_id: "grants-stream",
          empty: { id: "grants-empty", text: "No grants" },
        },
        grant_form_card: {
          id: "grant-form-card",
          heading: "Grant mission",
          subtitle: "Grant form subtitle",
        },
        audit: {
          card_id: "audit-card",
          heading: "Audit",
          subtitle: "Audit subtitle",
          stream_id: "audit-stream",
          empty: { id: "audit-empty", text: "No audit entries" },
        },
      },
      actions: {
        validate: {
          id: "account-validate",
          label: "Validate",
          disabled: true,
          payload: { source: "compact-header" },
          icon: "hero-shield-check",
        },
        rotate: {
          id: "account-rotate",
          label: "Rotate",
          disabled: false,
          payload: { source: "compact-header", operation: "rotate" },
          icon: "hero-arrow-path",
        },
        revoke: {
          id: "account-revoke",
          label: "Revoke",
          disabled: false,
          payload: { source: "compact-header", operation: "revoke" },
          confirm: "Revoke credential?",
        },
      },
      stats: [],
      grant_form: {
        id: "grant-form",
        values: Object.fromEntries(grantFieldKeys.map((key) => [key, ""])),
        fields: Object.fromEntries(
          grantFieldKeys.map((key) => [key, emptyGrantField(key)])
        ),
        action: { id: "grant-submit", label: "Grant" },
      },
      configuration: detailCard("account-config", "Configuration"),
      ingestion: {
        ...detailCard("account-ingestion", "Ingestion"),
        description: "Ingestion description",
      },
      guardrails: { id: "account-guardrails", title: "Guardrails", json: "{}" },
      diagnostics: {
        id: "account-diagnostics",
        title: "Diagnostics",
        columns: [],
      },
      account_grants: [],
      account_audit: [],
    },
  }),
  Object.freeze({
    file: "SpacecraftCommanding.vue",
    props: {
      page: {
        id: "commanding-page",
        title: "Commanding",
        subtitle: "Commanding subtitle",
        eyebrow: "Operations",
        breadcrumbs: breadcrumbSet(),
        status: status("Available", "info"),
      },
      panels: [],
      readiness: {
        eyebrow: "Readiness",
        title: "Ready to command",
        description: "Readiness description",
        status: status("Available", "info"),
      },
    },
  }),
  Object.freeze({
    file: "SpacecraftReadiness.vue",
    props: {
      page: {
        id: "readiness-page",
        title: "Readiness",
        title_suffix: "4/4",
        subtitle: "Readiness subtitle",
        breadcrumbs: breadcrumbSet(),
        status: status("Ready"),
      },
      panels: [],
      applications: [],
    },
  }),
  Object.freeze({
    file: "SpacecraftRouting.vue",
    props: {
      page: {
        title: "Routing",
        subtitle: "Routing subtitle",
        breadcrumbs: breadcrumbSet(),
        new_rule: { id: "new-rule", label: "New rule", href: "/routing/new" },
        empty_state: {
          title: "No rules",
          description: "Create a routing rule",
        },
        rules_id: "routing-rules",
        rows: [],
      },
    },
  }),
]);

assert.deepEqual(
  fixtures.map(({ file }) => file).sort(),
  [...compactHeaderBodyCallerNames].sort()
);

const mountedCallers = new Map();
const emittedEvents = { refresh: [], validateAccount: [] };
const callerHost = dom.window.document.querySelector(
  "#compact-header-body-callers"
);

const mountHarness = async (component, props, listeners, id) => {
  let state;
  const Harness = defineComponent({
    name: `CompactHeaderBodyHarness${id.replaceAll(/[^A-Za-z0-9]/g, "")}`,
    setup() {
      state = reactive(structuredClone(props));
      return () => h(component, { ...state, ...listeners });
    },
  });
  const host = dom.window.document.createElement("section");
  host.id = id;
  callerHost.append(host);
  const app = createApp(Harness);
  app.mount(host);
  await flushVue(nextTick);
  return { app, host, state };
};

for (const fixture of fixtures) {
  const callerPath = resolve(vueDirectory, fixture.file);
  const component = loadPredecessorModule(callerPath).default;
  const predecessorComponent = loadPredecessorModule(
    callerPath,
    predecessorSources.get(fixture.file)
  ).default;
  const listeners =
    fixture.file === "AdminRuntime.vue"
      ? { onRefresh: (...payload) => emittedEvents.refresh.push(payload) }
      : fixture.file === "ProviderAccountShow.vue"
      ? {
          onValidateAccount: (payload) =>
            emittedEvents.validateAccount.push(payload),
        }
      : {};
  const successorMount = await mountHarness(
    component,
    fixture.props,
    listeners,
    `successor-${fixture.file}`
  );
  const predecessorMount = await mountHarness(
    predecessorComponent,
    fixture.props,
    listeners,
    `predecessor-${fixture.file}`
  );
  const successorHeader = successorMount.host.querySelector("header");
  const predecessorHeader = predecessorMount.host.querySelector("header");
  const successorBody = successorHeader?.firstElementChild;
  const predecessorBody = predecessorHeader?.firstElementChild;

  assert.ok(successorBody, `${fixture.file} mounts its migrated header body`);
  assert.ok(
    predecessorBody,
    `${fixture.file} mounts its reconstructed native header body`
  );
  assert.equal(
    successorBody.outerHTML,
    predecessorBody.outerHTML,
    `${fixture.file} exact mounted HTML matches its reconstructed native predecessor`
  );
  assert.deepEqual(elementAttributes(successorBody), {
    class: compactHeaderBodyFrameClass,
  });
  assert.equal(successorBody.children.length, 2);
  assert.equal(successorBody.children[0].tagName, "DIV");
  assert.deepEqual(elementAttributes(successorBody.children[0]), {});
  assert.deepEqual(elementAttributes(successorBody.children[1]), {
    class: compactHeaderBodyActionsClass,
  });

  predecessorMount.app.unmount();
  predecessorMount.host.remove();
  mountedCallers.set(fixture.file, {
    ...successorMount,
    header: successorHeader,
    body: successorBody,
  });
}

const admin = mountedCallers.get("AdminRuntime.vue");
const adminNodes = {
  breadcrumb: admin.header.querySelector("nav"),
  link: admin.header.querySelector("nav a"),
  title: admin.header.querySelector("h1"),
  value: admin.header.querySelector("h1 > span"),
  subtitle: admin.header.querySelector("h1 + p"),
  button: admin.header.querySelector("#admin-runtime-refresh"),
};
adminNodes.button.click();
assert.deepEqual(
  emittedEvents.refresh,
  [[]],
  "the refresh event retains its empty payload"
);
admin.state.summary.decision_count = 8;
admin.state.navigation.admin_href = "/admin/updated";
await flushVue(nextTick);
for (const [name, element] of Object.entries(adminNodes)) {
  assert.strictEqual(
    admin.header.querySelector(
      name === "breadcrumb"
        ? "nav"
        : name === "link"
        ? "nav a"
        : name === "title"
        ? "h1"
        : name === "value"
        ? "h1 > span"
        : name === "subtitle"
        ? "h1 + p"
        : "#admin-runtime-refresh"
    ),
    element,
    `AdminRuntime ${name} retains native identity`
  );
}
assert.match(adminNodes.value.textContent, /8 decisions/);
assert.equal(adminNodes.link.getAttribute("href"), "/admin/updated");

const ground = mountedCallers.get("CommsGroundStationShow.vue");
const groundNodes = {
  breadcrumb: ground.header.querySelector("nav"),
  link: ground.header.querySelector("nav a"),
  title: ground.header.querySelector("h1"),
  value: ground.header.querySelector("h1 > span"),
  subtitle: ground.header.querySelector("h1 + p"),
  edit: ground.header.querySelector("#ground-edit"),
  archive: ground.header.querySelector("#ground-archive"),
};
ground.state.navigation.breadcrumbs[0].href = "/missions/updated";
ground.state.ground_station.display_name = "Goldstone Updated";
ground.state.ground_station.lifecycle_state = "MAINTENANCE";
ground.state.ground_station.ground_station_id = "ground-updated";
ground.state.actions.edit.href = "/ground/updated";
ground.state.actions.edit.label = "Edit updated";
await flushVue(nextTick);
for (const [name, element] of Object.entries(groundNodes)) {
  const selector =
    name === "breadcrumb"
      ? "nav"
      : name === "link"
      ? "nav a"
      : name === "title"
      ? "h1"
      : name === "value"
      ? "h1 > span"
      : name === "subtitle"
      ? "h1 + p"
      : name === "edit"
      ? "#ground-edit"
      : "#ground-archive";
  assert.strictEqual(
    ground.header.querySelector(selector),
    element,
    `${name} retains identity`
  );
}
assert.equal(groundNodes.link.getAttribute("href"), "/missions/updated");
assert.equal(groundNodes.edit.getAttribute("href"), "/ground/updated");
assert.equal(groundNodes.archive.getAttribute("data-confirm"), "Archive?");

const routing = mountedCallers.get("CommsRoutingShow.vue");
const routingStatus = routing.body.children[1].firstElementChild;
routing.state.rule.state.label = "Blocked";
routing.state.rule.state.tone = "blocked";
await flushVue(nextTick);
assert.strictEqual(routing.body.children[1].firstElementChild, routingStatus);
assert.equal(routingStatus.textContent.trim(), "Blocked");
assert.match(routingStatus.className, /bg-error\/20/);

const account = mountedCallers.get("ProviderAccountShow.vue");
const accountNodes = {
  breadcrumb: account.header.querySelector("nav"),
  title: account.header.querySelector("h1"),
  value: account.header.querySelector("h1 > span"),
  subtitle: account.header.querySelector("h1 + p"),
  validate: account.header.querySelector("#account-validate"),
  rotate: account.header.querySelector("#account-rotate"),
  revoke: account.header.querySelector("#account-revoke"),
};
assert.equal(accountNodes.validate.disabled, true);
assert.equal(accountNodes.validate.hasAttribute("disabled"), true);
assert.equal(
  accountNodes.revoke.getAttribute("data-confirm"),
  "Revoke credential?"
);

account.state.actions.validate.disabled = false;
account.state.page.header.title = "Provider Account Updated";
account.state.page.header.subtitle = "Updated account subtitle";
await flushVue(nextTick);
assert.strictEqual(
  account.header.querySelector("#account-validate"),
  accountNodes.validate
);
assert.strictEqual(
  account.header.querySelector("#account-rotate"),
  accountNodes.rotate
);
assert.strictEqual(
  account.header.querySelector("#account-revoke"),
  accountNodes.revoke
);
assert.strictEqual(
  account.header.querySelector("nav"),
  accountNodes.breadcrumb
);
assert.strictEqual(account.header.querySelector("h1"), accountNodes.title);
assert.strictEqual(
  account.header.querySelector("h1 > span"),
  accountNodes.value
);
assert.strictEqual(
  account.header.querySelector("h1 + p"),
  accountNodes.subtitle
);
assert.equal(accountNodes.validate.disabled, false);
assert.equal(accountNodes.validate.hasAttribute("disabled"), false);

accountNodes.validate.click();
assert.deepEqual(emittedEvents.validateAccount, [{ source: "compact-header" }]);

account.state.actions.revoke = null;
await flushVue(nextTick);
assert.equal(
  account.header.querySelector("#account-revoke"),
  null,
  "the conditional action unmounts"
);
assert.strictEqual(
  account.header.querySelector("#account-validate"),
  accountNodes.validate
);
assert.strictEqual(
  account.header.querySelector("#account-rotate"),
  accountNodes.rotate
);

for (const { app, host } of mountedCallers.values()) {
  app.unmount();
  host.remove();
}
contractApp.unmount();
dom.window.close();

console.log(
  "compact_page_header_body_frame_migration_test passed (10 callers + 23 exclusions + 225-to-226 SFC inventory)"
);
