import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = [
  "Phoenix keeps the drawer input, drawer content, responsive account chrome, inner content, and LiveToast",
  "one non-SSR LiveVue host carries drawer-side and owns the complete global sidebar surface",
  "the Vue fragment renders the overlay and sidebar surface as the host's ordered direct children",
  "Phoenix projects admin, organization, and fallback navigation branches with exact active states",
  "Phoenix alone derives organization copy and provider-account visibility",
  "every header and navigation anchor preserves Phoenix redirect navigation attrs and routes",
  "the sign-out form preserves POST tunneling, DELETE intent, CSRF, and submit attrs",
  "raw attrs preserve HEEx omission, valueless true, string, and number semantics",
  "collapse starts expanded and toggles only Vue-local reactive state",
  "legacy drawer classes, the retired Sidebar.nav_item class contract, DaisyUI topology, CSS, and router ownership stay pinned",
]

assert.equal(process.versions.node, "24.16.0", "global sidebar contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 10)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/GlobalSidebarNavigation.vue")
const layoutTemplatePath = resolve(
  __dirname,
  "../../lib/cadence_web/components/layouts/sidebar.html.heex",
)
const layoutsPath = resolve(__dirname, "../../lib/cadence_web/components/layouts.ex")
const layoutsTestPath = resolve(
  __dirname,
  "../../test/cadence_web/components/layouts_test.exs",
)
const sidebarPrimitivesPath = resolve(
  __dirname,
  "../../lib/cadence_web/components/sidebar.ex",
)
const legacyDrawerPath = resolve(__dirname, "global_sidebar_drawer_side_legacy.txt")
const sidebarCssPath = resolve(__dirname, "../css/components/sidebar.css")
const daisyUiPath = resolve(__dirname, "../vendor/daisyui.js")
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [
  componentSource,
  layoutTemplate,
  layoutsSource,
  layoutsTestSource,
  sidebarPrimitives,
  legacyDrawer,
  sidebarCss,
  daisyUi,
  router,
] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(layoutTemplatePath, "utf8"),
  readFile(layoutsPath, "utf8"),
  readFile(layoutsTestPath, "utf8"),
  readFile(sidebarPrimitivesPath, "utf8"),
  readFile(legacyDrawerPath, "utf8"),
  readFile(sidebarCssPath, "utf8"),
  readFile(daisyUiPath, "utf8"),
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
  assert.deepEqual(classTokens(actual), classTokens(expected), `${label} class tokens remain exact`)

const assertBalancedTemplate = (source) => {
  const stack = []
  const voidElements = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta"])
  const tags = source.matchAll(/<\/?([a-z][\w-]*)(?:\s[^<>]*?)?>/gs)

  for (const match of tags) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "SFC template tags are balanced")
}

assert.equal(
  createHash("sha256").update(legacyDrawer).digest("hex"),
  "1cc667679fbe56eb20e5718cb81b0c8cea5dd68f581390991bf04fde86b51fb1",
  "the pre-migration drawer-side source remains pinned",
)

const script = componentSource.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = componentSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "GlobalSidebarNavigation.vue must have a script setup block")
assert.ok(template, "GlobalSidebarNavigation.vue must have a template block")
assertBalancedTemplate(template)

assert.equal(layoutTemplate.match(/<\.vue/g)?.length, 1)
assert.match(layoutTemplate, /id="global-sidebar-navigation"/)
assert.match(layoutTemplate, /v-component="GlobalSidebarNavigation"/)
assert.match(layoutTemplate, /presentation=\{global_sidebar_navigation_presentation\(assigns\)\}/)
assert.match(layoutTemplate, /v-ssr=\{false\}/)
assert.match(layoutTemplate, /class="drawer-side"/)
assert.doesNotMatch(layoutTemplate, /<div class="drawer-side"/)
assert.doesNotMatch(layoutTemplate, /class="contents"/)

