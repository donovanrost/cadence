import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = [
  "Phoenix keeps the drawer shell, responsive account chrome, inner content, and LiveToast",
  "one non-SSR LiveVue parent owns the complete drawer-side surface",
  "Phoenix projects JSON-safe mission identity, routes, active states, and navigation attrs",
  "the organization link and every mission, Ops, and Comms entry preserve order and copy",
  "the sign-out form preserves POST tunneling, CSRF, submit, and DELETE session semantics",
  "collapse starts expanded and toggles only Vue-local reactive state",
  "the established sidebar classes and collapse CSS contract remain unchanged",
  "all five authenticated production LiveSessions retain their router and auth ownership",
]

assert.equal(process.versions.node, "24.16.0", "mission sidebar contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 8)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/MissionSidebarNavigation.vue")
const layoutTemplatePath = resolve(
  __dirname,
  "../../lib/cadence_web/components/layouts/mission_sidebar.html.heex",
)
const layoutsPath = resolve(__dirname, "../../lib/cadence_web/components/layouts.ex")
const sidebarPrimitivesPath = resolve(
  __dirname,
  "../../lib/cadence_web/components/sidebar.ex",
)
const sidebarCssPath = resolve(__dirname, "../css/components/sidebar.css")
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [componentSource, layoutTemplate, layoutsSource, sidebarPrimitives, sidebarCss, router] =
  await Promise.all([
    readFile(componentPath, "utf8"),
    readFile(layoutTemplatePath, "utf8"),
    readFile(layoutsPath, "utf8"),
    readFile(sidebarPrimitivesPath, "utf8"),
    readFile(sidebarCssPath, "utf8"),
    readFile(routerPath, "utf8"),
  ])

const capture = (source, pattern, label) => {
  const match = source.match(pattern)

  assert.ok(match, `${label} must remain source-auditable`)
  return match[1]
}

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return source.slice(startIndex, endIndex)
}

const moduleAttribute = (name) =>
  capture(layoutsSource, new RegExp(`@${name} "([^"]+)"`), `@${name}`)

const classTokens = (className) => className.trim().split(/\s+/).sort()

const assertSameClassTokens = (actual, expected, label) =>
  assert.deepEqual(classTokens(actual), classTokens(expected), `${label} class tokens match sidebar.ex`)

const script = componentSource.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = componentSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "MissionSidebarNavigation.vue must have a script setup block")
assert.ok(template, "MissionSidebarNavigation.vue must have a template block")

assert.equal(layoutTemplate.match(/<\.vue/g)?.length, 1)
assert.match(layoutTemplate, /id="mission-sidebar-navigation"/)
assert.match(layoutTemplate, /v-component="MissionSidebarNavigation"/)
assert.match(layoutTemplate, /presentation=\{mission_sidebar_navigation_presentation\(assigns\)\}/)
assert.match(layoutTemplate, /v-ssr=\{false\}/)
assert.match(layoutTemplate, /class="drawer-side"/)

assert.match(layoutTemplate, /<div class="drawer lg:drawer-open">/)
assert.match(layoutTemplate, /<input id="sidebar-drawer" type="checkbox" class="drawer-toggle" \/>/)
assert.match(layoutTemplate, /<div class="drawer-content flex flex-col">/)
assert.match(layoutTemplate, /id="notifications-bell-mobile"/)
assert.match(layoutTemplate, /id="notifications-bell-desktop"/)
assert.match(layoutTemplate, /id="user-menu-mobile"/)
assert.match(layoutTemplate, /id="user-menu-desktop"/)
assert.match(layoutTemplate, /\{@inner_content\}/)
assert.match(layoutTemplate, /<LiveToast\.toast_group/)

const drawerStart = layoutTemplate.indexOf('  <.vue\n    id="mission-sidebar-navigation"')
const drawerEnd = layoutTemplate.indexOf("\n  />", drawerStart)
const drawerSource = layoutTemplate.slice(drawerStart, drawerEnd)

assert.ok(drawerStart >= 0 && drawerEnd > drawerStart, "drawer-side host must remain auditable")
assert.equal(drawerSource.match(/<\.vue/g)?.length, 1)
assert.match(drawerSource, /class="drawer-side"/)
assert.doesNotMatch(drawerSource, /<label|<nav|<\.nav_item|<\.nav_section|<\.form|onclick=/)
assert.doesNotMatch(layoutTemplate, /document\.querySelectorAll|classList\.toggle/)

