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

const scenarios = Object.freeze([
  "CadencePanel forwards every caller root attribute to exactly one native section",
  "the required header class belongs to the section's exact first-child div",
  "header and default fragment VNodes flatten into exact direct-child order without wrappers",
  "caller-owned native nodes retain identity, attributes, listeners, and form behavior",
  "reactive root attributes update without replacing the panel or caller-owned nodes",
])

assert.equal(process.versions.node, "24.16.0", "panel contracts use pinned Node 24.16.0")
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadencePanel.vue")
const dom = installDom('<div id="app"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")

const source = await readFile(componentPath, "utf8")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadencePanel parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.script, "CadencePanel keeps a TypeScript render-function script")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)

const compiled = compileScript(parsed.descriptor, {id: "cadence-panel-foundation"}).content
const transformed = transformSync(compiled, {
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

const CadencePanel = loadedModule.exports.default

assert.deepEqual(Object.keys(CadencePanel.props), ["headerClass"])
assert.equal(CadencePanel.props.headerClass.required, true)
assert.equal(CadencePanel.props.headerClass.type, String)
assert.equal(CadencePanel.inheritAttrs, false)
assert.equal(source.match(/h\("section"/g)?.length, 1)
assert.equal(source.match(/h\("div"/g)?.length, 1)
assert.match(source, /child\.type === Fragment/)
assert.doesNotMatch(
  source,
  /<template>|<style|ref\(|reactive\(|computed\(|watch\(|emit\(|href|<form|<a|<button/,
)

const {Fragment, createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const panelId = ref("caller-panel-initial")
const phase = ref("ready")
const headerButtonElement = ref()
const anchorElement = ref()
const formElement = ref()
let sectionClicks = 0
let headerButtonClicks = 0
let formSubmits = 0

const PrimitiveOracle = defineComponent({
  name: "CadencePanelPrimitiveOracle",
  setup() {
    return () =>
      h(
        CadencePanel,
        {
          id: panelId.value,
          class: "root-first root-second",
          "aria-label": "Caller panel",
          "data-static": "static-value",
          "data-phase": phase.value,
          headerClass: "header-first header-second",
          onClick: () => {
            sectionClicks += 1
          },
        },
        {
          header: () => [
            h(Fragment, null, [
              h(
                "button",
                {
                  ref: headerButtonElement,
                  id: "caller-header-button",
                  type: "button",
                  name: "header-intent",
                  value: "inspect",
                  onClick: () => {
                    headerButtonClicks += 1
                  },
                },
                "Inspect <header>",
              ),
              h(Fragment, null, [
                h("span", {id: "caller-header-status"}, "Ready & waiting"),
              ]),
            ]),
          ],
          default: () => [
            h(Fragment, null, [
              h(
                "a",
                {
                  ref: anchorElement,
                  id: "caller-panel-link",
                  href: "/providers/one?from=panel&mode=inspect",
                  "data-phx-link": "redirect",
                  "data-phx-link-state": "push",
                },
                "Provider <one>",
              ),
              h(Fragment, null, [
                h(
                  "form",
                  {
                    ref: formElement,
                    id: "caller-panel-form",
                    action: "/providers/one?intent=sync&source=panel",
                    method: "post",
                    "data-phx-trigger-action": "true",
                    onSubmit: (event) => {
                      event.preventDefault()
                      formSubmits += 1
                    },
                  },
                  [
                    h("input", {type: "hidden", name: "_csrf_token", value: "csrf-token"}),
                    h(
                      "button",
                      {id: "caller-submit", type: "submit", name: "intent", value: "sync"},
                      "Sync provider",
                    ),
                  ],
                ),
              ]),
            ]),
          ],
        },
      )
  },
})

const expectedOuterHtml = (id, currentPhase) =>
  `<section id="${id}" class="root-first root-second" aria-label="Caller panel" data-static="static-value" data-phase="${currentPhase}"><div class="header-first header-second"><button id="caller-header-button" type="button" name="header-intent" value="inspect">Inspect &lt;header&gt;</button><span id="caller-header-status">Ready &amp; waiting</span></div><a id="caller-panel-link" href="/providers/one?from=panel&amp;mode=inspect" data-phx-link="redirect" data-phx-link-state="push">Provider &lt;one&gt;</a><form id="caller-panel-form" action="/providers/one?intent=sync&amp;source=panel" method="post" data-phx-trigger-action="true"><input type="hidden" name="_csrf_token" value="csrf-token"><button id="caller-submit" type="submit" name="intent" value="sync">Sync provider</button></form></section>`

const app = createApp(PrimitiveOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const section = dom.window.document.querySelector("#caller-panel-initial")
const header = section.firstElementChild
const headerButton = dom.window.document.querySelector("#caller-header-button")
const headerStatus = dom.window.document.querySelector("#caller-header-status")
const anchor = dom.window.document.querySelector("#caller-panel-link")
const form = dom.window.document.querySelector("#caller-panel-form")

assert.equal(section.outerHTML, expectedOuterHtml("caller-panel-initial", "ready"))
assert.equal(section.tagName, "SECTION")
assert.deepEqual(elementAttributes(section), {
  "aria-label": "Caller panel",
  class: "root-first root-second",
  "data-phase": "ready",
  "data-static": "static-value",
  id: "caller-panel-initial",
})
assert.equal(section.hasAttribute("headerclass"), false)
assert.equal(section.hasAttribute("header-class"), false)
assert.equal(section.childNodes.length, 3)
assert.deepEqual(
  [...section.childNodes].map((node) => [node.nodeType, node.nodeName]),
  [
    [dom.window.Node.ELEMENT_NODE, "DIV"],
    [dom.window.Node.ELEMENT_NODE, "A"],
    [dom.window.Node.ELEMENT_NODE, "FORM"],
  ],
)
assert.equal(header.getAttribute("class"), "header-first header-second")
assert.deepEqual(elementAttributes(header), {class: "header-first header-second"})
assert.equal(header.childNodes.length, 2)
assert.deepEqual(
  [...header.childNodes].map((node) => [node.nodeType, node.nodeName]),
  [
    [dom.window.Node.ELEMENT_NODE, "BUTTON"],
    [dom.window.Node.ELEMENT_NODE, "SPAN"],
  ],
)
assert.strictEqual(section.children[0], header)
assert.strictEqual(section.children[1], anchor)
assert.strictEqual(section.children[2], form)
assert.strictEqual(header.children[0], headerButton)
assert.strictEqual(header.children[1], headerStatus)
assert.strictEqual(headerButtonElement.value, headerButton)
assert.strictEqual(anchorElement.value, anchor)
assert.strictEqual(formElement.value, form)
assert.deepEqual(elementAttributes(headerButton), {
  id: "caller-header-button",
  name: "header-intent",
  type: "button",
  value: "inspect",
})
assert.deepEqual(elementAttributes(anchor), {
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/providers/one?from=panel&mode=inspect",
  id: "caller-panel-link",
})
assert.deepEqual(elementAttributes(form), {
  action: "/providers/one?intent=sync&source=panel",
  "data-phx-trigger-action": "true",
  id: "caller-panel-form",
  method: "post",
})

headerButton.click()
assert.equal(headerButtonClicks, 1)
assert.equal(sectionClicks, 1)

section.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.equal(sectionClicks, 2)

const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(form.dispatchEvent(submitEvent), false)
assert.equal(formSubmits, 1)

panelId.value = "caller-panel-updated"
phase.value = "running"
await flushVue(nextTick)

const updatedSection = dom.window.document.querySelector("#caller-panel-updated")

assert.strictEqual(updatedSection, section)
assert.strictEqual(updatedSection.children[0], header)
assert.strictEqual(updatedSection.children[1], anchor)
assert.strictEqual(updatedSection.children[2], form)
assert.strictEqual(headerButtonElement.value, headerButton)
assert.strictEqual(anchorElement.value, anchor)
assert.strictEqual(formElement.value, form)
assert.equal(updatedSection.outerHTML, expectedOuterHtml("caller-panel-updated", "running"))

assert.doesNotThrow(() => app.unmount())
console.log(`cadence_panel_test passed (${scenarios.length} semantic scenarios)`)