assert.match(layoutTemplate, /<div class="drawer lg:drawer-open">/)
assert.match(layoutTemplate, /<input id="sidebar-drawer" type="checkbox" class="drawer-toggle" \/>/)
assert.match(layoutTemplate, /<div class="drawer-content flex flex-col">/)
assert.match(layoutTemplate, /id="notifications-bell-mobile"/)
assert.match(layoutTemplate, /id="notifications-bell-desktop"/)
assert.match(layoutTemplate, /id="user-menu-mobile"/)
assert.match(layoutTemplate, /id="user-menu-desktop"/)
assert.match(layoutTemplate, /<main class="flex-1 overflow-y-auto bg-base-100">/)
assert.match(layoutTemplate, /\{@inner_content\}/)
assert.match(layoutTemplate, /<LiveToast\.toast_group/)

const drawerStart = layoutTemplate.indexOf('  <.vue\n    id="global-sidebar-navigation"')
const drawerEnd = layoutTemplate.indexOf("\n  />", drawerStart)
const drawerHostSource = layoutTemplate.slice(drawerStart, drawerEnd)

assert.ok(drawerStart >= 0 && drawerEnd > drawerStart, "drawer-side host must remain auditable")
assert.equal(drawerHostSource.match(/<\.vue/g)?.length, 1)
assert.match(drawerHostSource, /class="drawer-side"/)
assert.doesNotMatch(drawerHostSource, /<label|<nav|<\.nav_item|<\.form|onclick=/)
assert.doesNotMatch(drawerHostSource, /for=|aria-label=|href=|data-sidebar|title=/)
assert.doesNotMatch(layoutTemplate, /document\.querySelectorAll|classList\.toggle|phx-hook=/)

const renderGlobalSidebarTestHelper = sourceSlice(
  layoutsTestSource,
  "  defp render_global_sidebar",
  "\n  end\nend",
  "global sidebar LiveVue.Test helper",
)

