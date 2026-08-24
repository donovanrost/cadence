import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const vuePath = resolve(__dirname, "../vue/RuntimeDiagnosticsPanel.vue")
const componentPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/runtime_diagnostics_panel_components.ex",
)
const cacheComponentPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/runtime_cache_summary_components.ex",
)
const degradedComponentPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/runtime_degraded_source_components.ex",
)
const noRefreshComponentPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/runtime_no_refresh_summary_components.ex",
)
const recentInvalidationsComponentPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/runtime_recent_invalidations_components.ex",
)
const cacheVuePath = resolve(__dirname, "../vue/RuntimeCacheSummary.vue")
const degradedVuePath = resolve(__dirname, "../vue/RuntimeDegradedSource.vue")
const noRefreshVuePath = resolve(__dirname, "../vue/RuntimeNoRefreshSummary.vue")
const recentInvalidationsVuePath = resolve(__dirname, "../vue/RuntimeRecentInvalidations.vue")
const formComponentsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/form_components.ex",
)
const viewportSmokePath = resolve(__dirname, "./dashboard_viewport_smoke.mjs")

const [
  vueSource,
  componentSource,
  cacheComponentSource,
  degradedComponentSource,
  noRefreshComponentSource,
  recentInvalidationsComponentSource,
  cacheVueSource,
  degradedVueSource,
  noRefreshVueSource,
  recentInvalidationsVueSource,
  formComponentsSource,
  viewportSmokeSource,
] = await Promise.all([
  readFile(vuePath, "utf8"),
  readFile(componentPath, "utf8"),
  readFile(cacheComponentPath, "utf8"),
  readFile(degradedComponentPath, "utf8"),
  readFile(noRefreshComponentPath, "utf8"),
  readFile(recentInvalidationsComponentPath, "utf8"),
  readFile(cacheVuePath, "utf8"),
  readFile(degradedVuePath, "utf8"),
  readFile(noRefreshVuePath, "utf8"),
  readFile(recentInvalidationsVuePath, "utf8"),
  readFile(formComponentsPath, "utf8"),
  readFile(viewportSmokePath, "utf8"),
])

const scenarioLedger = [
  [
    "runtime_diagnostics_panel_components_test.exs",
    "diagnostics_panel renders runtime attributes and row sections",
  ],
  [
    "runtime_diagnostics_panel_components_test.exs",
    "diagnostics sections expose exact non-SSR LiveVue host and presentation contracts",
  ],
  [
    "runtime_diagnostics_panel_components_test.exs",
    "diagnostics section DTO preserves scalar HEEx body semantics and remains JSON-total",
  ],
  [
    "runtime_diagnostics_panel_detail_components_test.exs",
    "diagnostics_panel composes runtime detail sections",
  ],
  ["runtime_cache_summary_components_test.exs", "cache_summary renders visible cache fields"],
  ["runtime_cache_summary_components_test.exs", "cache_summary renders cache evidence drilldowns"],
  [
    "runtime_cache_summary_components_test.exs",
    "cache_summary preserves raw attribute and body value semantics",
  ],
  ["runtime_cache_summary_components_test.exs", "cache_summary renders nothing when hidden"],
  [
    "runtime_degraded_source_components_test.exs",
    "degraded_source_summary renders visible degraded source fields",
  ],
  [
    "runtime_degraded_source_components_test.exs",
    "degraded_source_summary renders nothing when hidden",
  ],
  [
    "runtime_degraded_source_components_test.exs",
    "degraded_source_drilldowns renders open evidence controls",
  ],
  [
    "runtime_degraded_source_components_test.exs",
    "degraded_source_drilldowns renders nothing without drilldowns",
  ],
  [
    "runtime_degraded_source_components_test.exs",
    "source_dependency_causes renders operator cause rows with upstream evidence controls",
  ],
  [
    "runtime_degraded_source_components_test.exs",
    "source_dependency_causes renders nothing without dependency evidence",
  ],
  [
    "runtime_degraded_source_capability_components_test.exs",
    "source_capability_postures renders operator evidence controls",
  ],
  [
    "runtime_degraded_source_capability_components_test.exs",
    "source_capability_postures renders nothing without posture evidence",
  ],
  [
    "runtime_no_refresh_summary_components_test.exs",
    "no_refresh_summary renders visible context and refresh fields",
  ],
  [
    "runtime_no_refresh_summary_components_test.exs",
    "no_refresh_summary renders blocker details with fallback display values",
  ],
  [
    "runtime_no_refresh_summary_components_test.exs",
    "no_refresh_summary renders nothing when hidden",
  ],
  [
    "runtime_recent_invalidations_components_test.exs",
    "recent_invalidations renders invalidation attributes and field rows",
  ],
  [
    "runtime_recent_invalidations_components_test.exs",
    "recent_invalidations renders empty state",
  ],
]

assert.equal(scenarioLedger.length, 21, "the diagnostics scenario ledger must remain one-for-one")

