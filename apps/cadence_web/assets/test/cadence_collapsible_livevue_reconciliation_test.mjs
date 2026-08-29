import assert from "node:assert/strict"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "client-seeded mode requires a caller-owned seed epoch",
  "the first client-owned state is seeded from the server open prop",
  "client interaction updates effective state immediately",
  "unrelated prop reconciliation does not overwrite client-owned state",
  "an epoch change intentionally reseeds from the current server open prop",
  "keep-mounted content preserves native identity, value, id, and aria-controls",
  "controlled request, acknowledgement, and unmount behavior remains unchanged",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const componentPaths = {
  root: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsible.vue"),
  trigger: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsibleTrigger.vue"),
  content: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsibleContent.vue"),
}

await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarios.length, 7)

const dom = installDom('<div id="client-app"></div><div id="controlled-app"></div>')
const [rootSfc, triggerSfc, contentSfc] = await Promise.all([
  loadSfc(componentPaths.root),
  loadSfc(componentPaths.trigger),
  loadSfc(componentPaths.content),
])

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const CadenceCollapsible = rootSfc.component
const CadenceCollapsibleTrigger = triggerSfc.component
const CadenceCollapsibleContent = contentSfc.component

assert.throws(
  () =>
    CadenceCollapsible.setup(
      {
        open: false,
        contentId: "missing-seed-content",
        disabled: false,
        clientSeeded: true,
        unmountOnHide: true,
      },
      {emit() {}, expose() {}},
    ),
  /client-seeded mode requires seedEpoch/,
)

const serverOpen = ref(true)
const seedEpoch = ref(1)
const reconciliationLabel = ref("initial")
const clientDisabled = ref(false)
const clientRequestedStates = []

const ClientSeededOracle = defineComponent({
  name: "CadenceCollapsibleClientSeededOracle",
  setup() {
    return () =>
      h(
        CadenceCollapsible,
        {
          open: serverOpen.value,
          contentId: "client-seeded-content",
          disabled: clientDisabled.value,
          clientSeeded: true,
          seedEpoch: seedEpoch.value,
          unmountOnHide: false,
          onRequestChange: (nextOpen) => clientRequestedStates.push(nextOpen),
        },
        {
          default: ({open, disabled}) =>
            h(
              "section",
              {
                id: "client-seeded-root",
                "data-state": "caller-stale",
                "data-disabled": "caller-stale",
                "data-slot-open": String(open),
                "data-slot-disabled": String(disabled),
                "data-reconciliation": reconciliationLabel.value,
              },
              [
                h(
                  CadenceCollapsibleTrigger,
                  null,
                  {
                    default: () =>
                      h(
                        "button",
                        {
                          id: "client-seeded-trigger",
                          type: "button",
                          "aria-controls": "caller-stale-content",
                          "aria-expanded": "caller-stale",
                          "data-state": "caller-stale",
                        },
                        open ? "Close" : "Open",
                      ),
                  },
                ),
                h(
                  CadenceCollapsibleContent,
                  null,
                  {
                    default: () =>
                      h(
                        "div",
                        {
                          id: "caller-stale-content",
                          "data-state": "caller-stale",
                        },
                        [
                          h("input", {
                            id: "client-seeded-input",
                            name: "client_seeded[draft]",
                          }),
                        ],
                      ),
                  },
                ),
              ],
            ),
        },
      )
  },
})

const clientApp = createApp(ClientSeededOracle)
clientApp.mount(dom.window.document.querySelector("#client-app"))
await flushVue(nextTick)

const clientRoot = dom.window.document.querySelector("#client-seeded-root")
const clientTrigger = dom.window.document.querySelector("#client-seeded-trigger")
const clientContent = () => dom.window.document.querySelector("#client-seeded-content")
const assertClientRelationship = (expectedContent) => {
  assert.equal(clientTrigger.getAttribute("aria-controls"), "client-seeded-content")
  assert.equal(expectedContent.id, "client-seeded-content")
  assert.equal(clientTrigger.getAttribute("aria-controls"), expectedContent.id)
}