assert.match(script, /import \{ref\} from "vue"/)
assert.match(script, /presentation: \{type: Object, required: true\}/)
assert.match(script, /const collapsed = ref\(false\)/)
assert.match(script, /const sidebarClass = \(\) =>/)
assert.match(script, /collapsed\.value = !collapsed\.value/)
assert.doesNotMatch(script, /document|querySelector|querySelectorAll|localStorage|sessionStorage/)

assert.ok(template.indexOf("<label") < template.indexOf("<div"))
assert.match(template, /v-bind="props\.presentation\.overlay\.attrs"/)
assert.match(template, /:class="sidebarClass\(\)"/)
assert.match(template, /v-bind="props\.presentation\.root\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.organization\.link\.attrs"/)
assert.match(template, /v-if="props\.presentation\.mission\.slug_visible"/)
assert.match(template, /v-for="item in props\.presentation\.navigation\.items"/)
assert.match(template, /:open="item\.expanded"/)
assert.match(template, /v-bind="item\.attrs"/)
assert.match(template, /v-for="child in item\.children"/)
assert.match(template, /v-bind="child\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.sign_out\.form\.attrs"/)
assert.match(template, /props\.presentation\.sign_out\.form\.hidden_fields/)
assert.match(template, /v-bind="field\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.collapse\.attrs"/)
assert.match(template, /@click="toggleCollapsed"/)
assert.doesNotMatch(
  componentSource,
  /\/missions|\/session|Overview|Spacecraft|Applications|Catalog|Dashboards|Transports|Ground Stations|Routing|Validation|Sign out/,
)