const assertionMinimums = new Map([
  ["runtime_diagnostics_panel_components_test.exs", 30],
  ["runtime_diagnostics_panel_detail_components_test.exs", 18],
  ["runtime_cache_summary_components_test.exs", 59],
  ["runtime_degraded_source_components_test.exs", 69],
  ["runtime_degraded_source_capability_components_test.exs", 39],
  ["runtime_no_refresh_summary_components_test.exs", 62],
  ["runtime_recent_invalidations_components_test.exs", 68],
])

for (const [file, minimum] of assertionMinimums) {
  const source = await readFile(
    resolve(__dirname, `../../test/cadence_web/live/ops_dashboard_show_live/${file}`),
    "utf8",
  )

  for (const [, scenario] of scenarioLedger.filter(([ledgerFile]) => ledgerFile === file)) {
    assert.equal(
      source.split(`test "${scenario}"`).length - 1,
      1,
      `ledger scenario must remain named exactly once: ${scenario}`,
    )
  }

  const assertionCount = source.match(/^\s*(?:assert|refute)\b/gm)?.length ?? 0
  assert.ok(assertionCount >= minimum, `${file} must retain at least ${minimum} assertion sites`)
}

assert.equal(
  componentSource.match(/<\.vue\b/g)?.length,
  1,
  "the complete diagnostics parent region must emit one LiveVue host",
)
assert.match(componentSource, /v-component="RuntimeDiagnosticsPanel"/)
assert.match(componentSource, /v-ssr=\{false\}/)
assert.match(componentSource, /Map\.put\("id", "dashboard-diagnostics-panel"\)/)
assert.match(componentSource, /Map\.put\("class", "space-y-5"\)/)
assert.match(componentSource, /def presentation\(assigns\)/)

const rootDataAttributes = [
  "data-runtime-invalidation-events",
  "data-runtime-invalidation-artifacts",
  "data-runtime-invalidation-boundaries",
  "data-runtime-invalidation-context-matches",
  "data-runtime-invalidation-context-filtered",
  "data-runtime-invalidation-context-filter-reasons",
  "data-runtime-invalidation-refresh-allowed",
  "data-runtime-invalidation-refresh-suppressed",
  "data-runtime-invalidation-refresh-suppress-reasons",
  "data-runtime-refresh-status",
  "data-runtime-refresh-reason",
  "data-runtime-active-refresh-mode",
  "data-runtime-active-refresh-started-at",
  "data-runtime-visible-refresh-action",
  "data-runtime-last-refresh-started-at",
  "data-runtime-last-refresh-finished-at",
  "data-runtime-last-refresh-duration-ms",
  "data-runtime-refresh-starts",
  "data-runtime-refresh-cancellations",
  "data-runtime-refresh-coalesced",
  "data-runtime-refresh-noops",
  "data-runtime-refresh-failures",
  "data-runtime-refresh-ignored",
  "data-runtime-refresh-ignored-resolve-ids",
  "data-runtime-canceled-resolves",
  "data-runtime-failed-resolves",
  "data-runtime-source-execution-degraded-identities",
  "data-runtime-source-execution-degraded-actions",
  "data-runtime-source-capability-statuses",
  "data-runtime-source-capability-postures",
  "data-runtime-source-dependency-evidence",
  "data-runtime-source-dependency-degraded-count",
]

assert.equal(rootDataAttributes.length, 32, "every original diagnostics root attribute must stay frozen")
for (const attribute of rootDataAttributes) {
  assert.equal(
    componentSource.match(new RegExp(`${attribute}(?:"|=)`, "g"))?.length,
    3,
    `${attribute} must remain both server-derived and attached to the host`,
  )
}

const directChildren = [
  ["RuntimeCacheSummary", "RuntimeCacheSummary.vue"],
  ["RuntimeDegradedSource", "RuntimeDegradedSource.vue"],
  ["RuntimeDiagnosticsSection", "RuntimeDiagnosticsSection.vue"],
  ["RuntimeNoRefreshSummary", "RuntimeNoRefreshSummary.vue"],
  ["RuntimeRecentInvalidations", "RuntimeRecentInvalidations.vue"],
]

for (const [component, file] of directChildren) {
  assert.match(vueSource, new RegExp(`import ${component} from "\\./${file}"`))
}
assert.doesNotMatch(vueSource, /v-component|<\.vue/)

assert.equal(
  vueSource.match(/<RuntimeDiagnosticsSection\b/g)?.length,
  3,
  "Engine, Runtime, and Invalidation must use the existing section presenter",
)
assert.equal(
  vueSource.match(/<RuntimeDegradedSource\b/g)?.length,
  4,
  "all four degraded-source presentations must compose the existing SFC",
)
assert.equal(vueSource.match(/<RuntimeCacheSummary\b/g)?.length, 1)
assert.equal(vueSource.match(/<RuntimeNoRefreshSummary\b/g)?.length, 1)
assert.equal(vueSource.match(/<RuntimeRecentInvalidations\b/g)?.length, 1)

