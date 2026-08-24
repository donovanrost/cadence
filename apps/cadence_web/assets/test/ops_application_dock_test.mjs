import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = [
  "the shared layout remains the sole caller and omits the complete dock for an empty surface list",
  "one distinct non-SSR LiveVue host owns the complete public dock DOM",
  "Phoenix projects every public id, attribute, class, label, and message through one DTO",
  "the public details remains open and retains its summary, navigation, chevron, and panel topology",
  "surface input order is retained and only the first supplied tab is selected",
  "tab ids keep the original dom_id replacement without collapsing unusual characters",
  "tab button attributes and selected or inactive class branches remain exact",
  "Vue binds the DTO without adding state, events, tab switching, or presentation defaults",
  "the OpsDock struct, resolution order, registry, shell authority, and existing empty oracle stay pinned",
  "the authenticated scope and all three shared-layout Ops live sessions stay pinned",
]

assert.equal(process.versions.node, "24.16.0", "dock contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 10)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const paths = {
  vue: resolve(testDirectory, "../vue/OpsApplicationDock.vue"),
  component: resolve(
    testDirectory,
    "../../lib/cadence_web/components/ops_application_dock.ex",
  ),
  caller: resolve(testDirectory, "../../lib/cadence_web/components/layouts/ops.html.heex"),
  router: resolve(testDirectory, "../../lib/cadence_web/router.ex"),
  struct: resolve(
    testDirectory,
    "../../../cadence/lib/cadence/applications/ops_dock_surface.ex",
  ),
  resolver: resolve(testDirectory, "../../../cadence/lib/cadence/applications/ops_dock.ex"),
  registry: resolve(testDirectory, "../../../cadence/lib/cadence/applications/registry.ex"),
  shellHook: resolve(testDirectory, "../../lib/cadence_web/live/ops_shell_hook.ex"),
  loader: resolve(testDirectory, "../vue/index.ts"),
  existingOracle: resolve(
    testDirectory,
    "../../test/cadence_web/live/ops_navigation_live_test.exs",
  ),
  componentTest: resolve(
    testDirectory,
    "../../test/cadence_web/components/ops_application_dock_test.exs",
  ),
}

const sourceEntries = await Promise.all(
  Object.entries(paths).map(async ([name, path]) => [name, await readFile(path, "utf8")]),
)
const source = Object.fromEntries(sourceEntries)

const sourceSlice = (value, start, end, label) => {
  const startIndex = value.indexOf(start)
  const endIndex = value.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return value.slice(startIndex, endIndex)
}

const assertBalancedTemplate = (template) => {
  const stack = []
  const voidElements = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta"])

  for (const match of template.matchAll(/<\/?([a-z][\w-]*)(?:\s[^<>]*?)?>/gs)) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "OpsApplicationDock SFC tags are balanced")
}

// The caller and existing empty-surface oracle remain exact.
assert.equal(source.caller.match(/<\.ops_application_dock\b/g)?.length, 1)
assert.match(source.caller, /:if=\{\(assigns\[:ops_dock_surfaces\] \|\| \[\]\) != \[\]\}/)
assert.match(source.caller, /surfaces=\{assigns\[:ops_dock_surfaces\] \|\| \[\]\}/)

const innerContentIndex = source.caller.indexOf("{@inner_content}")
const dockCallerIndex = source.caller.indexOf("<.ops_application_dock")
const contextRailIndex = source.caller.indexOf("<.mission_context_rail")

assert.ok(innerContentIndex < dockCallerIndex, "dock remains after inner content")
assert.ok(dockCallerIndex < contextRailIndex, "dock remains before the mission context rail")
assert.match(
  source.existingOracle,
  /refute has_element\?\(view, "#ops-application-dock"\)/,
)