const firstClientContent = clientContent()
const firstClientInput = dom.window.document.querySelector("#client-seeded-input")
assert.ok(firstClientContent)
assert.ok(firstClientInput)
assert.equal(serverOpen.value, true)
assert.equal(clientRoot.getAttribute("data-slot-open"), "true")
assert.equal(clientRoot.getAttribute("data-state"), "open")
assert.equal(clientTrigger.getAttribute("aria-expanded"), "true")
assert.equal(firstClientContent.getAttribute("data-state"), "open")
assert.equal(firstClientContent.hasAttribute("hidden"), false)
assertClientRelationship(firstClientContent)

firstClientInput.value = "operator draft"
clientTrigger.click()
await flushVue(nextTick)

assert.deepEqual(clientRequestedStates, [false])
assert.equal(serverOpen.value, true, "a client request does not mutate the server seed")
assert.equal(clientRoot.getAttribute("data-slot-open"), "false")
assert.equal(clientRoot.getAttribute("data-state"), "closed")
assert.equal(clientTrigger.getAttribute("aria-expanded"), "false")
assert.equal(clientContent(), firstClientContent)
assert.equal(firstClientContent.getAttribute("data-state"), "closed")
assert.equal(firstClientContent.hasAttribute("hidden"), true)
assert.equal(dom.window.document.querySelector("#client-seeded-input"), firstClientInput)
assert.equal(firstClientInput.value, "operator draft")
assertClientRelationship(firstClientContent)

clientTrigger.click()
await flushVue(nextTick)
assert.deepEqual(clientRequestedStates, [false, true])
assert.equal(clientRoot.getAttribute("data-slot-open"), "true")
assert.equal(clientRoot.getAttribute("data-state"), "open")
assert.equal(clientTrigger.getAttribute("aria-expanded"), "true")
assert.equal(clientContent(), firstClientContent)
assert.equal(firstClientInput.value, "operator draft")

serverOpen.value = false
reconciliationLabel.value = "unrelated-livevue-patch"
clientDisabled.value = true
await flushVue(nextTick)

assert.equal(clientRoot.getAttribute("data-reconciliation"), "unrelated-livevue-patch")
assert.equal(clientRoot.getAttribute("data-slot-open"), "true")
assert.equal(clientRoot.getAttribute("data-slot-disabled"), "true")
assert.equal(clientRoot.getAttribute("data-state"), "open")
assert.equal(clientRoot.getAttribute("data-disabled"), "")
assert.equal(clientTrigger.disabled, true)
assert.equal(clientContent(), firstClientContent)
assert.equal(firstClientInput.value, "operator draft")
assertClientRelationship(firstClientContent)

clientDisabled.value = false
seedEpoch.value = 2
await flushVue(nextTick)

assert.equal(clientRoot.getAttribute("data-slot-open"), "false")
assert.equal(clientRoot.getAttribute("data-state"), "closed")
assert.equal(clientTrigger.getAttribute("aria-expanded"), "false")
assert.equal(clientContent(), firstClientContent)
assert.equal(firstClientContent.getAttribute("data-state"), "closed")
assert.equal(firstClientContent.hasAttribute("hidden"), true)
assert.equal(dom.window.document.querySelector("#client-seeded-input"), firstClientInput)
assert.equal(firstClientInput.value, "operator draft")
assertClientRelationship(firstClientContent)

serverOpen.value = true
reconciliationLabel.value = "same-epoch-livevue-patch"
await flushVue(nextTick)
assert.equal(clientRoot.getAttribute("data-reconciliation"), "same-epoch-livevue-patch")
assert.equal(clientRoot.getAttribute("data-slot-open"), "false")
assert.equal(clientRoot.getAttribute("data-state"), "closed")
assert.equal(clientContent(), firstClientContent)
assert.equal(firstClientInput.value, "operator draft")

seedEpoch.value = 3
await flushVue(nextTick)
assert.equal(clientRoot.getAttribute("data-slot-open"), "true")
assert.equal(clientRoot.getAttribute("data-state"), "open")
assert.equal(clientTrigger.getAttribute("aria-expanded"), "true")
assert.equal(clientContent(), firstClientContent)
assert.equal(firstClientContent.hasAttribute("hidden"), false)
assert.equal(firstClientInput.value, "operator draft")
assertClientRelationship(firstClientContent)