assert.match(layoutsSource, /"aria-label" => "close sidebar", "for" => "sidebar-drawer"/)
assert.match(layoutsSource, /"data-sidebar-collapsible" => ""/)
assert.match(layoutsSource, /"expanded_class" =>[\s\S]*?"sidebar-collapsible sidebar-expanded/)
assert.match(layoutsSource, /"collapsed_class" =>[\s\S]*?"sidebar-collapsible sidebar-collapsed/)
assert.match(layoutsSource, /"data-phx-link" => "redirect"/)
assert.match(layoutsSource, /"data-phx-link-state" => "push"/)
assert.match(layoutsSource, /Plug\.CSRFProtection\.get_csrf_token_for\(~p"\/session"\)/)
assert.match(layoutsSource, /"name" => "_method", "type" => "hidden", "value" => "delete"/)
assert.match(layoutsSource, /"name" => "_csrf_token"/)

for (const className of [
  "drawer-overlay",
  "sidebar-collapsible sidebar-expanded min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative",
  "sidebar-collapsible sidebar-collapsed min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative",
  "px-3 h-10 flex items-center border-b border-primary/20",
  "flex items-center gap-2 text-xs text-base-content/60 hover:text-base-content",
  "hero-chevron-left h-3 w-3",
  "sidebar-label tracking-wide uppercase",
  "px-3 pt-4 pb-2 sidebar-expanded-only",
  "text-sm font-bold text-base-content truncate",
  "text-xs text-base-content/50 font-mono truncate",
  "flex-1 overflow-y-auto py-2",
  "menu menu-sm space-y-0.5",
  "flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all",
  "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]",
  "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30",
  "sidebar-label flex-1",
  "hero-chevron-right h-3 w-3 opacity-60 transition-transform group-open:rotate-90 sidebar-label",
  "mt-0.5 space-y-0.5",
  "flex items-center gap-2 px-3 py-1.5 text-xs tracking-wide uppercase border-l-2 border-transparent transition-all",
  "h-4 w-4 flex items-center justify-center flex-shrink-0",
  "px-2 py-2 border-t border-primary/20",
  "w-full",
  "btn btn-ghost btn-sm w-full justify-start gap-2 text-xs uppercase tracking-wide text-base-content/60",
  "hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80",
  "sidebar-toggle-btn hidden lg:flex",
  "hero-chevron-left h-3 w-3 toggle-chevron transition-transform",
]) {
  assert.ok(layoutsSource.includes(`"${className}"`), `${className} remains presentation-owned`)
}

for (const classFragment of [
  "h-4 w-4 opacity-80 flex-shrink-0",
  "h-1.5 w-1.5 rounded-full transition-colors",
]) {
  assert.ok(layoutsSource.includes(classFragment), `${classFragment} remains presentation-owned`)
}

for (const route of [
  "/spacecraft",
  "/applications",
  "/catalog",
  "/ops/dashboards",
  "/comms",
  "/comms/transports",
  "/comms/ground-stations",
  "/comms/routing",
  "/comms/validation",
]) {
  assert.ok(layoutsSource.includes(`mission.mission_id}${route}`), `${route} remains server-generated`)
}

for (const label of [
  "Overview",
  "Spacecraft",
  "Applications",
  "Catalog",
  "Ops",
  "Dashboards",
  "Comms",
  "Transports",
  "Ground Stations",
  "Routing",
  "Validation",
  "Sign out",
]) {
  assert.ok(layoutsSource.includes(`"${label}"`), `${label} remains Phoenix-owned presentation`)
}

assert.match(sidebarPrimitives, /def nav_item\(assigns\) do/)
assert.match(sidebarPrimitives, /def nav_section\(assigns\) do/)
assert.match(sidebarPrimitives, /def section_active\?\(:ops_dashboards, :ops\), do: true/)
assert.match(sidebarPrimitives, /def section_active\?\(:comms_providers, :comms\), do: true/)

const primitiveNavItem = sourceSlice(
  sidebarPrimitives,
  "  def nav_item(assigns) do",
  "  defp item_classes(true)",
  "nav_item primitive",
)
const primitiveNavSection = sourceSlice(
  sidebarPrimitives,
  "  def nav_section(assigns) do",
  "  defp child_classes(true)",
  "nav_section primitive",
)
const presentationNavItem = sourceSlice(
  layoutsSource,
  "  defp nav_link(key, label, href, icon, active?) do",
  "  defp nav_section(key, label, icon, active?, children) do",
  "nav item presentation",
)
const presentationNavSection = sourceSlice(
  layoutsSource,
  "  defp nav_section(key, label, icon, active?, children) do",
  "  defp nav_child(key, label, href, active?) do",
  "nav section presentation",
)
const presentationNavChild = sourceSlice(
  layoutsSource,
  "  defp nav_child(key, label, href, active?) do",
  "  defp nav_item_class(true)",
  "nav child presentation",
)

const primitiveItemActive = capture(
  sidebarPrimitives,
  /defp item_classes\(true\),\s+do: "([^"]+)"/,
  "active item classes",
)
const primitiveItemInactive = capture(
  sidebarPrimitives,
  /defp item_classes\(false\),\s+do:\s+"([^"]+)"/,
  "inactive item classes",
)
const primitiveChildActive = capture(
  sidebarPrimitives,
  /defp child_classes\(true\), do: "([^"]+)"/,
  "active child classes",
)
const primitiveChildInactive = capture(
  sidebarPrimitives,
  /defp child_classes\(false\), do: "([^"]+)"/,
  "inactive child classes",
)
const primitiveDotActive = capture(
  sidebarPrimitives,
  /defp child_dot_classes\(true\), do: "([^"]+)"/,
  "active child dot classes",
)
const primitiveDotInactive = capture(
  sidebarPrimitives,
  /defp child_dot_classes\(false\), do: "([^"]+)"/,
  "inactive child dot classes",
)
const primitiveNavBase = capture(
  primitiveNavItem,
  /class=\{\["([^"]+)", item_classes/,
  "nav item base classes",
)
const primitiveSummaryBase = capture(
  primitiveNavSection,
  /<summary class=\{\["([^"]+)", item_classes/,
  "nav section summary base classes",
)
const primitiveIconBase = capture(
  primitiveNavItem,
  /class=\{\[@icon, "([^"]+)"\]\}/,
  "nav item icon classes",
)
const primitiveChildBase = capture(
  primitiveNavSection,
  /<\.link navigate=\{item\.navigate\} class=\{\["([^"]+)", child_classes/,
  "nav child base classes",
)
const primitiveDotBase = capture(
  primitiveNavSection,
  /class=\{\["([^"]+)", child_dot_classes/,
  "nav child dot base classes",
)

