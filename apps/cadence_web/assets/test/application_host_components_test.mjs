import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {installDom, integrationRequire} from "./reka_adapter_test_support.mjs"

const scenarioLedger = Object.freeze([
  "the three frozen inline source regions transfer one-for-one to feature-scoped components",
  "ApplicationHost composes navigation, stats, and diagnostics in the original sibling order",
  "the original navigation, stats, and diagnostics conditional branches stay exact",
  "the extracted components add no native wrapper elements",
  "native tags, ids, attributes, redirect attributes, classes, class order, keys, and copy stay exact",
  "StatusBadge keeps the original stat status and label mapping",
  "StatusBadge keeps the original diagnostic severity, status, and label mapping",
  "the extracted regions compile with their shared TypeScript presentation types",
  "the extracted regions remain display-only and do not emit events or mutate props",
  "forms, packet controls, actions, confirmations, event handlers, watchers, and mutations remain in ApplicationHost",
  "the composed runtime renders the three exact pre-extraction native DOM fragments",
])
const transferredInlineSourceOracles = Object.freeze([
  Object.freeze({
    region: "application navigation",
    component: "ApplicationNavigation.vue",
    baseline_sha256: "85982b52c44fda6f267365c71b82f2520b7a869819288fcd95df7d5d95f477a0",
  }),
  Object.freeze({
    region: "application stats",
    component: "ApplicationStats.vue",
    baseline_sha256: "7e7256cf1572c1b5c3a35d511c58163a10dd5af34e53448943ae556b3461e5ee",
  }),
  Object.freeze({
    region: "application diagnostics",
    component: "ApplicationDiagnostics.vue",
    baseline_sha256: "37cd7eb447fe6325f36121dd900c4291dd512f87bc273a0878e7accbea5f5e7d",
  }),
])

assert.equal(
  process.versions.node,
  "24.16.0",
  "application-host component contracts use pinned Node 24.16.0",
)
assert.equal(scenarioLedger.length, 11)
assert.equal(transferredInlineSourceOracles.length, 3)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const paths = {
  applicationHost: resolve(testDirectory, "../vue/ApplicationHost.vue"),
  navigation: resolve(testDirectory, "../vue/application_host/ApplicationNavigation.vue"),
  stats: resolve(testDirectory, "../vue/application_host/ApplicationStats.vue"),
  diagnostics: resolve(testDirectory, "../vue/application_host/ApplicationDiagnostics.vue"),
  presentationTypes: resolve(testDirectory, "../vue/application_host/presentation_types.ts"),
  statusBadge: resolve(testDirectory, "../vue/StatusBadge.vue"),
  cadenceBadge: resolve(testDirectory, "../vue/ui/components/CadenceBadge.vue"),
  cadenceCard: resolve(testDirectory, "../vue/ui/components/CadenceCard.vue"),
  cadencePaginationFrame: resolve(
    testDirectory,
    "../vue/ui/components/CadencePaginationFrame.vue",
  ),
  cadencePageHeaderFrame: resolve(
    testDirectory,
    "../vue/ui/components/CadencePageHeaderFrame.vue",
  ),
}
const [
  applicationHostSource,
  navigationSource,
  statsSource,
  diagnosticsSource,
  presentationTypesSource,
] = await Promise.all([
  readFile(paths.applicationHost, "utf8"),
  readFile(paths.navigation, "utf8"),
  readFile(paths.stats, "utf8"),
  readFile(paths.diagnostics, "utf8"),
  readFile(paths.presentationTypes, "utf8"),
])

for (const [component, path] of [
  ["ApplicationDiagnostics", "./application_host/ApplicationDiagnostics.vue"],
  ["ApplicationNavigation", "./application_host/ApplicationNavigation.vue"],
  ["ApplicationStats", "./application_host/ApplicationStats.vue"],
]) {
  assert.match(applicationHostSource, new RegExp(`^import ${component} from "${path}"$`, "m"))
  assert.equal(applicationHostSource.match(new RegExp(`<${component}\\b`, "g"))?.length, 1)
}

