import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {
  diagnosticsSectionHeaderClass,
  diagnosticsSectionRootClass,
} from "./diagnostics_section_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the compiled SFC renders exactly one native section with one direct native header",
  "root attributes, listeners, and directives stay on the native section",
  "header and content arrays and Fragments flatten without wrapper or text nodes",
  "caller-owned content, controls, values, payloads, listeners, and directives remain native",
  "keyed section, header, content, and control identity survives reordering and updates",
  "the frame output remains byte-equivalent to the native section and header oracle",
])

assert.equal(process.versions.node, "24.16.0", "expected pinned Node 24.16.0")
assert.equal(scenarios.length, 6)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceDiagnosticsSectionFrame.vue",
)
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="primitive-host"></div><div id="native-host"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceDiagnosticsSectionFrame parses")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function script")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)

const compiled = compileScript(parsed.descriptor, {
  id: "cadence-diagnostics-section-frame-contract",
})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
new Function("require", "module", "exports", transformed.code)(
  integrationRequire,
  loadedModule,
  loadedModule.exports,
)
const CadenceDiagnosticsSectionFrame = loadedModule.exports.default

assert.equal(CadenceDiagnosticsSectionFrame.inheritAttrs, false)
assert.deepEqual(Object.keys(CadenceDiagnosticsSectionFrame.props ?? {}), [])
assert.deepEqual(Object.keys(CadenceDiagnosticsSectionFrame.emits ?? {}), [])
assert.equal(source.match(/h\("section"/g)?.length, 1)
assert.equal(source.match(/h\("header"/g)?.length, 1)
assert.equal(source.split(diagnosticsSectionRootClass).length - 1, 1)
assert.equal(source.split(diagnosticsSectionHeaderClass).length - 1, 1)
assert.match(source, /child\.type === Fragment/)
assert.doesNotMatch(
  source,
  /CadencePanel|<template|<style|defineProps|defineEmits|\b(?:ref|reactive|computed|watch|onMounted)\s*\(|<form|<button|href/,
)

const {
  Fragment,
  createApp,
  defineComponent,
  h,
  nextTick,
  ref,
  withDirectives,
} = integrationRequire("vue")
const frames = ref([
  {key: "alpha", label: "Alpha", phase: "ready"},
  {key: "bravo", label: "Bravo", phase: "warning"},
])
const rootClicks = []
const controlClicks = []
const formSubmits = []

const rootDirective = {
  mounted(element, binding) {
    element.setAttribute("data-root-directive", binding.value)
  },
  updated(element, binding) {
    element.setAttribute("data-root-directive", binding.value)
  },
}
const controlDirective = {
  mounted(element, binding) {
    element.setAttribute("data-control-directive", binding.value)
  },
  updated(element, binding) {
    element.setAttribute("data-control-directive", binding.value)
  },
}

const rootAttributes = (frame, target) => ({
  key: frame.key,
  id: `diagnostics-${frame.key}`,
  role: "region",
  "aria-live": "polite",
  "aria-label": `${frame.label} diagnostics`,
  "data-owner": "caller",
  "data-phase": frame.phase,
  onClick: () => rootClicks.push(`${target}:${frame.key}`),
})

const headerChildren = (frame, target) => [
  h(Fragment, null, [
    [
      h("div", {key: "copy", id: `copy-${frame.key}`}, [
        `${frame.label} `,
        h("span", {id: `count-${frame.key}`}, "2"),
      ]),
      h(Fragment, null, [
        withDirectives(
          h(
            "button",
            {
              key: "control",
              id: `control-${frame.key}`,
              type: "button",
              name: "diagnostic_intent",
              value: frame.phase,
              "data-payload": `${frame.key}:${frame.phase}`,
              onClick: () => controlClicks.push(`${target}:${frame.key}`),
            },
            `Inspect ${frame.label}`,
          ),
          [[controlDirective, `${frame.key}:${frame.phase}`]],
        ),
      ]),
    ],
  ]),
]

const bodyChildren = (frame, target) => [
  h(Fragment, null, [
    h(
      "article",
      {
        key: "content",
        id: `content-${frame.key}`,
        "data-diagnostic-code": `${frame.key}.code`,
      },
      `${frame.label} content`,
    ),
    [
      h(
        "form",
        {
          key: "form",
          id: `form-${frame.key}`,
          action: `/diagnostics/${frame.key}`,
          method: "post",
          onSubmit: (event) => {
            event.preventDefault()
            formSubmits.push(`${target}:${frame.key}`)
          },
        },
        [h("input", {type: "hidden", name: "phase", value: frame.phase})],
      ),
    ],
  ]),
]

const renderFrame = (frame, target, primitive) => {
  if (primitive) {
    return withDirectives(
      h(CadenceDiagnosticsSectionFrame, rootAttributes(frame, target), {
        header: () => headerChildren(frame, target),
        default: () => bodyChildren(frame, target),
      }),
      [[rootDirective, `${frame.key}:${frame.phase}`]],
    )
  }

  return withDirectives(
    h(
      "section",
      {...rootAttributes(frame, target), class: diagnosticsSectionRootClass},
      [
        h("header", {class: diagnosticsSectionHeaderClass}, headerChildren(frame, target)),
        ...bodyChildren(frame, target),
      ],
    ),
    [[rootDirective, `${frame.key}:${frame.phase}`]],
  )
}

const contract = (name, target, primitive) =>
  defineComponent({
    name,
    setup() {
      return () => h("div", frames.value.map((frame) => renderFrame(frame, target, primitive)))
    },
  })

const primitiveHost = dom.window.document.querySelector("#primitive-host")
const nativeHost = dom.window.document.querySelector("#native-host")
const primitiveApp = createApp(contract("DiagnosticsFramePrimitiveOracle", "primitive", true))
const nativeApp = createApp(contract("DiagnosticsFrameNativeOracle", "native", false))
primitiveApp.mount(primitiveHost)
nativeApp.mount(nativeHost)
await flushVue(nextTick)

const normalizeOracleHtml = (html) => html
assert.equal(normalizeOracleHtml(primitiveHost.innerHTML), normalizeOracleHtml(nativeHost.innerHTML))

const primitiveList = primitiveHost.firstElementChild
const alphaSection = primitiveList.querySelector("#diagnostics-alpha")
const bravoSection = primitiveList.querySelector("#diagnostics-bravo")
const alphaHeader = alphaSection.firstElementChild
const alphaContent = alphaSection.querySelector("#content-alpha")
const alphaControl = alphaSection.querySelector("#control-alpha")
const alphaForm = alphaSection.querySelector("#form-alpha")

assert.equal(alphaSection.tagName, "SECTION")
assert.equal(alphaHeader.tagName, "HEADER")
assert.equal(alphaSection.children.length, 3)
assert.deepEqual([...alphaSection.children].map(({tagName}) => tagName), [
  "HEADER",
  "ARTICLE",
  "FORM",
])
assert.deepEqual([...alphaHeader.children].map(({tagName}) => tagName), ["DIV", "BUTTON"])
assert.equal(alphaSection.getAttribute("class"), diagnosticsSectionRootClass)
assert.equal(alphaHeader.getAttribute("class"), diagnosticsSectionHeaderClass)
assert.deepEqual(elementAttributes(alphaSection), {
  "aria-label": "Alpha diagnostics",
  "aria-live": "polite",
  class: diagnosticsSectionRootClass,
  "data-owner": "caller",
  "data-phase": "ready",
  "data-root-directive": "alpha:ready",
  id: "diagnostics-alpha",
  role: "region",
})
assert.deepEqual(elementAttributes(alphaControl), {
  "data-control-directive": "alpha:ready",
  "data-payload": "alpha:ready",
  id: "control-alpha",
  name: "diagnostic_intent",
  type: "button",
  value: "ready",
})

alphaControl.click()
assert.deepEqual(controlClicks, ["primitive:alpha"])
assert.deepEqual(rootClicks, ["primitive:alpha"])
const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(alphaForm.dispatchEvent(submitEvent), false)
assert.deepEqual(formSubmits, ["primitive:alpha"])

frames.value = [
  {key: "bravo", label: "Bravo updated", phase: "ready"},
  {key: "alpha", label: "Alpha updated", phase: "error"},
]
await flushVue(nextTick)

assert.equal(primitiveHost.innerHTML, nativeHost.innerHTML)
assert.deepEqual([...primitiveList.children].map(({id}) => id), [
  "diagnostics-bravo",
  "diagnostics-alpha",
])
const updatedAlphaSection = primitiveList.querySelector("#diagnostics-alpha")
assert.strictEqual(updatedAlphaSection, alphaSection)
assert.strictEqual(primitiveList.querySelector("#diagnostics-bravo"), bravoSection)
assert.strictEqual(updatedAlphaSection.firstElementChild, alphaHeader)
assert.strictEqual(updatedAlphaSection.querySelector("#content-alpha"), alphaContent)
assert.strictEqual(updatedAlphaSection.querySelector("#control-alpha"), alphaControl)
assert.strictEqual(updatedAlphaSection.querySelector("#form-alpha"), alphaForm)
assert.equal(updatedAlphaSection.getAttribute("data-phase"), "error")
assert.equal(updatedAlphaSection.getAttribute("data-root-directive"), "alpha:error")
assert.equal(alphaControl.getAttribute("value"), "error")
assert.equal(alphaControl.getAttribute("data-payload"), "alpha:error")
assert.equal(alphaControl.getAttribute("data-control-directive"), "alpha:error")
assert.equal(alphaContent.textContent, "Alpha updated content")

primitiveApp.unmount()
nativeApp.unmount()
dom.window.close()
console.log(`cadence_diagnostics_section_frame_test passed (${scenarios.length} scenarios)`)
