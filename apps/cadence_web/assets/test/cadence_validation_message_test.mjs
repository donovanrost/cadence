import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceValidationMessage contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(
  testDirectory,
  "../vue/ui/components/CadenceValidationMessage.vue",
)
const callerPath = resolve(testDirectory, "../vue/HistoricalWorkflowStageForm.vue")
const [source, callerSource] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(callerPath, "utf8"),
])
const dom = installDom('<div id="validation-message-contract"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(source, {filename: componentPath})

assert.deepEqual(parsed.errors, [], "CadenceValidationMessage.vue parses with the pinned compiler")
assert.ok(parsed.descriptor.script, "the validation message keeps a typed render-function block")
assert.equal(parsed.descriptor.script.lang, "ts")
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null, "the primitive avoids template slot anchors")

const compiled = compileScript(parsed.descriptor, {
  id: "cadence-validation-message-contract",
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

const CadenceValidationMessage = loadedModule.exports.default

assert.equal(CadenceValidationMessage.name, "CadenceValidationMessage")
assert.equal(CadenceValidationMessage.inheritAttrs, false)
assert.equal(source.match(/h\(\s*"p"/g)?.length, 1)
assert.match(source, /"mt-1\.5 text-sm text-error"/)
assert.match(source, /child\.type === Fragment/)
assert.doesNotMatch(
  source,
  /<template|<style|defineProps|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(|\bemit\s*\(|\bfetch\s*\(|<form|<input|<button|@(?:click|input|change|submit)/,
  "the primitive owns no template wrapper, model, state, events, controls, or domain behavior",
)

const {Fragment, createApp, createTextVNode, defineComponent, h} = integrationRequire("vue")
const callerLeadText = createTextVNode("<Caller & safe>")
const callerTailText = createTextVNode(" tail & final")
let callerContent = null
let forwardedClicks = 0
const Contract = defineComponent({
  name: "CadenceValidationMessageContract",
  setup() {
    return () =>
      h(
        CadenceValidationMessage,
        {
          id: "validation-message",
          class: "caller-validation",
          "aria-live": "polite",
          "data-owner": "caller",
          title: "<Server> & validation",
          tabindex: "-1",
          onClick: () => {
            forwardedClicks += 1
          },
        },
        {
          default: () => [
            h(Fragment, null, [
              [callerLeadText],
              h(Fragment, null, [
                h(
                  "strong",
                  {
                    ref: (element) => {
                      callerContent = element
                    },
                    "data-content-owner": "caller",
                  },
                  "Owned <content> & identity",
                ),
                [callerTailText],
              ]),
            ]),
          ],
        },
      )
  },
})

const host = dom.window.document.querySelector("#validation-message-contract")
const app = createApp(Contract)
app.mount(host)

const message = host.firstElementChild

assert.equal(host.children.length, 1, "the primitive adds exactly one native element")
assert.equal(message.tagName, "P")
assert.equal(
  message.outerHTML,
  '<p id="validation-message" class="mt-1.5 text-sm text-error caller-validation" aria-live="polite" data-owner="caller" title="<Server> &amp; validation" tabindex="-1">&lt;Caller &amp; safe&gt;<strong data-content-owner="caller">Owned &lt;content&gt; &amp; identity</strong> tail &amp; final</p>',
)
assert.deepEqual(elementAttributes(message), {
  "aria-live": "polite",
  class: "mt-1.5 text-sm text-error caller-validation",
  "data-owner": "caller",
  id: "validation-message",
  tabindex: "-1",
  title: "<Server> & validation",
})
assert.deepEqual(
  [...message.childNodes].map((node) => [node.nodeName, node.nodeType, node.textContent]),
  [
    ["#text", 3, "<Caller & safe>"],
    ["STRONG", 1, "Owned <content> & identity"],
    ["#text", 3, " tail & final"],
  ],
)
assert.strictEqual(message.childNodes[0], callerLeadText.el)
assert.strictEqual(message.childNodes[1], callerContent)
assert.strictEqual(message.childNodes[2], callerTailText.el)
message.click()
assert.equal(forwardedClicks, 1, "caller listeners are forwarded to the native paragraph")

const occurrences = (value, fragment) => value.split(fragment).length - 1
const importSource =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n\n'
const reasonOpening = `      <CadenceValidationMessage
        v-for="(error, index) in presentation.reason.errors"
        :key="\`reason-error-\${index}\`"
      >`
const reasonPredecessor = `      <p
        v-for="(error, index) in presentation.reason.errors"
        :key="\`reason-error-\${index}\`"
        class="mt-1.5 text-sm text-error"
      >`
const fieldOpening = `        <CadenceValidationMessage
          v-for="(error, index) in field.errors"
          :key="\`\${field.input_attrs.id}-error-\${index}\`"
        >`
const fieldPredecessor = `        <p
          v-for="(error, index) in field.errors"
          :key="\`\${field.input_attrs.id}-error-\${index}\`"
          class="mt-1.5 text-sm text-error"
        >`

assert.equal(occurrences(callerSource, importSource), 1)
assert.equal(occurrences(callerSource, reasonOpening), 1)
assert.equal(occurrences(callerSource, fieldOpening), 1)
assert.equal(occurrences(callerSource, "<CadenceValidationMessage"), 2)

const predecessorSource = callerSource
  .replace(importSource, "")
  .replace(reasonOpening, reasonPredecessor)
  .replace("      </CadenceValidationMessage>", "      </p>")
  .replace(fieldOpening, fieldPredecessor)
  .replace("        </CadenceValidationMessage>", "        </p>")

assert.doesNotMatch(predecessorSource, /CadenceValidationMessage/)
assert.equal(
  createHash("sha256").update(predecessorSource).digest("hex"),
  "f7b9da36e57b047e98e3855e82c11c36df15e60f8596e65962d124503f5a6ee3",
  "the two canary loops reconstruct the exact HistoricalWorkflowStageForm predecessor",
)

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log("cadence_validation_message_test passed")