const orderedBindings = [
  "presentation.engine_section.root.attrs",
  "presentation.cache_summary.root.attrs",
  "presentation.runtime_section.root.attrs",
  "presentation.degraded_source_summary.root.attrs",
  "presentation.degraded_source_drilldowns.root.attrs",
  "presentation.source_capability_postures.root.attrs",
  "presentation.source_dependency_causes.root.attrs",
  "presentation.no_refresh_summary.root.attrs",
  "presentation.invalidation_section.root.attrs",
  "presentation.recent_invalidations.root.attrs",
]
let previousIndex = -1
for (const binding of orderedBindings) {
  const index = vueSource.indexOf(binding, previousIndex + 1)
  assert.ok(index > previousIndex, `${binding} must preserve diagnostics child ordering`)
  previousIndex = index
}

const childHostIds = [
  "dashboard-diagnostics-engine-section-component",
  "dashboard-cache-summary-component",
  "dashboard-diagnostics-runtime-section-component",
  "dashboard-source-execution-degraded-summary-component",
  "dashboard-degraded-source-drilldowns-component",
  "dashboard-source-capability-postures-component",
  "dashboard-source-dependency-causes-component",
  "dashboard-no-refresh-summary-component",
  "dashboard-diagnostics-invalidation-section-component",
  "dashboard-recent-invalidations-component",
]
for (const id of childHostIds) assert.match(componentSource, new RegExp(`"${id}"`))

assert.match(cacheComponentSource, /def cache_summary_presentation\(summary\)/)
assert.match(
  degradedComponentSource,
  /def degraded_source_summary_presentation\(summary\)/,
)
assert.match(
  degradedComponentSource,
  /def degraded_source_drilldowns_presentation\(drilldowns\)/,
)
assert.match(
  degradedComponentSource,
  /def source_capability_postures_presentation\(postures\)/,
)
assert.match(
  degradedComponentSource,
  /def source_dependency_causes_presentation\(dependencies\)/,
)
assert.match(noRefreshComponentSource, /def no_refresh_summary_presentation\(summary\)/)
assert.match(
  recentInvalidationsComponentSource,
  /def recent_invalidations_presentation\(invalidations, lifecycle_events, current_path\)/,
)

assert.match(cacheComponentSource, /"phx-click" => "open_evidence"/)
assert.match(cacheVueSource, /v-bind="item\.button\.attributes"/)
assert.match(degradedComponentSource, /"phx-click" => "open_evidence"/)
assert.match(degradedVueSource, /v-bind="item\.render_attrs"/)
assert.match(noRefreshComponentSource, /"data-phx-link" => "redirect"/)
assert.match(noRefreshComponentSource, /"data-phx-link-state" => "push"/)
assert.match(noRefreshVueSource, /:href="summary\.admin_action\.href"/)
assert.match(noRefreshVueSource, /v-bind="summary\.admin_action\.attributes"/)
assert.match(
  recentInvalidationsComponentSource,
  /ActivityNavigation\.link\(current_path, :version_changes, lifecycle_event\)/,
)
assert.match(
  recentInvalidationsComponentSource,
  /RuntimeAdminDecisionLink\.from_runtime_invalidation\(event\)/,
)
assert.match(
  recentInvalidationsComponentSource,
  /"data-runtime-invalidation-activity-event-id"/,
)
assert.match(recentInvalidationsComponentSource, /"data-runtime-invalidation-activity-link"/)
assert.match(
  recentInvalidationsComponentSource,
  /"data-runtime-invalidation-admin-decision-link"/,
)
assert.match(recentInvalidationsComponentSource, /"data-phx-link" => "redirect"/)
assert.match(recentInvalidationsComponentSource, /"data-phx-link-state" => "push"/)
assert.match(recentInvalidationsVueSource, /:href="action\.href"/)
assert.match(recentInvalidationsVueSource, /v-bind="action\.data_attrs"/)

assert.equal(
  formComponentsSource.match(/<RuntimeDiagnosticsPanelComponents\.diagnostics_panel\b/g)?.length,
  1,
  "FormComponents must retain the sole diagnostics caller",
)
assert.match(formComponentsSource, /:if=\{@panel == :diagnostics\}/)
assert.match(formComponentsSource, /dashboard_lifecycle_events=\{@dashboard_lifecycle_events\}/)
assert.match(formComponentsSource, /dashboard_current_path=\{@dashboard_current_path\}/)

assert.equal(
  viewportSmokeSource.split("#dashboard-diagnostics-panel").length - 1,
  8,
  "every existing browser diagnostics-panel oracle must remain",
)
assert.match(
  viewportSmokeSource,
  /#dashboard-source-dependency-causes \[data-source-dependency-cause\]/,
)
assert.match(
  viewportSmokeSource,
  /#dashboard-source-capability-postures \[data-source-capability-posture\]/,
)
assert.match(viewportSmokeSource, /dataset\.runtimeRefreshStatus/)
assert.match(viewportSmokeSource, /dataset\.runtimeSourceExecutionDegradedActions/)
