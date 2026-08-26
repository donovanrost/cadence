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
  "the controlled root preserves the server-authored public root instead of adding a wrapper",
  "compound trigger and content preserve the explicit aria-controls and id relationship",
  "arbitrary server siblings retain their order around collapsible content",
  "trigger activation requests the next state without opening or closing optimistically",
  "closed content is unmounted and disabled roots reject activation",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const componentPaths = {
  root: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsible.vue"),
  trigger: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsibleTrigger.vue"),
  content: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsibleContent.vue"),
}

await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarios.length, 5)

const dom = installDom()
const [rootSfc, triggerSfc, contentSfc] = await Promise.all([
  loadSfc(componentPaths.root),
  loadSfc(componentPaths.trigger),
  loadSfc(componentPaths.content),
])

assert.match(rootSfc.descriptor.scriptSetup.content, /^import \{CollapsibleRoot\} from "reka-ui"$/m)
assert.match(rootSfc.descriptor.scriptSetup.content, /open: boolean/)
assert.match(rootSfc.descriptor.scriptSetup.content, /contentId: string/)
assert.match(rootSfc.descriptor.scriptSetup.content, /disabled\?: boolean/)
assert.match(rootSfc.descriptor.scriptSetup.content, /"request-change": \[open: boolean\]/)
assert.match(
  rootSfc.descriptor.scriptSetup.content,
  /provide\("cadence-collapsible", \{contentId: toRef\(props, "contentId"\)\}\)/,
)
assert.match(rootSfc.descriptor.template.content, /<CollapsibleRoot/)
assert.match(rootSfc.descriptor.template.content, /:open="props\.open"/)
assert.match(rootSfc.descriptor.template.content, /:disabled="props\.disabled"/)
assert.match(rootSfc.descriptor.template.content, /:unmount-on-hide="true"/)
assert.match(rootSfc.descriptor.template.content, /\bas-child\b/)
assert.match(rootSfc.descriptor.template.content, /contract-name="CadenceCollapsible"/)
assert.match(rootSfc.descriptor.template.content, /:enforce-attrs="\['data-state', 'data-disabled'\]"/)
assert.match(
  rootSfc.descriptor.template.content,
  /@update:open="emit\('request-change', \$event\)"/,
)
assert.doesNotMatch(rootSfc.source, /\bv-model\b|defaultOpen|default-open|\bref\(|\breactive\(/)

assert.match(
  triggerSfc.descriptor.scriptSetup.content,
  /^import \{CollapsibleTrigger\} from "reka-ui"$/m,
)
assert.match(triggerSfc.descriptor.template.content, /<CollapsibleTrigger as-child>/)
assert.equal(triggerSfc.descriptor.template.content.match(/<slot/g)?.length, 1)
assert.match(triggerSfc.descriptor.template.content, /:aria-controls="collapsible\.contentId\.value"/)
assert.match(triggerSfc.descriptor.template.content, /'aria-expanded'/)
assert.match(triggerSfc.descriptor.template.content, /'disabled'/)

assert.match(
  contentSfc.descriptor.scriptSetup.content,
  /^import \{CollapsibleContent\} from "reka-ui"$/m,
)
assert.match(contentSfc.descriptor.template.content, /<CollapsibleContent as-child>/)
assert.match(contentSfc.descriptor.template.content, /:id="collapsible\.contentId\.value"/)
assert.match(contentSfc.descriptor.template.content, /:enforce-attrs="\['id', 'hidden'/)
assert.doesNotMatch(contentSfc.source, /forceMount|force-mount/)

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const CadenceCollapsible = rootSfc.component
const CadenceCollapsibleTrigger = triggerSfc.component
const CadenceCollapsibleContent = contentSfc.component
const open = ref(false)
const disabled = ref(false)
const requestedStates = []

const RuntimeOracle = defineComponent({
  name: "CadenceCollapsibleRuntimeOracle",
  setup() {
    return () =>
      h(
        CadenceCollapsible,
        {
          open: open.value,
          contentId: "catalog-revision-upload-slot",
          disabled: disabled.value,
          onRequestChange: (nextOpen) => requestedStates.push(nextOpen),
        },
        {
          default: () =>
            h(
              "main",
              {
                id: "catalog-database-show-surface",
                class: "space-y-6",
                "data-state": open.value ? "closed" : "open",
                "data-disabled": disabled.value ? undefined : "child-stale",
                "data-server-root": "preserved",
              },
              [
                h("header", {id: "catalog-header"}, [
                  h(
                    CadenceCollapsibleTrigger,
                    null,
                    {
                      default: () =>
                        h(
                          "button",
                          {
                            id: "add-revision-toggle",
                            type: "button",
                            "aria-controls": "stale-child-content-id",
                            "aria-expanded": "true",
                            class: "btn",
                            disabled: !disabled.value,
                            "data-disabled": "child-stale",
                            "data-state": "child-stale",
                            "data-server-trigger": "preserved",
                          },
                          open.value ? "Cancel" : "+ Add revision",
                        ),
                    },
                  ),
                ]),
                h("section", {id: "database-summary"}, "Database"),
                h(
                  CadenceCollapsibleContent,
                  null,
                  {
                    default: () =>
                      h(
                        "div",
                        {
                          id: "stale-child-content-id",
                          "data-state": "child-stale",
                          "data-server-content": "preserved",
                        },
                        "Upload form",
                      ),
                  },
                ),
                h("section", {id: "catalog-revision-history"}, "Revision history"),
                h("section", {id: "catalog-import-attempts"}, "Import attempts"),
              ],
            ),
        },
      )
  },
})

const app = createApp(RuntimeOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const publicRoot = dom.window.document.querySelector("#catalog-database-show-surface")
const trigger = dom.window.document.querySelector("#add-revision-toggle")
const childIds = () => [...publicRoot.children].map((child) => child.id)

assert.equal(dom.window.document.querySelector("#app").children.length, 1)
assert.equal(publicRoot.parentElement.id, "app")
assert.equal(publicRoot.className, "space-y-6")
assert.equal(publicRoot.getAttribute("data-server-root"), "preserved")
assert.equal(publicRoot.getAttribute("data-state"), "closed")
assert.equal(publicRoot.getAttribute("data-disabled"), null)
assert.equal(trigger.getAttribute("aria-controls"), "catalog-revision-upload-slot")
assert.equal(trigger.getAttribute("aria-expanded"), "false")
assert.equal(trigger.disabled, false)
assert.equal(trigger.getAttribute("data-server-trigger"), "preserved")
assert.equal(dom.window.document.querySelector("#catalog-revision-upload-slot"), null)
assert.deepEqual(childIds(), [
  "catalog-header",
  "database-summary",
  "catalog-revision-history",
  "catalog-import-attempts",
])

trigger.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true])
assert.equal(publicRoot.getAttribute("data-state"), "closed")
assert.equal(trigger.getAttribute("aria-expanded"), "false")
assert.equal(dom.window.document.querySelector("#catalog-revision-upload-slot"), null)

open.value = true
await flushVue(nextTick)
const content = dom.window.document.querySelector("#catalog-revision-upload-slot")
assert.ok(content)
assert.equal(content.getAttribute("data-server-content"), "preserved")
assert.equal(content.getAttribute("data-state"), "open")
assert.equal(trigger.getAttribute("aria-controls"), content.id)
assert.equal(trigger.getAttribute("aria-expanded"), "true")
assert.equal(publicRoot.getAttribute("data-state"), "open")
assert.equal(publicRoot.getAttribute("data-disabled"), null)
assert.deepEqual(childIds(), [
  "catalog-header",
  "database-summary",
  "catalog-revision-upload-slot",
  "catalog-revision-history",
  "catalog-import-attempts",
])

trigger.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true, false])
assert.ok(
  dom.window.document.querySelector("#catalog-revision-upload-slot"),
  "content stays mounted until the server-authored prop closes it",
)

open.value = false
await flushVue(nextTick)
assert.equal(dom.window.document.querySelector("#catalog-revision-upload-slot"), null)
assert.equal(publicRoot.getAttribute("data-state"), "closed")
assert.deepEqual(childIds(), [
  "catalog-header",
  "database-summary",
  "catalog-revision-history",
  "catalog-import-attempts",
])

disabled.value = true
await flushVue(nextTick)
assert.equal(trigger.disabled, true)
assert.equal(trigger.getAttribute("data-disabled"), "")
assert.equal(publicRoot.getAttribute("data-disabled"), "")
trigger.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true, false])

disabled.value = false
await flushVue(nextTick)
assert.equal(trigger.disabled, false)
assert.equal(trigger.getAttribute("data-disabled"), null)
assert.equal(publicRoot.getAttribute("data-disabled"), null)

app.unmount()
dom.window.close()

console.log(`cadence_collapsible_adapter_test passed (${scenarios.length} scenarios)`)