const canonicalClassContract = {
  "nav item active": `${primitiveNavBase} ${primitiveItemActive}`,
  "nav item inactive": `${primitiveNavBase} ${primitiveItemInactive}`,
  "nav item icon": primitiveIconBase,
  "nav item label": capture(primitiveNavItem, /<span class="([^"]+)">\{@label\}/, "nav item label"),
  "nav section details": capture(primitiveNavSection, /<details class="([^"]+)"/, "nav section details"),
  "nav section summary active": `${primitiveSummaryBase} ${primitiveItemActive}`,
  "nav section summary inactive": `${primitiveSummaryBase} ${primitiveItemInactive}`,
  "nav section icon": capture(
    primitiveNavSection,
    /class=\{\[@icon, "([^"]+)"\]\}/,
    "nav section icon",
  ),
  "nav section label": capture(
    primitiveNavSection,
    /<span class="([^"]*flex-1[^"]*)">\{@label\}/,
    "nav section label",
  ),
  "nav section chevron": capture(
    primitiveNavSection,
    /<span class="([^"]*group-open:rotate-90[^"]*)"><\/span>/,
    "nav section chevron",
  ),
  "nav section child list": capture(
    primitiveNavSection,
    /<ul class="([^"]+)"/,
    "nav section child list",
  ),
  "nav child active": `${primitiveChildBase} ${primitiveChildActive}`,
  "nav child inactive": `${primitiveChildBase} ${primitiveChildInactive}`,
  "nav child icon container": capture(
    primitiveNavSection,
    /<span class="([^"]*items-center justify-center[^"]*)">/,
    "nav child icon container",
  ),
  "nav child dot active": `${primitiveDotBase} ${primitiveDotActive}`,
  "nav child dot inactive": `${primitiveDotBase} ${primitiveDotInactive}`,
  "nav child label": capture(
    primitiveNavSection,
    /<span class="([^"]+)">\{render_slot\(item\)\}/,
    "nav child label",
  ),
}

const presentationNavBase = moduleAttribute("nav_item_base_class")
const presentationSummaryBase = `${moduleAttribute("nav_section_summary_prefix")} ${presentationNavBase}`
const presentationItemActive = moduleAttribute("nav_item_active_class")
const presentationItemInactive = moduleAttribute("nav_item_inactive_class")
const presentationChildBase = moduleAttribute("nav_child_base_class")
const presentationIconBase = capture(
  presentationNavItem,
  /"icon_class" => "#\{icon\} ([^"]+)"/,
  "presentation nav icon",
)
const presentationDotBase = capture(
  presentationNavChild,
  /"icon_class" =>\s+"([^"]+) #\{if/,
  "presentation child dot",
)
const presentationChildActive = capture(
  layoutsSource,
  /defp nav_child_class\(true\), do: "#\{@nav_child_base_class\} ([^"]+)"/,
  "presentation active child classes",
)
const presentationChildInactive = capture(
  layoutsSource,
  /defp nav_child_class\(false\),\s+do: "#\{@nav_child_base_class\} ([^"]+)"/,
  "presentation inactive child classes",
)
const presentationDotStates = presentationNavChild.match(
  /if\(active\?, do: "([^"]+)", else: "([^"]+)"\)/,
)

assert.ok(presentationDotStates, "presentation child dot states must remain source-auditable")

const presentationClassContract = {
  "nav item active": `${presentationNavBase} ${presentationItemActive}`,
  "nav item inactive": `${presentationNavBase} ${presentationItemInactive}`,
  "nav item icon": presentationIconBase,
  "nav item label": capture(
    presentationNavItem,
    /"label_class" => "([^"]+)"/,
    "presentation nav label",
  ),
  "nav section details": capture(
    presentationNavSection,
    /"details_class" => "([^"]+)"/,
    "presentation section details",
  ),
  "nav section summary active": `${presentationSummaryBase} ${presentationItemActive}`,
  "nav section summary inactive": `${presentationSummaryBase} ${presentationItemInactive}`,
  "nav section icon": capture(
    presentationNavSection,
    /"icon_class" => "#\{icon\} ([^"]+)"/,
    "presentation section icon",
  ),
  "nav section label": capture(
    presentationNavSection,
    /"label_class" => "([^"]+)"/,
    "presentation section label",
  ),
  "nav section chevron": capture(
    presentationNavSection,
    /"chevron_class" =>\s+"([^"]+)"/,
    "presentation section chevron",
  ),
  "nav section child list": capture(
    presentationNavSection,
    /"list_class" => "([^"]+)"/,
    "presentation section child list",
  ),
  "nav child active": `${presentationChildBase} ${presentationChildActive}`,
  "nav child inactive": `${presentationChildBase} ${presentationChildInactive}`,
  "nav child icon container": capture(
    presentationNavChild,
    /"icon_container_class" => "([^"]+)"/,
    "presentation child icon container",
  ),
  "nav child dot active": `${presentationDotBase} ${presentationDotStates[1]}`,
  "nav child dot inactive": `${presentationDotBase} ${presentationDotStates[2]}`,
  "nav child label": capture(
    presentationNavChild,
    /"label_class" => "([^"]+)"/,
    "presentation child label",
  ),
}