// Phoenix retains the struct contract, application admission, ordering, and shell assign authority.
assert.match(source.struct, /@type t :: %__MODULE__\{/)
assert.match(source.struct, /id: binary\(\)/)
assert.match(source.struct, /application_key: binary\(\)/)
assert.match(source.struct, /surface_definition: SurfaceDefinition\.t\(\)/)
assert.match(source.struct, /label: binary\(\)/)
assert.match(source.struct, /order: integer\(\)/)
assert.match(source.resolver, /Enum\.sort_by\(&\{&1\.order, &1\.application_name, &1\.id\}\)/)
assert.match(
  source.registry,
  /surface\.scope == scope and surface\.placement == :ops_dock/,
)
assert.match(source.shellHook, /\|> refresh_ops_dock\(\)/)
assert.match(source.shellHook, /assign\(socket, :ops_dock_surfaces, surfaces\)/)
assert.match(source.loader, /import\.meta\.glob\("\.\/\*\*\/\*\.vue", \{eager: true\}\)/)

// The component is one passive LiveVue boundary and the server owns the presentation.
assert.equal(
  source.component.match(/<\.vue\b/g)?.length,
  1,
  "the complete dock emits one LiveVue host",
)
assert.match(source.component, /id="ops-application-dock-component"/)
assert.match(source.component, /v-component="OpsApplicationDock"/)
assert.match(source.component, /presentation=\{@presentation\}/)
assert.match(source.component, /v-ssr=\{false\}/)
assert.match(source.component, /class="contents"/)
assert.doesNotMatch(source.component, /<details\b|<summary\b|<nav\b|<button\b|<\.icon\b/)
assert.match(source.component, /def presentation\(surfaces\) when is_list\(surfaces\)/)
assert.match(source.component, /surfaces\s*\n\s*\|> Enum\.with_index\(\)/)
assert.match(source.component, /selected\? = index == 0/)
assert.match(source.component, /"aria-selected" => to_string\(selected\?\)/)
assert.match(source.component, /String\.replace\(id, ~r\/\[\^a-zA-Z0-9_-\]\/, "-"\)/)
assert.match(source.component, /\{_name, value\}, rendered when value in \[nil, false\]/)
assert.match(source.component, /\{name, true\}, rendered ->\s*Map\.put\(rendered, name, ""\)/s)
assert.match(source.component, /\{name, value\}, rendered ->\s*Map\.put\(rendered, name, to_string\(value\)\)/s)

for (const exactServerValue of [
  "ops-application-dock",
  "group shrink-0 border-t border-primary/25 bg-base-200/80",
  "Operations dock",
  "Application dock surfaces",
  "hero-chevron-down size-4 text-base-content/45 transition-transform group-open:rotate-180",
  "ops-dock-surface-host",
  "The application surface is registered with the Ops host.",
]) {
  assert.ok(source.component.includes(exactServerValue), `${exactServerValue} remains server-owned`)
}

const script = source.vue.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.vue.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "OpsApplicationDock.vue has a script setup contract")
assert.ok(template, "OpsApplicationDock.vue has a template contract")
new vm.Script(script, {filename: paths.vue})
assertBalancedTemplate(template)
assert.match(script, /presentation: \{type: Object, required: true\}/)
assert.doesNotMatch(
  source.vue,
  /defineEmits|\bemit\(|\bref\(|\breactive\(|\bcomputed\(|\bwatch\(|v-model|@[\w:-]+=|addEventListener|querySelector/,
)
assert.doesNotMatch(
  source.vue,
  /Operations dock|Application dock surfaces|ops-application-dock|ops-dock-tab|ops-dock-surface-host|hero-chevron-down|registered with the Ops host/,
)

const orderedBindings = [
  'v-bind="presentation.root.attrs"',
  ':class="presentation.root.class"',
  ':class="presentation.summary.class"',
  ':class="presentation.label.class"',
  "{{ presentation.label.text }}",
  'v-bind="presentation.navigation.attrs"',
  ':class="presentation.navigation.class"',
  'v-for="tab in presentation.navigation.tabs"',
  ':key="tab.key"',
  'v-bind="tab.attrs"',
  ':class="tab.class"',
  "{{ tab.label }}",
  ':class="presentation.chevron.class"',
  'v-bind="presentation.panel.attrs"',
  ':class="presentation.panel.class"',
  ':class="presentation.panel.message.class"',
  "{{ presentation.panel.message.text }}",
]

let previousBindingIndex = -1
for (const binding of orderedBindings) {
  const index = template.indexOf(binding, previousBindingIndex + 1)
  assert.ok(index > previousBindingIndex, `${binding} preserves the DTO-to-DOM order`)
  previousBindingIndex = index
}

assert.equal(template.match(/^  <details\b/gm)?.length, 1, "the SFC has one root details element")
assert.equal(template.match(/<summary\b/g)?.length, 1)
assert.equal(template.match(/<nav\b/g)?.length, 1)
assert.equal(template.match(/<button\b/g)?.length, 1)

// The new focused tests pin the exact boundary and unusual-id presentation cases.
for (const scenario of [
  "emits one non-SSR LiveVue host with the exact dock chrome presentation",
  "presentation preserves input order, first-tab selection, unusual ids, and JSON totality",
]) {
  assert.equal(
    source.componentTest.split(`test "${scenario}"`).length - 1,
    1,
    `focused Elixir scenario remains named exactly once: ${scenario}`,
  )
}
assert.match(source.componentTest, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(source.componentTest, /ops-dock-tab-install-beta-surface--two/)

// All Ops routes remain inside the existing authenticated scope and shared layout sessions.
assert.match(
  source.router,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const authorSession = sourceSlice(
  source.router,
  "live_session :ops_dashboard_author",
  "live_session :ops,",
  "ops dashboard author session",
)
const opsSession = sourceSlice(
  source.router,
  "live_session :ops,",
  "live_session :ops_admin",
  "ops viewer session",
)
const adminSession = sourceSlice(
  source.router,
  "live_session :ops_admin",
  "# Legacy application URLs redirect",
  "ops admin session",
)

for (const session of [authorSession, opsSession, adminSession]) {
  assert.match(session, /\{CadenceWeb\.OrganizationAuth, :require_organization_scope\}/)
  assert.match(session, /\{CadenceWeb\.MissionAuth, :load_mission\}/)
  assert.match(session, /\{CadenceWeb\.UserAuth, :attach_user_menu\}/)
  assert.match(session, /\{CadenceWeb\.OpsShellHook, :default\}/)
  assert.match(session, /layout: \{CadenceWeb\.Layouts, :ops\}/)
}

assert.match(authorSession, /\{CadenceWeb\.DashboardAuthorAuth, :require_dashboard_author\}/)
assert.doesNotMatch(opsSession, /DashboardAuthorAuth|require_organization_admin/)
assert.match(adminSession, /\{CadenceWeb\.OrganizationAuth, :require_organization_admin\}/)

console.log("ops_application_dock_test passed")
