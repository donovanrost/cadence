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
  "CadenceCard owns exactly one section and one body div with caller-authored classes",
  "static and dynamic root attributes forward only to the native section",
  "native root listeners forward to the native section",
  "caller-owned Phoenix redirect anchor and form retain native identity and attributes",
  "the default slot is flattened in exact order without wrapper or empty nodes",
])

assert.equal(process.versions.node, "24.16.0", "card contracts use pinned Node 24.16.0")
assert.equal(scenarios.length, 5)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceCard.vue")
const dom = installDom('<div id="app"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")

const source = await readFile(componentPath, "utf8")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceCard parses with the pinned Vue compiler")
assert.ok(parsed.descriptor.script, "CadenceCard keeps a native render-function script")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)

const compiled = compileScript(parsed.descriptor, {
  id: "cadence-card-foundation",
}).content
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

const CadenceCard = loadedModule.exports.default

assert.deepEqual(Object.keys(CadenceCard.props), ["bodyClass"])
assert.equal(CadenceCard.props.bodyClass.required, true)
assert.equal(CadenceCard.props.bodyClass.type, String)
assert.equal(CadenceCard.inheritAttrs, false)
assert.equal(source.match(/h\("section"/g)?.length, 1)
assert.equal(source.match(/h\("div"/g)?.length, 1)
assert.doesNotMatch(
  source,
  /<template>|<style|ref\(|reactive\(|computed\(|watch\(|emit\(|variant|href|<form|<a/,
)

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const rootId = ref("caller-card-initial")
const phase = ref("ready")
const anchorElement = ref()
const formElement = ref()
let sectionClicks = 0
let formSubmits = 0

const PrimitiveOracle = defineComponent({
  name: "CadenceCardPrimitiveOracle",
  setup() {
    return () =>
      h(
        CadenceCard,
        {
          bodyClass: "body-first body-second",
          id: rootId.value,
          class: "root-first root-second",
          "aria-label": "Caller card",
          "data-static": "static-value",
          "data-phase": phase.value,
          onClick: () => {
            sectionClicks += 1
          },
        },
        {
          default: () => [
            h(
              "a",
              {
                ref: anchorElement,
                id: "caller-organizations-link",
                href: "/admin/organizations?from=card&mode=all",
                "data-phx-link": "redirect",
                "data-phx-link-state": "push",
                class: "btn first-class second-class",
              },
              "Organizations <all>",
            ),
            h(
              "form",
              {
                ref: formElement,
                id: "caller-create-form",
                action: "/admin/organizations?intent=create&source=card",
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
                  {id: "caller-submit", type: "submit", name: "intent", value: "create"},
                  "Create organization",
                ),
              ],
            ),
          ],
        },
      )
  },
})

const expectedOuterHtml = (id, currentPhase) =>
  `<section id="${id}" class="root-first root-second" aria-label="Caller card" data-static="static-value" data-phase="${currentPhase}"><div class="body-first body-second"><a id="caller-organizations-link" href="/admin/organizations?from=card&amp;mode=all" data-phx-link="redirect" data-phx-link-state="push" class="btn first-class second-class">Organizations &lt;all&gt;</a><form id="caller-create-form" action="/admin/organizations?intent=create&amp;source=card" method="post" data-phx-trigger-action="true"><input type="hidden" name="_csrf_token" value="csrf-token"><button id="caller-submit" type="submit" name="intent" value="create">Create organization</button></form></div></section>`

const app = createApp(PrimitiveOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const section = dom.window.document.querySelector("#caller-card-initial")
const body = section.firstElementChild
const anchor = dom.window.document.querySelector("#caller-organizations-link")
const form = dom.window.document.querySelector("#caller-create-form")

assert.equal(section.outerHTML, expectedOuterHtml("caller-card-initial", "ready"))
assert.equal(section.tagName, "SECTION")
assert.equal(section.childNodes.length, 1)
assert.equal(section.children.length, 1)
assert.equal(body.tagName, "DIV")
assert.equal(body.getAttribute("class"), "body-first body-second")
assert.deepEqual(elementAttributes(section), {
  "aria-label": "Caller card",
  class: "root-first root-second",
  "data-phase": "ready",
  "data-static": "static-value",
  id: "caller-card-initial",
})
assert.deepEqual(elementAttributes(body), {class: "body-first body-second"})
assert.equal(section.hasAttribute("bodyclass"), false)
assert.equal(section.hasAttribute("body-class"), false)
assert.equal(body.hasAttribute("bodyclass"), false)
assert.equal(body.hasAttribute("body-class"), false)
assert.equal(body.childNodes.length, 2)
assert.equal(body.children.length, 2)
assert.deepEqual(
  [...body.childNodes].map((node) => [node.nodeType, node.nodeName]),
  [
    [dom.window.Node.ELEMENT_NODE, "A"],
    [dom.window.Node.ELEMENT_NODE, "FORM"],
  ],
)
assert.strictEqual(body.children[0], anchor)
assert.strictEqual(body.children[1], form)
assert.strictEqual(anchorElement.value, anchor)
assert.strictEqual(formElement.value, form)
assert.deepEqual(elementAttributes(anchor), {
  class: "btn first-class second-class",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/admin/organizations?from=card&mode=all",
  id: "caller-organizations-link",
})
assert.deepEqual(elementAttributes(form), {
  action: "/admin/organizations?intent=create&source=card",
  "data-phx-trigger-action": "true",
  id: "caller-create-form",
  method: "post",
})
assert.equal(form.childNodes.length, 2)
assert.deepEqual(
  [...form.children].map((element) => [element.tagName, element.id]),
  [
    ["INPUT", ""],
    ["BUTTON", "caller-submit"],
  ],
)

section.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.equal(sectionClicks, 1)

const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(form.dispatchEvent(submitEvent), false)
assert.equal(formSubmits, 1)

rootId.value = "caller-card-updated"
phase.value = "running"
await flushVue(nextTick)

const updatedSection = dom.window.document.querySelector("#caller-card-updated")

assert.strictEqual(updatedSection, section)
assert.strictEqual(updatedSection.firstElementChild, body)
assert.equal(updatedSection.outerHTML, expectedOuterHtml("caller-card-updated", "running"))
assert.equal(updatedSection.getAttribute("class"), "root-first root-second")
assert.equal(updatedSection.getAttribute("data-phase"), "running")
assert.equal(body.getAttribute("class"), "body-first body-second")
assert.strictEqual(anchorElement.value, anchor)
assert.strictEqual(formElement.value, form)

assert.doesNotThrow(() => app.unmount())
console.log(`cadence_card_test passed (${scenarios.length} semantic scenarios)`)
