import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "CadenceBadge exposes only the four semantic visual tones needed by StatusBadge",
  "CadenceBadge owns the existing span element and complete base and tone class mapping",
  "StatusBadge keeps its exact status and label props with the existing info default",
  "StatusBadge keeps the exact info, ready, attention, and blocked status vocabulary",
  "StatusBadge delegates each status to CadenceBadge without adding a public wrapper",
  "StatusBadge renders labels as text through the compatibility boundary",
])
const transferredWholeFileHashOracles = Object.freeze([
  "mission_list_component_test.mjs StatusBadge frozen-source hash",
  "organization_home_test.mjs StatusBadge frozen-source hash",
])

assert.equal(process.versions.node, "24.16.0", "badge contracts use pinned Node 24.16.0")
assert.equal(scenarios.length, 6)
assert.equal(
  transferredWholeFileHashOracles.length,
  2,
  "both prior whole-file hash oracles transfer to this semantic compatibility contract",
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPaths = {
  cadenceBadge: resolve(testDirectory, "../vue/ui/components/CadenceBadge.vue"),
  statusBadge: resolve(testDirectory, "../vue/StatusBadge.vue"),
}
const dom = installDom('<div id="app"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")

const loadSfc = async (componentPath, localModules = {}) => {
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${componentPath} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${componentPath} keeps a TypeScript setup block`)
  assert.ok(parsed.descriptor.template, `${componentPath} keeps a template block`)

  const compiled = compileScript(parsed.descriptor, {
    id: `cadence-badge-${componentPath.split("/").at(-1)}`,
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

  return {
    component: loadedModule.exports.default,
    descriptor: parsed.descriptor,
    module: loadedModule.exports,
  }
}

const cadenceBadgeSfc = await loadSfc(componentPaths.cadenceBadge)
const statusBadgeSfc = await loadSfc(componentPaths.statusBadge, {
  "./ui/components/CadenceBadge.vue": cadenceBadgeSfc.module,
})
const CadenceBadge = cadenceBadgeSfc.component
const StatusBadge = statusBadgeSfc.component

assert.deepEqual(Object.keys(CadenceBadge.props).sort(), ["tone"])
assert.equal(CadenceBadge.props.tone.required, true)
assert.deepEqual(Object.keys(StatusBadge.props).sort(), ["label", "status"])
assert.equal(StatusBadge.props.status.required, true)
assert.equal(StatusBadge.props.status.default, "info")
assert.equal(StatusBadge.props.label.required, true)

const assertLiteralUnion = (source, typeName, expectedValues) => {
  const declaration = source.match(new RegExp(`type ${typeName} = ([^\\n]+)`))?.[1]

  assert.ok(declaration, `${typeName} remains source-auditable`)
  assert.deepEqual(
    [...declaration.matchAll(/"([^"]+)"/g)].map((match) => match[1]).sort(),
    [...expectedValues].sort(),
  )
}

assertLiteralUnion(cadenceBadgeSfc.descriptor.scriptSetup.content, "Tone", [
  "info",
  "success",
  "warning",
  "error",
])
assertLiteralUnion(statusBadgeSfc.descriptor.scriptSetup.content, "Status", [
  "info",
  "ready",
  "attention",
  "blocked",
])
assert.match(
  statusBadgeSfc.descriptor.scriptSetup.content,
  /^import CadenceBadge from "\.\/ui\/components\/CadenceBadge\.vue"$/m,
)
assert.equal(statusBadgeSfc.descriptor.template.content.match(/<CadenceBadge/g)?.length, 1)
assert.doesNotMatch(statusBadgeSfc.descriptor.template.content, /<span\b/)

const baseClasses =
  "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide"
const cadenceToneClasses = {
  info: "bg-info/20 text-info",
  success: "bg-success/20 text-success",
  warning: "bg-warning/20 text-warning",
  error: "bg-error/20 text-error",
}
const statusToneClasses = {
  info: cadenceToneClasses.info,
  ready: cadenceToneClasses.success,
  attention: cadenceToneClasses.warning,
  blocked: cadenceToneClasses.error,
}
const {createApp, defineComponent, h, nextTick} = integrationRequire("vue")
const RuntimeOracle = defineComponent({
  name: "CadenceBadgeRuntimeOracle",
  setup() {
    return () =>
      h("main", {id: "badge-contracts"}, [
        ...Object.entries(cadenceToneClasses).map(([tone, classes]) =>
          h(
            CadenceBadge,
            {id: `cadence-badge-${tone}`, tone, "data-expected-classes": classes},
            {default: () => `${tone} primitive`},
          ),
        ),
        ...Object.keys(statusToneClasses).map((status) =>
          h(StatusBadge, {
            id: `status-badge-${status}`,
            status,
            label: `${status} status`,
          }),
        ),
        h(StatusBadge, {
          id: "status-badge-default",
          status: undefined,
          label: "<default & safe>",
        }),
      ])
  },
})

const app = createApp(RuntimeOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const root = dom.window.document.querySelector("#badge-contracts")
assert.equal(root.children.length, 9)

for (const [tone, toneClasses] of Object.entries(cadenceToneClasses)) {
  const badge = dom.window.document.querySelector(`#cadence-badge-${tone}`)

  assert.equal(badge.tagName, "SPAN")
  assert.equal(badge.className, `${baseClasses} ${toneClasses}`)
  assert.equal(badge.textContent, `${tone} primitive`)
  assert.equal(badge.getAttribute("data-expected-classes"), toneClasses)
}

for (const [status, toneClasses] of Object.entries(statusToneClasses)) {
  const badge = dom.window.document.querySelector(`#status-badge-${status}`)

  assert.equal(badge.tagName, "SPAN")
  assert.equal(badge.className, `${baseClasses} ${toneClasses}`)
  assert.equal(badge.textContent, `${status} status`)
}

const defaultBadge = dom.window.document.querySelector("#status-badge-default")
assert.equal(defaultBadge.tagName, "SPAN")
assert.equal(defaultBadge.className, `${baseClasses} ${cadenceToneClasses.info}`)
assert.equal(defaultBadge.textContent, "<default & safe>")
assert.equal(defaultBadge.innerHTML, "&lt;default &amp; safe&gt;")
assert.doesNotThrow(() => app.unmount())
