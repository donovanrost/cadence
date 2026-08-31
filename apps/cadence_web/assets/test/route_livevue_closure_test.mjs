import assert from "node:assert/strict"
import {access, readdir, readFile} from "node:fs/promises"
import {dirname, extname, join, relative, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "closure contract uses pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const webRoot = resolve(testDirectory, "../..")
const routerPath = resolve(webRoot, "lib/cadence_web/router.ex")
const liveRoot = resolve(webRoot, "lib/cadence_web/live")
const controllerRoot = resolve(webRoot, "lib/cadence_web/controllers")
const runtimeTemplateRoot = resolve(webRoot, "lib/cadence_web")
const federatedTemplatePath = resolve(
  runtimeTemplateRoot,
  "controllers/application_host_html/federated.html.heex",
)
const federatedHtmlModulePath = resolve(controllerRoot, "application_host_html.ex")
const federatedControllerPath = resolve(controllerRoot, "application_host_controller.ex")
const vueRoot = resolve(webRoot, "assets/vue")
const vueIndexPath = resolve(vueRoot, "index.ts")
const appPath = resolve(webRoot, "assets/js/app.js")

const expectedLiveRoutes = `
auth|/sign-in|UserSessionLive|new
organization|/|OrganizationHomeLive|show
organization|/missions|MissionListLive|index
organization|/missions/new|MissionNewLive|new
organization|/livevue-poc|LiveVuePocLive|index
provider_accounts|/provider-accounts|ProviderAccountListLive|index
provider_accounts|/provider-accounts/new|ProviderAccountNewLive|new
provider_accounts|/provider-accounts/:provider_account_id|ProviderAccountShowLive|show
mission|/missions/:mission_id|MissionShowLive|show
mission|/missions/:mission_id/applications|MissionApplicationsLive|index
mission|/missions/:mission_id/applications/:application_key|ApplicationHostLive|show
mission|/missions/:mission_id/applications/:application_key/:surface_id|ApplicationHostLive|show
spacecraft|/missions/:mission_id/spacecraft|SpacecraftListLive|index
spacecraft|/missions/:mission_id/spacecraft/new|SpacecraftNewLive|new
spacecraft|/missions/:mission_id/spacecraft/profiles|SpacecraftTypeListLive|index
spacecraft|/missions/:mission_id/spacecraft/profiles/new|SpacecraftTypeNewLive|new
spacecraft|/missions/:mission_id/spacecraft/profiles/:profile_id|SpacecraftTypeShowLive|show
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id|SpacecraftShowLive|show
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/identity|SpacecraftEditLive|identity
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/edit|SpacecraftEditLive|edit
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/readiness|SpacecraftReadinessLive|show
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/routing|SpacecraftRoutingLive|show
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/applications|SpacecraftApplicationsLive|index
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key|ApplicationHostLive|show
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id|ApplicationHostLive|show
spacecraft_show|/missions/:mission_id/spacecraft/:spacecraft_id/commanding|SpacecraftCommandingLive|show
catalog|/missions/:mission_id/catalog|CatalogIndexLive|index
catalog|/missions/:mission_id/catalog/new|CatalogDatabaseNewLive|new
catalog|/missions/:mission_id/catalog/databases/:catalog_database_id|CatalogDatabaseShowLive|show
catalog|/missions/:mission_id/catalog/revisions/:catalog_revision_id|CatalogRevisionShowLive|show
catalog|/missions/:mission_id/catalog/artifacts/:artifact_id|CatalogArtifactShowLive|show
catalog|/missions/:mission_id/catalog/imports/:import_run_id|CatalogImportRunShowLive|show
comms|/missions/:mission_id/comms|CommsOverviewLive|index
comms|/missions/:mission_id/comms/transports|CommsTransportListLive|index
comms|/missions/:mission_id/comms/transports/new|CommsTransportNewLive|new
comms|/missions/:mission_id/comms/transports/:transport_id|CommsTransportShowLive|show
comms|/missions/:mission_id/comms/ground-stations|CommsGroundStationListLive|index
comms|/missions/:mission_id/comms/ground-stations/new|CommsGroundStationFormLive|new
comms|/missions/:mission_id/comms/ground-stations/:ground_station_id/edit|CommsGroundStationFormLive|edit
comms|/missions/:mission_id/comms/ground-stations/:ground_station_id|CommsGroundStationShowLive|show
comms|/missions/:mission_id/comms/routing|CommsRoutingListLive|index
comms|/missions/:mission_id/comms/routing/new|CommsRoutingNewLive|new
comms|/missions/:mission_id/comms/routing/:routing_rule_id|CommsRoutingShowLive|show
comms|/missions/:mission_id/comms/validation|CommsValidationLive|index
comms|/missions/:mission_id/comms/providers|CommsProviderListLive|index
comms|/missions/:mission_id/comms/providers/new|CommsProviderNewLive|new
comms|/missions/:mission_id/comms/providers/:provider_id|CommsProviderShowLive|show
ops_dashboard_author|/missions/:mission_id/ops/dashboards/new|OpsDashboardNewLive|new
ops_dashboard_author|/missions/:mission_id/ops/dashboards/library|OpsDashboardLibraryLive|index
ops_dashboard_author|/missions/:mission_id/ops/dashboards/playlists|OpsDashboardPlaylistsLive|index
ops_dashboard_author|/missions/:mission_id/ops/dashboards/:dashboard_id/edit|OpsDashboardEditorLive|edit
ops_dashboard_author|/missions/:mission_id/ops/dashboards/:dashboard_id/settings|OpsDashboardSettingsLive|show
ops|/missions/:mission_id/ops/dashboards|OpsDashboardListLive|index
ops|/missions/:mission_id/ops/dashboard-shares/:share_id|OpsDashboardShareLive|show
ops|/missions/:mission_id/ops/dashboard-snapshots/:snapshot_id|OpsDashboardSnapshotLive|show
ops|/missions/:mission_id/ops/dashboards/playlists/:playlist_id/present|OpsDashboardPlaylistPresentLive|show
ops|/missions/:mission_id/ops/data-sources|OpsDataSourcesLive|index
ops|/missions/:mission_id/ops/data-sources/:data_source_id|OpsDataSourcesLive|show
ops|/missions/:mission_id/ops/data-operations|OpsDataOperationsLive|index
ops|/missions/:mission_id/ops/planning|OpsFleetPlanningLive|index
ops|/missions/:mission_id/ops/planning/new|OpsFleetPlanningNewLive|new
ops|/missions/:mission_id/ops/planning/policy|OpsFleetPlanningPolicyLive|show
ops|/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id|OpsFleetPlanningRunLive|show
ops|/missions/:mission_id/ops/requirement-templates|OpsContactRequirementTemplateLive|index
ops|/missions/:mission_id/ops/requirements|OpsContactRequirementListLive|index
ops|/missions/:mission_id/ops/requirements/new|OpsContactRequirementNewLive|new
ops|/missions/:mission_id/ops/requirements/:contact_requirement_id|OpsContactRequirementShowLive|show
ops|/missions/:mission_id/ops/plans/:contact_plan_id|OpsContactPlanShowLive|show
ops|/missions/:mission_id/ops/contacts|OpsContactScheduleLive|index
ops|/missions/:mission_id/ops/contacts/records/:contact_id|OpsContactRecordLive|show
ops|/missions/:mission_id/ops/contacts/:provider_reservation_id|OpsContactDetailLive|show
ops|/missions/:mission_id/ops/alarms|OpsAlarmsLive|index
ops|/missions/:mission_id/ops/timeline|OpsTimelineLive|index
ops|/missions/:mission_id/ops/commands|OpsCommandsLive|index
ops|/missions/:mission_id/ops/explore|OpsTelemetryExploreLive|show
ops|/missions/:mission_id/ops/dashboards/:dashboard_id/activity|OpsDashboardActivityLive|show
ops|/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics|OpsDashboardDiagnosticsLive|show
ops|/missions/:mission_id/ops/dashboards/:dashboard_id|OpsDashboardViewerLive|show
ops_admin|/missions/:mission_id/ops/activations|OpsActivationRequestsLive|index
ops_admin|/missions/:mission_id/ops/data-sources/registration/new|OpsDataSourcesLive|new
ops_admin|/missions/:mission_id/ops/data-sources/:data_source_id/settings|OpsDataSourcesLive|settings
ops_admin|/missions/:mission_id/ops/data-operations/manage|OpsDataOperationsLive|manage
user|/notifications|NotificationsLive|index
admin|/admin|AdminHomeLive|index
admin|/admin/runtime|AdminRuntimeLive|index
admin|/admin/organizations|AdminOrganizationListLive|index
admin|/admin/organizations/new|AdminOrganizationNewLive|new
admin|/admin/organizations/:org_id|AdminOrganizationShowLive|show
admin|/admin/organizations/:org_id/invite|AdminOrganizationInviteLive|invite
`.trim().split("\n")

const expectedBrowserGets = `
public_page|/invitations/:invitation_token|OrganizationInvitationController|show
authenticated_page|/admin-mode|AdminModeController|new
authenticated_page|/no-organization|NoOrganizationController|show
download|/missions/:mission_id/catalog/artifacts/:artifact_id/download|CatalogArtifactDownloadController|show
authenticated_page|/missions/:mission_id/applications/:application_key/federated|ApplicationHostController|federated
authenticated_page|/missions/:mission_id/applications/:application_key/:surface_id/federated|ApplicationHostController|federated
authenticated_page|/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/federated|ApplicationHostController|federated
authenticated_page|/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id/federated|ApplicationHostController|federated
redirect|/missions/:mission_id/ops/telemetry/explore|LegacyOpsRedirectController|telemetry_explore
download|/missions/:mission_id/ops/dashboards/:dashboard_id/export|DashboardExportController|show
redirect|/missions/:mission_id/spacecraft/:spacecraft_id/telemetry|LegacyApplicationRedirectController|telemetry_decom
redirect|/missions/:mission_id/spacecraft/:spacecraft_id/telemetry_decom|LegacyApplicationRedirectController|telemetry_decom
redirect|/missions/:mission_id/comms/links|LegacyCommsRedirectController|link_templates_index
redirect|/missions/:mission_id/comms/links/new|LegacyCommsRedirectController|shared_link_new
redirect|/missions/:mission_id/comms/path-templates|LegacyCommsRedirectController|link_templates_index
redirect|/missions/:mission_id/comms/path-templates/new|LegacyCommsRedirectController|link_templates_new
redirect|/missions/:mission_id/comms/path-templates/:path_template_id|LegacyCommsRedirectController|link_templates_show
redirect|/missions/:mission_id/comms/path-templates/:path_template_id/new-version|LegacyCommsRedirectController|link_templates_new_version
redirect|/missions/:mission_id/comms/transport-profiles|LegacyCommsRedirectController|protocol_behaviors_index
redirect|/missions/:mission_id/comms/transport-profiles/new|LegacyCommsRedirectController|protocol_behaviors_new
redirect|/missions/:mission_id/comms/transport-profiles/:transport_profile_id|LegacyCommsRedirectController|protocol_behaviors_show
redirect|/missions/:mission_id/comms/transport-profiles/:transport_profile_id/new-version|LegacyCommsRedirectController|protocol_behaviors_new_version
redirect|/missions/:mission_id/comms/provider-profiles|LegacyCommsRedirectController|providers_index
redirect|/missions/:mission_id/comms/provider-profiles/new|LegacyCommsRedirectController|providers_new
redirect|/missions/:mission_id/comms/provider-profiles/:provider_profile_id|LegacyCommsRedirectController|providers_show
redirect|/missions/:mission_id/comms/provider-profiles/:provider_profile_id/new-version|LegacyCommsRedirectController|providers_new_version
redirect|/missions/:mission_id/comms/source-endpoints|LegacyCommsRedirectController|runtime_identities_index
redirect|/missions/:mission_id/comms/source-endpoints/new|LegacyCommsRedirectController|runtime_identities_new
redirect|/missions/:mission_id/comms/advanced/runtime-identities|LegacyCommsRedirectController|runtime_identities_index
redirect|/missions/:mission_id/comms/advanced/runtime-identities/new|LegacyCommsRedirectController|runtime_identities_new
`.trim().split("\n")

assert.equal(expectedLiveRoutes.length, 89)
assert.equal(expectedBrowserGets.length, 30)

const walkFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name)
      return entry.isDirectory() ? walkFiles(path) : [path]
    }),
  )

  return nested.flat()
}