const controlledOpen = ref(false)
const controlledRequestedStates = []

const ControlledOracle = defineComponent({
  name: "CadenceCollapsibleControlledReconciliationOracle",
  setup() {
    return () =>
      h(
        CadenceCollapsible,
        {
          open: controlledOpen.value,
          contentId: "controlled-content",
          onRequestChange: (nextOpen) => controlledRequestedStates.push(nextOpen),
        },
        {
          default: ({open}) =>
            h(
              "section",
              {
                id: "controlled-root",
                "data-slot-open": String(open),
              },
              [
                h(
                  CadenceCollapsibleTrigger,
                  null,
                  {
                    default: () =>
                      h("button", {id: "controlled-trigger", type: "button"}, "Toggle"),
                  },
                ),
                h(
                  CadenceCollapsibleContent,
                  null,
                  {
                    default: () =>
                      h("div", {id: "caller-controlled-content"}, [
                        h("input", {id: "controlled-input", value: "controlled"}),
                      ]),
                  },
                ),
              ],
            ),
        },
      )
  },
})

const controlledApp = createApp(ControlledOracle)
controlledApp.mount(dom.window.document.querySelector("#controlled-app"))
await flushVue(nextTick)

const controlledRoot = dom.window.document.querySelector("#controlled-root")
const controlledTrigger = dom.window.document.querySelector("#controlled-trigger")
assert.equal(controlledRoot.getAttribute("data-slot-open"), "false")
assert.equal(controlledRoot.getAttribute("data-state"), "closed")
assert.equal(controlledTrigger.getAttribute("aria-controls"), "controlled-content")
assert.equal(controlledTrigger.getAttribute("aria-expanded"), "false")
assert.equal(dom.window.document.querySelector("#controlled-content"), null)

controlledTrigger.click()
await flushVue(nextTick)
assert.deepEqual(controlledRequestedStates, [true])
assert.equal(controlledRoot.getAttribute("data-slot-open"), "false")
assert.equal(controlledRoot.getAttribute("data-state"), "closed")
assert.equal(controlledTrigger.getAttribute("aria-expanded"), "false")
assert.equal(dom.window.document.querySelector("#controlled-content"), null)

controlledOpen.value = true
await flushVue(nextTick)
const acknowledgedContent = dom.window.document.querySelector("#controlled-content")
const acknowledgedInput = dom.window.document.querySelector("#controlled-input")
assert.ok(acknowledgedContent)
assert.ok(acknowledgedInput)
assert.equal(controlledRoot.getAttribute("data-slot-open"), "true")
assert.equal(controlledRoot.getAttribute("data-state"), "open")
assert.equal(controlledTrigger.getAttribute("aria-expanded"), "true")
assert.equal(controlledTrigger.getAttribute("aria-controls"), acknowledgedContent.id)

controlledTrigger.click()
await flushVue(nextTick)
assert.deepEqual(controlledRequestedStates, [true, false])
assert.equal(controlledRoot.getAttribute("data-slot-open"), "true")
assert.equal(controlledTrigger.getAttribute("aria-expanded"), "true")
assert.equal(dom.window.document.querySelector("#controlled-content"), acknowledgedContent)

controlledOpen.value = false
await flushVue(nextTick)
assert.equal(controlledRoot.getAttribute("data-slot-open"), "false")
assert.equal(controlledRoot.getAttribute("data-state"), "closed")
assert.equal(controlledTrigger.getAttribute("aria-expanded"), "false")
assert.equal(dom.window.document.querySelector("#controlled-content"), null)
assert.equal(acknowledgedContent.isConnected, false)
assert.equal(acknowledgedInput.isConnected, false)

controlledApp.unmount()
clientApp.unmount()
dom.window.close()

console.log(
  `cadence_collapsible_livevue_reconciliation_test passed (${scenarios.length} scenarios; JSDOM state/reconciliation only, browser Enter/Space/focus remains a separate gate)`,
)