const navigationCall = applicationHostSource.indexOf(
  '<ApplicationNavigation v-if="navigation" :navigation="navigation" />',
)
const statsCall = applicationHostSource.indexOf("    <ApplicationStats\n")
const diagnosticsCall = applicationHostSource.indexOf("    <ApplicationDiagnostics\n")
const formRegion = applicationHostSource.indexOf('      v-if="declarative_surface.form"')
assert.ok(navigationCall >= 0)
assert.ok(navigationCall < statsCall && statsCall < diagnosticsCall && diagnosticsCall < formRegion)
assert.match(
  applicationHostSource,
  /<ApplicationStats\s+v-if="declarative_surface\.stats\.length > 0"\s+:stats="declarative_surface\.stats"\s+\/>/,
)
assert.match(
  applicationHostSource,
  /<ApplicationDiagnostics\s+v-if="declarative_surface\.diagnostics"\s+:diagnostics="declarative_surface\.diagnostics"\s+\/>/,
)

for (const retainedOwner of [
  "watch(",
  "const formValues = ref",
  "const packetValues = ref",
  "const selectedPacketIds = ref",
  "const confirmAction =",
  "const submitGeneratedForm =",
  "const changePacketValue =",
  "const changePacketSelection =",
  "const submitPacketBindings =",
  "@submit.prevent=\"submitGeneratedForm(declarative_surface.form)\"",
  "@submit.prevent=\"submitPacketBindings(declarative_surface.packet_bindings)\"",
  "@click=\"paginate(declarative_surface.table.pagination.previous_page)\"",
]) {
  assert.ok(applicationHostSource.includes(retainedOwner), `${retainedOwner} remains host-owned`)
}