const routerSource = await readFile(routerPath, "utf8")

const parseLiveRoutes = (source) => {
  const routes = []
  let liveSession = null
  let pendingRoute = ""

  for (const line of source.split("\n")) {
    const sessionStart = line.match(/^    live_session :(\w+)/)
    if (sessionStart) {
      liveSession = sessionStart[1]
      continue
    }

    if (liveSession && /^    end\s*$/.test(line)) {
      liveSession = null
      pendingRoute = ""
      continue
    }

    if (liveSession && /^      live\s+/.test(line)) {
      pendingRoute = line.trim()
    } else if (pendingRoute) {
      pendingRoute += ` ${line.trim()}`
    }

    const route = pendingRoute.match(
      /^live\s+"([^"]+)"\s*,\s*([A-Z][A-Za-z0-9_.]*)\s*,\s*:(\w+)/,
    )

    if (route) {
      routes.push(`${liveSession}|${route[1]}|${route[2]}|${route[3]}`)
      pendingRoute = ""
    }
  }

  return routes
}

assert.deepEqual(parseLiveRoutes(routerSource), expectedLiveRoutes)

const apiStart = routerSource.indexOf('  scope "/api", CadenceWeb do')
assert.ok(apiStart > 0, "API scopes remain present after browser routes")

const browserSource = routerSource.slice(0, apiStart)
const browserGets = [
  ...browserSource.matchAll(
    /\bget\s+"([^"]+)"\s*,\s*([A-Z][A-Za-z0-9_.]*)\s*,\s*:(\w+)/gs,
  ),
].map((match) => `${match[1]}|${match[2]}|${match[3]}`)

