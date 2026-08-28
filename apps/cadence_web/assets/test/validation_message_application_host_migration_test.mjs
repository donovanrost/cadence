import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `ApplicationHost validation-message migration uses pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const callerPath = resolve(testDirectory, "../vue/ApplicationHost.vue")
const callerSource = await readFile(callerPath, "utf8")
const occurrences = (value, fragment) => value.split(fragment).length - 1
const importSource =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const messageOpening = `                <CadenceValidationMessage
                  v-for="error in field.errors"
                  :key="error"
                >`
const predecessorOpening = `                <p
                  v-for="error in field.errors"
                  :key="error"
                  class="mt-1.5 text-sm text-error"
                >`
const messageClosing = "                >{{ error }}</CadenceValidationMessage>"
const predecessorClosing = "                >{{ error }}</p>"

assert.equal(occurrences(callerSource, importSource), 1)
assert.equal(occurrences(callerSource, messageOpening), 1)
assert.equal(occurrences(callerSource, messageClosing), 1)
assert.equal(occurrences(callerSource, "<CadenceValidationMessage"), 1)
assert.equal(occurrences(callerSource, "</CadenceValidationMessage>"), 1)
assert.equal(occurrences(callerSource, 'class="mt-1.5 text-sm text-error"'), 0)

const predecessorSource = callerSource
  .replace(importSource, "")
  .replace(messageOpening, predecessorOpening)
  .replace(messageClosing, predecessorClosing)

assert.doesNotMatch(predecessorSource, /CadenceValidationMessage/)
assert.equal(
  createHash("sha256").update(predecessorSource).digest("hex"),
  "da2d9e772a112e009f1cf2b4ec8fa5bc1d4d86e9fcaea7dc30b827f224d4f4b8",
  "the exact native paragraph predecessor reconstructs byte-for-byte",
)

const dom = installDom('<div id="application-host-validation-message"></div>')
const {component: ApplicationHost} = await loadSfc(callerPath)
const {createApp, nextTick} = integrationRequire("vue")
const formChanges = []
const applicationActions = []
const props = {
  host: {
    dom_id: "mission-application-host",
    application_key: "limits",
    application_version: 1,
    application_installation_id: "application-installation-1",
    surface_id: "configure",
    renderer: "declarative",
  },
  navigation: null,
  declarative_surface: {
    id: "declarative-application-surface",
    page: {title: "Configure limits", subtitle: null},
    action_feedback: null,
    stats: [],
    diagnostics: null,
    form: {
      id: "application-form-card",
      form_id: "application-form",
      title: "Limit configuration",
      description: null,
      fields: [
        {
          id: "application-limit-field",
          field: "limit",
          input_id: "application-limit",
          name: "application_action[limit]",
          type: "text",
          contract_type: "string",
          label: "Operational limit",
          placeholder: null,
          help: null,
          required: true,
          step: null,
          min: null,
          max: null,
          value: "initial <value> & state",
          errors: ["can't be blank", "<Server> & invalid"],
          options: [],
          reference: null,
          visible_when: null,
        },
      ],
      action: {
        id: "application-form-submit",
        action_id: "save_limits",
        label: "Save limits",
        version: 7,
        intent: "update",
        scope: "mission",
        effect: "write",
        execution: "synchronous",
        confirmation: null,
        disabled: false,
      },
    },
    packet_bindings: null,
    table: null,
    activity: null,
  },
  application_surface_rows: [],
  application_surface_activity: [],
  application_surface_packet_groups: [],
  onApplication_form_change: (payload) => formChanges.push(payload),
  onApplication_action: (payload) => applicationActions.push(payload),
}
const host = dom.window.document.querySelector("#application-host-validation-message")
const app = createApp(ApplicationHost, props)
app.mount(host)
await nextTick()

const fieldset = host.querySelector("#application-limit-field .fieldset")
const input = host.querySelector("#application-limit")
const messages = [...fieldset.querySelectorAll(":scope > p")]

assert.equal(
  fieldset.outerHTML,
  '<div class="fieldset mb-3"><label><span class="hud-label mb-1.5 block">Operational limit</span><input id="application-limit" name="application_action[limit]" type="text" required="" class="input w-full input-error" value="initial <value> &amp; state"></label><!--v-if--><!--v-if--><p class="mt-1.5 text-sm text-error">can\'t be blank</p><p class="mt-1.5 text-sm text-error">&lt;Server&gt; &amp; invalid</p></div>',
  "the migrated host renders the exact native form-field DOM",
)
assert.deepEqual(
  messages.map((message) => [message.tagName, message.className, message.textContent]),
  [
    ["P", "mt-1.5 text-sm text-error", "can't be blank"],
    ["P", "mt-1.5 text-sm text-error", "<Server> & invalid"],
  ],
)
assert.ok(messages.every((message) => message.parentElement === fieldset))
assert.ok(messages.every((message) => message.childNodes.length === 1))

input.value = "updated value"
input.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await nextTick()

assert.strictEqual(host.querySelector("#application-limit"), input)
assert.deepEqual(formChanges, [
  {
    application_action: {limit: "updated value"},
    _target: ["application_action", "limit"],
  },
])

const form = host.querySelector("#application-form")
form.dispatchEvent(new dom.window.Event("submit", {bubbles: true, cancelable: true}))
await nextTick()

assert.deepEqual(applicationActions, [
  {
    "action-id": "save_limits",
    application_action: {limit: "updated value"},
  },
])

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log("validation_message_application_host_migration_test passed")