assert.doesNotMatch(
  `${navigationSource}\n${statsSource}\n${diagnosticsSource}`,
  /defineEmits|\b(?:computed|reactive|ref|watch)\s*\(|@(?:click|change|input|submit)|window\.confirm|<form\b|<button\b|<input\b|<select\b|<textarea\b/,
)
assert.doesNotMatch(
  applicationHostSource,
  /diagnosticHeaderIcons|diagnosticHeaderIconClasses|diagnosticRailClasses|diagnosticItemIcons/,
)

assert.match(navigationSource, /defineProps<\{navigation: Navigation\}>\(\)/)
assert.match(navigationSource, /v-for="item in navigation\.items"/)
assert.match(navigationSource, /:key="item\.surface_id"/)
assert.match(navigationSource, /data-phx-link="redirect"/)
assert.match(navigationSource, /data-phx-link-state="push"/)
assert.match(navigationSource, /:aria-current="item\.current \? 'page' : undefined"/)
assert.match(statsSource, /defineProps<\{stats: Stat\[\]\}>\(\)/)
assert.match(statsSource, /v-for="stat in stats"/)
assert.match(statsSource, /:key="stat\.stat_id"/)
assert.match(statsSource, /<StatusBadge :status="stat\.tone" :label="stat\.tone_label" \/>/)
assert.match(diagnosticsSource, /defineProps<\{diagnostics: Diagnostics\}>\(\)/)
assert.match(diagnosticsSource, /v-for="item in diagnostics\.items"/)
assert.match(diagnosticsSource, /:key="item\.diagnostic_id"/)
assert.match(
  diagnosticsSource,
  /:status="diagnostics\.severity === 'error'\s+\? 'blocked'\s+: diagnostics\.severity === 'warning' \? 'attention' : 'info'"/,
)
assert.match(diagnosticsSource, /:label="diagnostics\.label"/)

for (const typeContract of [
  'export type StatusTone = "ready" | "attention" | "blocked" | "info"',
  'export type DiagnosticSeverity = "error" | "warning" | "info"',
  "export type Navigation = {",
  "export type Stat = {",
  "export type Diagnostics = {",
]) {
  assert.ok(presentationTypesSource.includes(typeContract), `${typeContract} remains shared`)
}

const dom = installDom('<div id="app"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
assert.doesNotThrow(() =>
  transformSync(presentationTypesSource, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  }),
)

const loadSfc = async (componentPath, localModules = {}) => {
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${componentPath} parses with the pinned Vue compiler`)
  const script = parsed.descriptor.scriptSetup ?? parsed.descriptor.script
  assert.ok(script, `${componentPath} keeps a TypeScript script block`)
  assert.equal(script.lang, "ts")
  if (parsed.descriptor.scriptSetup) {
    assert.ok(parsed.descriptor.template, `${componentPath} keeps a template block`)
  }

  const compiled = compileScript(parsed.descriptor, {
    id: `application-host-${componentPath.split("/").at(-1)}`,
    inlineTemplate: true,
  })
  const transformed = transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  const localRequire = (specifier) => localModules[specifier] ?? integrationRequire(specifier)

  new Function("require", "module", "exports", transformed.code)(
    localRequire,
    loadedModule,
    loadedModule.exports,
  )

  return loadedModule.exports
}

const cadenceBadge = await loadSfc(paths.cadenceBadge)
const cadenceCard = await loadSfc(paths.cadenceCard)
const cadencePaginationFrame = await loadSfc(paths.cadencePaginationFrame)
const cadencePageHeaderFrame = await loadSfc(paths.cadencePageHeaderFrame)
const statusBadge = await loadSfc(paths.statusBadge, {
  "./ui/components/CadenceBadge.vue": cadenceBadge,
})
const navigation = await loadSfc(paths.navigation)
const stats = await loadSfc(paths.stats, {
  "../StatusBadge.vue": statusBadge,
  "../ui/components/CadenceCard.vue": cadenceCard,
})
const diagnostics = await loadSfc(paths.diagnostics, {"../StatusBadge.vue": statusBadge})
const cadenceValidationMessage = {default: {name: "CadenceValidationMessage"}}
const applicationHost = await loadSfc(paths.applicationHost, {
  "./StatusBadge.vue": statusBadge,
  "./application_host/ApplicationDiagnostics.vue": diagnostics,
  "./application_host/ApplicationNavigation.vue": navigation,
  "./application_host/ApplicationStats.vue": stats,
  "./ui/components/CadenceCard.vue": cadenceCard,
  "./ui/components/CadencePaginationFrame.vue": cadencePaginationFrame,
  "./ui/components/CadencePageHeaderFrame.vue": cadencePageHeaderFrame,
  "./ui/components/CadenceValidationMessage.vue": cadenceValidationMessage,
})

assert.deepEqual(Object.keys(navigation.default.props), ["navigation"])
assert.deepEqual(Object.keys(stats.default.props), ["stats"])
assert.deepEqual(Object.keys(diagnostics.default.props), ["diagnostics"])

const props = {
  host: {
    dom_id: "mission-application-host",
    application_key: "limits",
    application_version: 1,
    application_installation_id: "application-installation-1",
    surface_id: "activity",
    renderer: "declarative",
  },
  navigation: {
    id: "application-surface-navigation",
    label: "Application surfaces",
    items: [
      {
        id: "application-surface-nav-manage",
        surface_id: "manage",
        label: "Definitions",
        href: "/missions/mission-1/applications/limits/manage",
        current: false,
      },
      {
        id: "application-surface-nav-activity",
        surface_id: "activity",
        label: "Current posture",
        href: "/missions/mission-1/applications/limits/activity",
        current: true,
      },
    ],
  },
  declarative_surface: {
    id: "declarative-application-surface",
    page: {title: "Current limit posture", subtitle: null},
    action_feedback: null,
    stats: [
      {
        id: "application-surface-stat-red",
        stat_id: "red",
        label: "Red departures",
        value: "1",
        tone: "blocked",
        tone_label: "Missing",
      },
      {
        id: "application-surface-stat-nominal",
        stat_id: "nominal",
        label: "Nominal points",
        value: "12",
        tone: "ready",
        tone_label: "Ready",
      },
    ],
    diagnostics: {
      id: "limit-current-diagnostics",
      items_id: "limit-current-diagnostics-items",
      role: "alert",
      severity: "error",
      count: 2,
      total_count: 3,
      count_label: "2 shown · 3 total",
      label: "Blocked",
      title: "Current limit findings",
      description: "Resolve current departures.",
      items: [
        {
          id: "limit-current-diagnostics-item-red",
          diagnostic_id: "red",
          code: "limits.current.red",
          severity: "error",
          title: "Red limit departures",
          detail: "One point is beyond a red threshold.",
          value: "HK.bus_voltage",
        },
        {
          id: "limit-current-diagnostics-item-advisory",
          diagnostic_id: "advisory",
          code: "limits.current.advisory",
          severity: "warning",
          title: "Advisory posture",
          detail: "Review the configured threshold.",
          value: null,
        },
      ],
    },
    form: null,
    packet_bindings: null,
    table: null,
    activity: null,
  },
  application_surface_rows: [],
  application_surface_activity: [],
  application_surface_packet_groups: [],
}
const frozenProps = structuredClone(props)
const expectedHtml = {
  "#application-surface-navigation": '<nav id="application-surface-navigation" aria-label="Application surfaces" class="mb-5 flex flex-wrap items-center gap-1 border-b border-base-300/70"><a id="application-surface-nav-manage" href="/missions/mission-1/applications/limits/manage" data-phx-link="redirect" data-phx-link-state="push" class="relative -mb-px border-b-2 px-3 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition-colors border-transparent text-base-content/55 hover:border-base-content/30 hover:text-base-content">Definitions</a><a id="application-surface-nav-activity" href="/missions/mission-1/applications/limits/activity" data-phx-link="redirect" data-phx-link-state="push" aria-current="page" class="relative -mb-px border-b-2 px-3 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition-colors border-primary text-primary">Current posture</a></nav>',
  "#application-surface-stats": '<section id="application-surface-stats" class="grid gap-4 md:grid-cols-3"><section id="application-surface-stat-red" class="card border border-base-300 bg-base-200"><div class="card-body p-6"><div class="flex items-start justify-between gap-3"><div><p class="hud-label">Red departures</p><p class="mt-2 text-2xl font-semibold">1</p></div><span class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-error/20 text-error">Missing</span></div></div></section><section id="application-surface-stat-nominal" class="card border border-base-300 bg-base-200"><div class="card-body p-6"><div class="flex items-start justify-between gap-3"><div><p class="hud-label">Nominal points</p><p class="mt-2 text-2xl font-semibold">12</p></div><span class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-success/20 text-success">Ready</span></div></div></section></section>',
  "#limit-current-diagnostics": '<section id="limit-current-diagnostics" role="alert" aria-live="polite" data-diagnostic-severity="error" data-diagnostic-count="2" data-diagnostic-total="3" class="overflow-hidden border border-base-300/80 bg-base-200/30"><header class="grid gap-4 border-b border-base-300/70 px-4 py-3 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center"><div class="grid size-9 place-items-center border border-error/35 bg-error/10 text-error"><span class="size-4 hero-exclamation-triangle" aria-hidden="true"></span></div><div class="min-w-0"><div class="flex flex-wrap items-center gap-x-3 gap-y-1"><h2 class="text-sm font-semibold uppercase tracking-[0.14em]">Current limit findings</h2><span class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45">2 shown · 3 total</span></div><p class="mt-1 text-sm text-base-content/65">Resolve current departures.</p></div><span class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-error/20 text-error">Blocked</span></header><div id="limit-current-diagnostics-items" class="divide-y divide-base-300/60"><article id="limit-current-diagnostics-item-red" data-diagnostic-code="limits.current.red" data-diagnostic-severity="error" class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"><span class="rounded-full bg-error"></span><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><span class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45">limits.current.red</span><h3 class="text-sm font-medium text-base-content">Red limit departures</h3></div><p class="mt-1 text-xs leading-5 text-base-content/60">One point is beyond a red threshold.</p></div><div class="flex items-center gap-3 self-center"><span class="max-w-56 truncate font-mono text-xs text-base-content/65">HK.bus_voltage</span><span class="size-4 shrink-0 hero-x-circle text-error" aria-hidden="true"></span></div></article><article id="limit-current-diagnostics-item-advisory" data-diagnostic-code="limits.current.advisory" data-diagnostic-severity="warning" class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"><span class="rounded-full bg-warning"></span><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><span class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45">limits.current.advisory</span><h3 class="text-sm font-medium text-base-content">Advisory posture</h3></div><p class="mt-1 text-xs leading-5 text-base-content/60">Review the configured threshold.</p></div><div class="flex items-center gap-3 self-center"><!--v-if--><span class="size-4 shrink-0 hero-exclamation-circle text-warning" aria-hidden="true"></span></div></article></div></section>',
}
const {createApp, nextTick} = integrationRequire("vue")
const app = createApp(applicationHost.default, props)
app.mount(dom.window.document.querySelector("#app"))
await nextTick()

for (const [selector, html] of Object.entries(expectedHtml)) {
  const element = dom.window.document.querySelector(selector)
  assert.ok(element, `${selector} remains rendered by the composed host`)
  assert.equal(element.outerHTML, html, `${selector} keeps its exact frozen native DOM shape`)
}

assert.deepEqual(props, frozenProps, "the display components do not mutate Phoenix presentation DTOs")
assert.equal(
  dom.window.document.querySelector("#application-surface-navigation").parentElement,
  dom.window.document.querySelector("#declarative-application-surface").parentElement,
  "application navigation adds no wrapper",
)
assert.equal(
  dom.window.document.querySelector("#application-surface-stats").parentElement.id,
  "declarative-application-surface",
  "application stats add no wrapper",
)
assert.equal(
  dom.window.document.querySelector("#limit-current-diagnostics").parentElement.id,
  "declarative-application-surface",
  "application diagnostics add no wrapper",
)
assert.doesNotThrow(() => app.unmount())

console.log("application host component contracts passed")