assert.deepEqual(
  browserGets,
  expectedBrowserGets.map((entry) => entry.split("|").slice(1).join("|")),
)

assert.doesNotMatch(
  routerSource,
  /get\s+"\/missions\/:mission_id\/comms\/federated"/s,
  "retired application-specific Comms host path is not routed",
)
assert.doesNotMatch(
  routerSource,
  /LegacyApplicationRedirectController[\s,]+:comms_overview/s,
  "retired Comms host dispatch branch is absent",
)

const publicBrowserScope = browserSource.slice(
  browserSource.indexOf('  scope "/", CadenceWeb do\n    pipe_through :browser'),
  browserSource.indexOf(
    '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  ),
)
const authenticatedBrowserScope = browserSource.slice(
  browserSource.indexOf(
    '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  ),
)

for (const entry of expectedBrowserGets) {
  const [kind, path, controller, action] = entry.split("|")
  const declaration = new RegExp(
    `get\\s+"${path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"\\s*,\\s*${controller}\\s*,\\s*:${action}`,
    "s",
  )
  const scope = kind === "public_page" ? publicBrowserScope : authenticatedBrowserScope
  assert.match(scope, declaration, `${path} remains in its audited browser pipeline`)
}

const apiSource = routerSource.slice(apiStart)
const apiGets = [...apiSource.matchAll(/\bget\s+"[^"]+"\s*,/g)]
assert.equal(apiGets.length, 63, "JSON API GET declarations remain outside presentation closure")
assert.match(
  apiSource,
  /scope "\/api", CadenceWeb do\s+pipe_through :api\s+get "\/health", HealthController, :show/s,
)
assert.match(
  apiSource,
  /scope "\/api", CadenceWeb do\s+pipe_through \[:api, :authenticated_api\]/s,
)

const liveFiles = await walkFiles(liveRoot)
const liveModuleSources = new Map()

for (const path of liveFiles.filter((path) => extname(path) === ".ex")) {
  const source = await readFile(path, "utf8")
  const module = source.match(/defmodule\s+([A-Z][A-Za-z0-9_.]+)/)?.[1]
  if (module) liveModuleSources.set(module, {path, source})
}

const rendererOverrides = new Map([
  [
    "CadenceWeb.OpsDashboardEditorLive",
    {
      target: "CadenceWeb.OpsDashboardShowLive.Controller",
      delegation: /defdelegate render\(assigns\), to: Controller/,
    },
  ],
  [
    "CadenceWeb.OpsDashboardViewerLive",
    {
      target: "CadenceWeb.OpsDashboardShowLive.Controller",
      delegation: /defdelegate render\(assigns\), to: Controller/,
    },
  ],
  [
    "CadenceWeb.OpsDataSourcesLive",
    {
      target: "CadenceWeb.OpsDataSourcesLive.Page",
      delegation: /def render\(assigns\), do: Page\.render\(assigns\)/,
    },
  ],
  [
    "CadenceWeb.OpsTelemetryExploreLive",
    {
      target: "CadenceWeb.OpsTelemetryExploreComponents",
      delegation: /def render\(assigns\), do: OpsTelemetryExploreComponents\.page\(assigns\)/,
    },
  ],
])

const controllerPageContracts = [
  {
    controller: "admin_mode_controller.ex",
    liveModule: "CadenceWeb.AdminModeLive",
    component: "AdminModePage",
  },
  {
    controller: "no_organization_controller.ex",
    liveModule: "CadenceWeb.NoOrganizationLive",
    component: "NoOrganizationPage",
  },
  {
    controller: "organization_invitation_controller.ex",
    liveModule: "CadenceWeb.OrganizationInvitationLive",
    component: "OrganizationInvitationPage",
  },
]

for (const contract of controllerPageContracts) {
  const controllerPath = resolve(controllerRoot, contract.controller)
  const controllerSource = await readFile(controllerPath, "utf8")
  assert.ok(
    controllerSource.includes(`live_render(${contract.liveModule},`),
    `${contract.controller} remains a live_render page`,
  )

  const liveSource = liveModuleSources.get(contract.liveModule)?.source
  assert.ok(liveSource, `${contract.liveModule} remains defined`)
  assert.ok(liveSource.includes(`v-component="${contract.component}"`))
}

const rendererTargets = new Map()

for (const entry of expectedLiveRoutes) {
  const [, path, routeModule] = entry.split("|")
  const fullModule = `CadenceWeb.${routeModule}`
  const routeSource = liveModuleSources.get(fullModule)
  assert.ok(routeSource, `${path} resolves to ${fullModule}`)

  const override = rendererOverrides.get(fullModule)
  if (override) {
    assert.match(routeSource.source, override.delegation)
    rendererTargets.set(override.target, path)
  } else {
    assert.match(routeSource.source, /\bdef render\s*\(/, `${fullModule} defines render`)
    rendererTargets.set(fullModule, path)
  }
}

for (const contract of controllerPageContracts) {
  rendererTargets.set(contract.liveModule, contract.controller)
}

const vueHosts = (template) => [...template.matchAll(/<\.vue\b([\s\S]*?)\/>/g)]
const assertNonSsrHosts = async (template, label) => {
  const hosts = vueHosts(template)
  assert.ok(hosts.length > 0, `${label} has a LiveVue host`)
  assert.ok(
    hosts.some((host) => !host[1].includes(":if=")),
    `${label} has an unconditional LiveVue host`,
  )

  for (const host of hosts) {
    assert.match(host[1], /v-ssr=\{false\}/, `${label} host is non-SSR`)
    const component = host[1].match(/v-component="([^"]+)"/)?.[1]
    assert.ok(component, `${label} host names a static component`)
    await access(resolve(vueRoot, `${component}.vue`))
  }
}

for (const [rendererModule, routeLabel] of rendererTargets) {
  const renderer = liveModuleSources.get(rendererModule)
  assert.ok(renderer, `${rendererModule} renderer remains defined`)
  const templates = [...renderer.source.matchAll(/~H"""([\s\S]*?)"""/g)].map(
    (match) => match[1],
  )
  assert.ok(templates.length > 0, `${rendererModule} has a HEEx render template`)

  if (rendererModule === "CadenceWeb.ApplicationHostLive") {
    const hostTemplates = templates.filter((template) => vueHosts(template).length > 0)
    const transitionTemplates = templates.filter((template) => vueHosts(template).length === 0)
    assert.equal(hostTemplates.length, 2, "trusted and declarative application surfaces host Vue")
    assert.equal(transitionTemplates.length, 1, "application redirect transition stays explicit")
    assert.match(transitionTemplates[0], /<div id="application-host"><\/div>/)
    assert.equal(
      [...renderer.source.matchAll(/\|> push_navigate\(to: inventory_path\(socket\.assigns\)\)/g)]
        .length,
      2,
      "not-found and unavailable applications navigate away instead of presenting HEEx",
    )
    for (const template of hostTemplates) {
      await assertNonSsrHosts(template, `${routeLabel} via ${rendererModule}`)
    }
  } else {
    for (const template of templates) {
      await assertNonSsrHosts(template, `${routeLabel} via ${rendererModule}`)
    }
  }
}

const controllerFiles = await walkFiles(controllerRoot)
assert.deepEqual(
  controllerFiles.filter((path) => [".eex", ".heex", ".leex"].includes(extname(path))),
  [federatedTemplatePath],
  "only the federated host retains a controller-owned HEEx template",
)

for (const path of controllerFiles.filter((path) => extname(path) === ".ex")) {
  const source = await readFile(path, "utf8")
  if (path === federatedHtmlModulePath) continue
  if (path === federatedControllerPath) {
    assert.match(source, /\brender\(conn, :federated,/, "federated host renders its dedicated template")
    continue
  }
  assert.doesNotMatch(source, /\bembed_templates\b/, `${relative(webRoot, path)} embeds no templates`)
  assert.doesNotMatch(source, /\brender\s*\(/, `${relative(webRoot, path)} renders no controller HEEx`)
}

const productionFiles = [
  ...(await walkFiles(runtimeTemplateRoot)).filter((path) =>
    [".ex", ".heex"].includes(extname(path)),
  ),
  ...(await walkFiles(vueRoot)).filter((path) => [".js", ".ts", ".vue"].includes(extname(path))),
  appPath,
]

for (const path of productionFiles) {
  const source = await readFile(path, "utf8")
  assert.doesNotMatch(source, /\bphx-hook\s*=/, `${relative(webRoot, path)} has no phx-hook`)
}

const runtimeTemplateFiles = productionFiles.filter((path) =>
  [".ex", ".heex"].includes(extname(path)),
)
const scriptTags = []

for (const path of runtimeTemplateFiles) {
  const source = await readFile(path, "utf8")
  for (const match of source.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
    scriptTags.push({path, attributes: match[1], body: match[2]})
  }
}

assert.ok(scriptTags.length > 0, "root layout still loads the production bundle")
for (const script of scriptTags) {
  assert.match(
    script.attributes,
    /\bsrc=/,
    `${relative(webRoot, script.path)} loads an external script`,
  )
  assert.equal(
    script.body.trim(),
    "",
    `${relative(webRoot, script.path)} contains no inline script body`,
  )
}

const appSource = await readFile(appPath, "utf8")
const vueIndexSource = await readFile(vueIndexPath, "utf8")
const federatedTemplateSource = await readFile(federatedTemplatePath, "utf8")
assert.match(appSource, /const Hooks = \{\s*LiveToast: createLiveToastHook\(\)\s*\}/)
assert.match(appSource, /hooks: \{\.\.\.Hooks, \.\.\.getHooks\(liveVueApp\)\}/)
assert.doesNotMatch(
  federatedTemplateSource,
  /<script\b/,
  "federated HEEx delegates its host loader to app.js",
)
assert.match(
  appSource,
  /const federationRoot = document\.querySelector\("#cadence-federation-root"\)/,
  "app.js identifies the opt-in federation root",
)
assert.match(
  appSource,
  /if \(federationRoot\)\s*\{\s*const federationHostAsset = "\/assets\/application-host\/host\/host\.js"\s*void import\(\/\* @vite-ignore \*\/ federationHostAsset\)/,
  "app.js runtime-loads the separately published host bundle",
)
assert.doesNotMatch(appSource, /\bdom\s*:/, "LiveSocket has no global DOM callback object")
assert.doesNotMatch(
  appSource,
  /onBeforeElUpdated|onNodeAdded|onNodeDiscarded|onElUpdated/,
  "LiveSocket has no legacy global DOM callbacks",
)
assert.match(vueIndexSource, /import\.meta\.glob\("\.\/\*\*\/\*\.vue", \{eager: true\}\)/)
assert.match(vueIndexSource, /resolve: \(name\) => findComponent\(components, name\)/)

const applicationJsFiles = (await walkFiles(resolve(webRoot, "assets/js")))
  .filter((path) => [".js", ".mjs", ".ts"].includes(extname(path)))
  .map((path) => relative(resolve(webRoot, "assets/js"), path))
  .sort()
assert.deepEqual(applicationJsFiles, ["app.js"], "no legacy JS hook modules remain")

console.log("route_livevue_closure_test passed")
