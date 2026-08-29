#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {dashboardSettingsSectionFrameClass} from "./dashboard_settings_section_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the compiled SFC owns exactly one native section and the canonical class",
  "root attrs, classes, listeners, and directives forward without a wrapper",
  "nested arrays and Fragments flatten into caller-owned direct children",
  "caller-owned forms, controls, links, values, payloads, and events remain native",
  "keyed sections and nested native child identity survive reorder and updates",
  "the transparent frame output matches the native section oracle exactly",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode, "the mounted contract uses the pinned Node executable")
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 6)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceDashboardSettingsSectionFrame.vue",
)
const source = await readFile(componentPath, "utf8")
const dom = installDom('<div id="frame-host"></div><div id="native-host"></div>')
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLButtonElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})
assert.deepEqual(parsed.errors, [], "the frame parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the frame keeps a typed render-function script")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)
assert.equal(parsed.descriptor.styles.length, 0)

const compiled = compileScript(parsed.descriptor, {id: "cadence-dashboard-settings-section-frame-contract"})
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
const CadenceDashboardSettingsSectionFrame = loadedModule.exports.default

assert.equal(CadenceDashboardSettingsSectionFrame.inheritAttrs, false)
assert.deepEqual(Object.keys(CadenceDashboardSettingsSectionFrame.props ?? {}), [])
assert.deepEqual(Object.keys(CadenceDashboardSettingsSectionFrame.emits ?? {}), [])
assert.equal(source.match(/h\(\s*"section"/g)?.length, 1)
assert.equal(source.split(dashboardSettingsSectionFrameClass).length - 1, 1)
assert.match(source, /Array\.isArray\(child\)/)
assert.match(source, /child\.type === Fragment/)
assert.match(source, /cloneVNode\(child/)
assert.match(source, /String\(inheritedKey\)/)
assert.doesNotMatch(
  source,
  /<template|<style|defineProps|defineEmits|\b(?:computed|reactive|ref|watch|onMounted)\s*\(|\b(?:role|aria-|data-|tabindex)\b|<form|<button|href/,
  "the frame owns no caller semantics or controls",
)

const {Fragment, createApp, defineComponent, h, nextTick, ref, withDirectives} =
  integrationRequire("vue")
const frames = ref([
  {key: "sharing", label: "Sharing", phase: "ready", value: "alpha"},
  {key: "snapshots", label: "Snapshots", phase: "draft", value: "bravo"},
])
const rootClicks = []
const controlClicks = []
const formSubmits = []
const inputEvents = []
const rootDirective = {
  mounted(element, binding) {
    element.setAttribute("data-root-directive", binding.value)
  },
  updated(element, binding) {
    element.setAttribute("data-root-directive", binding.value)
  },
}

const childNodes = (frame, target) => [
  h(Fragment, null, [
    [
      h(
        "form",
        {
          key: "form",
          id: `${target}-${frame.key}-form`,
          "phx-submit": "save_settings",
          onSubmit: (event) => {
            event.preventDefault()
            formSubmits.push(`${target}:${frame.key}`)
          },
        },
        [
          h("input", {
            key: "input",
            id: `${target}-${frame.key}-input`,
            name: `${frame.key}_value`,
            type: "text",
            value: frame.value,
            "data-payload": `${frame.key}:${frame.value}`,
            onInput: (event) => inputEvents.push(`${target}:${event.target.value}`),
          }),
          h(
            "select",
            {
              key: "select",
              id: `${target}-${frame.key}-select`,
              name: `${frame.key}_visibility`,
              value: frame.phase,
            },
            [
              h("option", {key: "ready", value: "ready"}, "Ready"),
              h("option", {key: "draft", value: "draft"}, "Draft"),
              h("option", {key: "error", value: "error"}, "Error"),
            ],
          ),
          h(
            "button",
            {
              key: "button",
              id: `${target}-${frame.key}-button`,
              type: "button",
              "phx-click": "inspect",
              "phx-value-section": frame.key,
              onClick: () => controlClicks.push(`${target}:${frame.key}`),
            },
            `Inspect ${frame.label}`,
          ),
        ],
      ),
    ],
    h(Fragment, null, [
      h(
        "a",
        {
          key: "link",
          id: `${target}-${frame.key}-link`,
          href: `/dashboards/${frame.key}`,
          "data-phx-link": "redirect",
          "data-phx-link-state": "push",
        },
        `${frame.label} link`,
      ),
      h(
        "article",
        {key: "article", id: `${target}-${frame.key}-article`},
        `${frame.label} content`,
      ),
    ]),
  ]),
]

const renderFrame = (frame, target, primitive) => {
  const attrs = {
    key: frame.key,
    id: `${target}-${frame.key}`,
    class: "caller-first caller-second",
    "aria-label": `${frame.label} settings`,
    "data-phase": frame.phase,
    onClick: () => rootClicks.push(`${target}:${frame.key}`),
  }
  const content = childNodes(frame, target)

  if (primitive) {
    return withDirectives(h(CadenceDashboardSettingsSectionFrame, attrs, {default: () => content}), [
      [rootDirective, `${frame.key}:${frame.phase}`],
    ])
  }

  return withDirectives(
    h("section", {...attrs, class: [dashboardSettingsSectionFrameClass, attrs.class]}, content),
    [[rootDirective, `${frame.key}:${frame.phase}`]],
  )
}

const contract = (name, target, primitive) =>
  defineComponent({
    name,
    setup() {
      return () => h("main", frames.value.map((frame) => renderFrame(frame, target, primitive)))
    },
  })

const frameHost = dom.window.document.querySelector("#frame-host")
const nativeHost = dom.window.document.querySelector("#native-host")
const frameApp = createApp(contract("DashboardSettingsSectionFrameOracle", "frame", true))
const nativeApp = createApp(contract("DashboardSettingsSectionNativeOracle", "native", false))
frameApp.mount(frameHost)
nativeApp.mount(nativeHost)
await flushVue(nextTick)

assert.equal(frameHost.innerHTML.replaceAll("frame-", "native-"), nativeHost.innerHTML)
const frameMain = frameHost.firstElementChild
const sharingSection = frameMain.querySelector("#frame-sharing")
const snapshotsSection = frameMain.querySelector("#frame-snapshots")
const sharingForm = sharingSection.querySelector("form")
const sharingInput = sharingSection.querySelector("input")
const sharingSelect = sharingSection.querySelector("select")
const sharingButton = sharingSection.querySelector("button")
const sharingLink = sharingSection.querySelector("a")
const originalNodes = {
  sharingSection,
  snapshotsSection,
  sharingForm,
  sharingInput,
  sharingSelect,
  sharingButton,
  sharingLink,
}

assert.equal(frameHost.childNodes.length, 1)
assert.equal(frameMain.tagName, "MAIN")
assert.deepEqual([...frameMain.children].map(({id}) => id), ["frame-sharing", "frame-snapshots"])
assert.equal(sharingSection.tagName, "SECTION")
assert.equal(sharingSection.className, `${dashboardSettingsSectionFrameClass} caller-first caller-second`)
assert.deepEqual(elementAttributes(sharingSection), {
  "aria-label": "Sharing settings",
  "data-phase": "ready",
  "data-root-directive": "sharing:ready",
  class: `${dashboardSettingsSectionFrameClass} caller-first caller-second`,
  id: "frame-sharing",
})
assert.deepEqual([...sharingSection.children].map(({tagName}) => tagName), ["FORM", "A", "ARTICLE"])
assert.equal(sharingForm.getAttribute("phx-submit"), "save_settings")
assert.equal(sharingInput.getAttribute("name"), "sharing_value")
assert.equal(sharingInput.value, "alpha")
assert.equal(sharingInput.getAttribute("data-payload"), "sharing:alpha")
assert.equal(sharingSelect.value, "ready")
assert.equal(sharingButton.getAttribute("phx-click"), "inspect")
assert.equal(sharingButton.getAttribute("phx-value-section"), "sharing")
assert.equal(sharingLink.getAttribute("data-phx-link"), "redirect")
assert.equal(sharingLink.getAttribute("data-phx-link-state"), "push")

sharingButton.click()
assert.deepEqual(controlClicks, ["frame:sharing"])
sharingInput.value = "charlie"
sharingInput.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
assert.deepEqual(inputEvents, ["frame:charlie"])
const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(sharingForm.dispatchEvent(submitEvent), false)
assert.deepEqual(formSubmits, ["frame:sharing"])
assert.deepEqual(rootClicks, ["frame:sharing"])
rootClicks.length = 0
sharingSection.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.deepEqual(rootClicks, ["frame:sharing"])

frames.value = [
  {key: "snapshots", label: "Snapshots updated", phase: "ready", value: "delta"},
  {key: "sharing", label: "Sharing updated", phase: "error", value: "echo"},
]
await flushVue(nextTick)

assert.equal(frameHost.innerHTML.replaceAll("frame-", "native-"), nativeHost.innerHTML)
assert.deepEqual([...frameMain.children].map(({id}) => id), ["frame-snapshots", "frame-sharing"])
const updatedSharingSection = frameMain.querySelector("#frame-sharing")
const updatedSharingForm = updatedSharingSection.querySelector("form")
const updatedSharingInput = updatedSharingSection.querySelector("input")
const updatedSharingSelect = updatedSharingSection.querySelector("select")
const updatedSharingButton = updatedSharingSection.querySelector("button")
const updatedSharingLink = updatedSharingSection.querySelector("a")
assert.strictEqual(updatedSharingSection, originalNodes.sharingSection)
assert.strictEqual(frameMain.querySelector("#frame-snapshots"), originalNodes.snapshotsSection)
assert.strictEqual(updatedSharingForm, originalNodes.sharingForm)
assert.strictEqual(updatedSharingInput, originalNodes.sharingInput)
assert.strictEqual(updatedSharingSelect, originalNodes.sharingSelect)
assert.strictEqual(updatedSharingButton, originalNodes.sharingButton)
assert.strictEqual(updatedSharingLink, originalNodes.sharingLink)
assert.equal(updatedSharingSection.getAttribute("data-phase"), "error")
assert.equal(updatedSharingSection.getAttribute("data-root-directive"), "sharing:error")
assert.equal(updatedSharingInput.value, "echo")
assert.equal(updatedSharingInput.getAttribute("data-payload"), "sharing:echo")
assert.equal(updatedSharingSelect.value, "error")
assert.equal(updatedSharingButton.getAttribute("phx-value-section"), "sharing")
assert.equal(updatedSharingLink.textContent, "Sharing updated link")

frameApp.unmount()
nativeApp.unmount()
dom.window.close()

console.log(`cadence_dashboard_settings_section_frame_test passed (${scenarios.length} scenarios)`)