assert.deepEqual(Object.keys(presentationClassContract), Object.keys(canonicalClassContract))

for (const [surface, expected] of Object.entries(canonicalClassContract)) {
  assertSameClassTokens(presentationClassContract[surface], expected, surface)
}

const expectedSummaryBase =
  "list-none cursor-pointer flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all"
const expectedActiveSummary =
  `${expectedSummaryBase} bg-primary/10 text-primary border-primary ` +
  "shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]"
const expectedInactiveSummary =
  `${expectedSummaryBase} text-base-content/60 border-transparent ` +
  "hover:bg-primary/5 hover:text-base-content hover:border-primary/30"

assert.equal(
  presentationSummaryBase,
  expectedSummaryBase,
  "summary preserves the exact canonical class order, including its leading tokens",
)
assert.equal(primitiveSummaryBase, expectedSummaryBase, "sidebar.ex retains the frozen summary base")
assert.equal(
  presentationClassContract["nav section summary active"],
  expectedActiveSummary,
  "active summary preserves the exact canonical class contract",
)
assert.equal(
  presentationClassContract["nav section summary inactive"],
  expectedInactiveSummary,
  "inactive summary preserves the exact canonical class contract",
)
assert.equal(canonicalClassContract["nav section summary active"], expectedActiveSummary)
assert.equal(canonicalClassContract["nav section summary inactive"], expectedInactiveSummary)
assert.match(layoutsSource, /"summary_class" => nav_section_summary_class\(active\?\)/)

for (const selector of [
  ".sidebar-collapsible.sidebar-expanded",
  ".sidebar-collapsible.sidebar-collapsed",
  ".sidebar-collapsed .sidebar-label",
  ".sidebar-collapsed .sidebar-expanded-only",
  ".sidebar-collapsed:hover",
  ".sidebar-toggle-btn",
  ".sidebar-collapsed .sidebar-toggle-btn",
  ".sidebar-collapsed .sidebar-toggle-btn .toggle-chevron",
]) {
  assert.ok(sidebarCss.includes(selector), `${selector} remains in the collapse CSS contract`)
}

assert.match(router, /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/)
assert.equal(router.match(/layout: \{CadenceWeb\.Layouts, :mission_sidebar\}/g)?.length, 5)

for (const liveSession of ["mission", "spacecraft", "spacecraft_show", "catalog", "comms"]) {
  assert.match(
    router,
    new RegExp(
      `live_session :${liveSession},[\\s\\S]*?CadenceWeb\\.OrganizationAuth, :require_organization_scope[\\s\\S]*?CadenceWeb\\.MissionAuth, :load_mission[\\s\\S]*?CadenceWeb\\.UserAuth, :attach_user_menu[\\s\\S]*?layout: \\{CadenceWeb\\.Layouts, :mission_sidebar\\}`,
    ),
  )
}

assert.match(router, /delete "\/session", UserSessionController, :delete/)

const componentProps = {
  presentation: {
    root: {
      expanded_class: "sidebar-collapsible sidebar-expanded",
      collapsed_class: "sidebar-collapsible sidebar-collapsed",
    },
  },
}

const context = {
  defineProps(definition) {
    assert.equal(definition.presentation.type.name, "Object")
    assert.equal(definition.presentation.required, true)
    return componentProps
  },
  ref(value) {
    return {value}
  },
}

const testableScript =
  script.replace('import {ref} from "vue"', "const ref = globalThis.ref") +
  "\nglobalThis.missionSidebarContract = {collapsed, sidebarClass, toggleCollapsed}"

vm.runInNewContext(testableScript, context)

const behavior = context.missionSidebarContract
assert.equal(behavior.collapsed.value, false)
assert.equal(behavior.sidebarClass(), "sidebar-collapsible sidebar-expanded")
behavior.toggleCollapsed()
assert.equal(behavior.collapsed.value, true)
assert.equal(behavior.sidebarClass(), "sidebar-collapsible sidebar-collapsed")
behavior.toggleCollapsed()
assert.equal(behavior.collapsed.value, false)
assert.equal(behavior.sidebarClass(), "sidebar-collapsible sidebar-expanded")