assert.match(
  renderGlobalSidebarTestHelper,
  /then\(fn merged_assigns -> render_component\(&Layouts\.sidebar\/1, merged_assigns\) end\)/,
)
assert.doesNotMatch(renderGlobalSidebarTestHelper, /then\(&render_component/)

assert.match(daisyUi, /"> \.drawer-overlay": \{/)
assert.match(daisyUi, /"> \*:not\(\.drawer-overlay\)": \{/)

assert.match(script, /import \{ref\} from "vue"/)
assert.match(script, /presentation: \{type: Object, required: true\}/)
assert.match(script, /const collapsed = ref\(false\)/)
assert.match(script, /const sidebarClass = \(\) =>/)
assert.match(script, /collapsed\.value = !collapsed\.value/)
assert.doesNotMatch(
  script,
  /document|querySelector|querySelectorAll|localStorage|sessionStorage|addEventListener|MutationObserver/,
)

const topLevelElements = template
  .split("\n")
  .filter((line) => /^  <[a-z]/.test(line))
  .map((line) => capture(line, /^  <([a-z][\w-]*)/, "top-level Vue element"))

assert.deepEqual(topLevelElements, ["label", "div"])
assert.ok(template.indexOf("props.presentation.overlay") < template.indexOf("sidebarClass()"))
assert.ok(template.indexOf("props.presentation.header") < template.indexOf("props.presentation.navigation"))
assert.ok(template.indexOf("props.presentation.navigation") < template.indexOf("props.presentation.sign_out"))
assert.ok(template.indexOf("props.presentation.sign_out") < template.indexOf("props.presentation.collapse"))

assert.match(template, /v-bind="props\.presentation\.overlay\.attrs"/)
assert.match(template, /:class="sidebarClass\(\)"/)
assert.match(template, /v-bind="props\.presentation\.root\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.header\.link\.attrs"/)
assert.match(template, /v-if="props\.presentation\.navigation\.section"/)
assert.match(template, /v-for="item in props\.presentation\.navigation\.items"/)
assert.match(template, /v-bind="item\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.sign_out\.form\.attrs"/)
assert.match(template, /props\.presentation\.sign_out\.form\.hidden_fields/)
assert.match(template, /v-bind="field\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.sign_out\.form\.button\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.collapse\.attrs"/)
assert.match(template, /@click="toggleCollapsed"/)
assert.doesNotMatch(
  componentSource,
  /\/admin|\/missions|\/provider-accounts|\/session|Dashboard|Organizations|Runtime|Provider Accounts|Sign out|CADENCE/,
)

const globalPresentationSource = sourceSlice(
  layoutsSource,
  "  defp global_sidebar_navigation_presentation(assigns) do",
  "  defp mission_sidebar_navigation_presentation(assigns) do",
  "global sidebar presentation",
)

for (const route of [
  "/",
  "/admin",
  "/admin/organizations",
  "/admin/runtime",
  "/missions",
  "/provider-accounts",
]) {
  assert.ok(globalPresentationSource.includes(`~p"${route}"`), `${route} remains server-generated`)
}

for (const [label, icon] of [
  ["Dashboard", "hero-chart-bar-square"],
  ["Organizations", "hero-building-office"],
  ["Runtime", "hero-signal"],
  ["Home", "hero-home"],
  ["Missions", "hero-rocket-launch"],
  ["Provider Accounts", "hero-globe-alt"],
]) {
  assert.ok(globalPresentationSource.includes(`"${label}"`), `${label} remains Phoenix-owned`)
  assert.ok(globalPresentationSource.includes(`"${icon}"`), `${icon} remains Phoenix-owned`)
}

for (const navItem of [
  "admin_dashboard",
  "admin_organizations",
  "admin_runtime",
  "organization_home",
  "missions",
  "provider_accounts",
]) {
  assert.ok(
    globalPresentationSource.includes(`nav_item == :${navItem}`),
    `${navItem} remains Phoenix-derived`,
  )
}

for (const label of ["CADENCE", "Administration", "Organization"]) {
  assert.ok(layoutsSource.includes(`"${label}"`), `${label} remains Phoenix-owned`)
}

assert.match(globalPresentationSource, /assigns\[:nav_context\]/)
assert.match(globalPresentationSource, /assigns\[:current_scope\]/)
assert.match(globalPresentationSource, /assigns\[:nav_item\]/)
assert.match(globalPresentationSource, /defp global_navigation_presentation\(:admin, _scope, nav_item\)/)
assert.match(globalPresentationSource, /defp global_navigation_presentation\(:organization, scope, nav_item\)/)
assert.match(globalPresentationSource, /provider_accounts_visible\?\(scope\)/)
assert.match(globalPresentationSource, /"provider-accounts-nav-link"/)
assert.match(globalPresentationSource, /defp global_navigation_presentation\(_nav_context, _scope, _nav_item\)/)
assert.match(globalPresentationSource, /do: global_navigation_presentation\(nil, \[\]\)/)

assert.match(globalPresentationSource, /"data-phx-link" => "redirect"/)
assert.match(globalPresentationSource, /"data-phx-link-state" => "push"/)
assert.match(globalPresentationSource, /"href" => href/)
assert.match(globalPresentationSource, /"sign_out" => sign_out_presentation\(\)/)
assert.match(layoutsSource, /Plug\.CSRFProtection\.get_csrf_token_for\(~p"\/session"\)/)
assert.match(layoutsSource, /"action" => ~p"\/session"/)
assert.match(layoutsSource, /"method" => "post"/)
assert.match(layoutsSource, /"name" => "_method", "type" => "hidden", "value" => "delete"/)
assert.match(layoutsSource, /"name" => "_csrf_token"/)
assert.match(layoutsSource, /"attrs" => %\{"type" => "submit"\}/)

const rawAttrsSource = sourceSlice(
  layoutsSource,
  "  defp raw_attrs(attrs) do",
  "  defp provider_accounts_visible?",
  "raw attribute semantics",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)
assert.match(globalPresentationSource, /raw_attrs\(%\{"data-sidebar-collapsible" => true\}\)/)
assert.match(globalPresentationSource, /global_navigate_attrs\(href, %\{"id" => id\}\)/)

const expectedLegacyStaticClasses = [
  "drawer-side",
  "drawer-overlay",
  "sidebar-collapsible sidebar-expanded min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative",
  "px-3 h-10 flex items-center border-b border-primary/20",
  "flex items-center gap-2",
  "text-primary font-bold text-sm",
  "text-xs font-bold tracking-[0.15em] text-primary sidebar-label",
  "flex-1 overflow-y-auto py-2",
  "px-3 mb-2 sidebar-expanded-only",
  "hud-label",
  "menu menu-sm space-y-0.5",
  "px-2 py-2 border-t border-primary/20",
  "w-full",
  "btn btn-ghost btn-sm w-full justify-start gap-2 text-xs uppercase tracking-wide text-base-content/60",
  "hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80",
  "sidebar-label",
  "sidebar-toggle-btn hidden lg:flex",
  "hero-chevron-left h-3 w-3 toggle-chevron transition-transform",
]

const legacyStaticClasses = [
  ...new Set([...legacyDrawer.matchAll(/\bclass="([^"]+)"/g)].map((match) => match[1])),
]

assert.deepEqual(legacyStaticClasses, expectedLegacyStaticClasses)

for (const className of legacyStaticClasses) {
  const owner = className === "drawer-side" ? layoutTemplate : layoutsSource
  assert.ok(owner.includes(`"${className}"`), `${className} remains presentation-owned`)
}

assert.match(
  globalPresentationSource,
  /"collapsed_class" =>[\s\S]*?"sidebar-collapsible sidebar-collapsed min-h-full bg-base-200 flex flex-col border-r border-primary\/20 hud-grid relative"/,
)

const globalNavItem = sourceSlice(
  layoutsSource,
  "  defp global_nav_link(",
  "  defp global_navigate_attrs",
  "global nav item presentation",
)

const retiredNavItemClassContract = {
  base: "flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all",
  active:
    "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]",
  inactive:
    "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30",
  icon: "h-4 w-4 opacity-80 flex-shrink-0",
  label: "sidebar-label",
}

assert.doesNotMatch(sidebarPrimitives, /def nav_item\(assigns\) do/)
assertSameClassTokens(
  moduleAttribute("nav_item_base_class"),
  retiredNavItemClassContract.base,
  "nav item base",
)
assertSameClassTokens(
  moduleAttribute("nav_item_active_class"),
  retiredNavItemClassContract.active,
  "active nav item",
)
assertSameClassTokens(
  moduleAttribute("nav_item_inactive_class"),
  retiredNavItemClassContract.inactive,
  "inactive nav item",
)
assert.equal(
  capture(globalNavItem, /"icon_class" => "#\{icon\} ([^"]+)"/, "global nav icon classes"),
  retiredNavItemClassContract.icon,
)
assert.equal(
  capture(globalNavItem, /"label_class" => "([^"]+)"/, "global nav label classes"),
  retiredNavItemClassContract.label,
)
assert.match(globalNavItem, /"class" => nav_item_class\(active\?\)/)

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
assert.equal(router.match(/layout: \{CadenceWeb\.Layouts, :sidebar\}/g)?.length, 3)

const organizationSession = sourceSlice(
  router,
  "    live_session :organization,",
  "    live_session :provider_accounts,",
  "organization LiveSession",
)
const providerAccountsSession = sourceSlice(
  router,
  "    live_session :provider_accounts,",
  "    live_session :mission,",
  "provider accounts LiveSession",
)
const adminSession = sourceSlice(
  router,
  "    live_session :admin,",
  "  end\n\n  scope \"/api\", CadenceWeb do",
  "admin LiveSession",
)

assert.match(organizationSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(organizationSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(organizationSession, /layout: \{CadenceWeb\.Layouts, :sidebar\}/)
assert.doesNotMatch(organizationSession, /require_organization_admin|require_platform_admin/)

assert.match(providerAccountsSession, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(providerAccountsSession, /CadenceWeb\.OrganizationAuth, :require_organization_admin/)
assert.match(providerAccountsSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(providerAccountsSession, /layout: \{CadenceWeb\.Layouts, :sidebar\}/)

assert.match(adminSession, /CadenceWeb\.AdminAuth, :require_platform_admin/)
assert.match(adminSession, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(adminSession, /layout: \{CadenceWeb\.Layouts, :sidebar\}/)
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
  "\nglobalThis.globalSidebarContract = {collapsed, sidebarClass, toggleCollapsed}"

vm.runInNewContext(testableScript, context)

const behavior = context.globalSidebarContract
assert.equal(behavior.collapsed.value, false)
assert.equal(behavior.sidebarClass(), "sidebar-collapsible sidebar-expanded")
behavior.toggleCollapsed()
assert.equal(behavior.collapsed.value, true)
assert.equal(behavior.sidebarClass(), "sidebar-collapsible sidebar-collapsed")
behavior.toggleCollapsed()
assert.equal(behavior.collapsed.value, false)
assert.equal(behavior.sidebarClass(), "sidebar-collapsible sidebar-expanded")
