import assert from "node:assert/strict"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {assertPinnedAdapterRuntime, flushVue, installDom, integrationRequire, loadSfc} from "./reka_adapter_test_support.mjs"

const scenarios = ["toggle-position-panel", "outside-escape-focus", "nested-escape", "peer-coordination", "identity-update", "teardown"]
assert.equal(scenarios.length, 6)
const dir = dirname(fileURLToPath(import.meta.url))
await assertPinnedAdapterRuntime(resolve(dir, "../../package-lock.json"))
const dom = installDom('<div id="app"></div>')
globalThis.HTMLInputElement = dom.window.HTMLInputElement
const {component: CadencePopover} = await loadSfc(resolve(dir, "../vue/ui/reka/CadencePopover.vue"))
assert.match((await loadSfc(resolve(dir, "../vue/ui/reka/CadencePopover.vue"))).source, /handleEscapeKeyDown[\s\S]*data-overlay-open[\s\S]*suppressEscapeDismiss = true/)
const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

const identity = ref("widget-details-root")
const app = createApp(defineComponent({
  setup() {
    return () => h(CadencePopover, {id: "widget-details-root", identity: identity.value, side: "bottom", align: "end", sideOffset: 8, collisionPadding: 16}, {
      trigger: ({open}) => h("button", {id: "details-trigger", type: "button", "data-overlay-trigger": "", "aria-expanded": String(open)}, "Details"),
      content: ({open}) => h("section", {id: "details-panel", "data-overlay-panel": "", hidden: !open}, [
        h("button", {id: "panel-action", type: "button"}, "Action"),
        h("div", {id: "nested-overlay", "data-overlay-open": ""}, "Nested"),
      ]),
    })
  },
}))
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)
const trigger = () => dom.window.document.querySelector("#details-trigger")
const panel = () => dom.window.document.querySelector("#details-panel")
assert.equal(trigger().getAttribute("aria-expanded"), "false")
trigger().dispatchEvent(new dom.window.MouseEvent("pointerdown", {bubbles: true}))
trigger().click()
await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "true")
assert.equal(panel().hidden, false)
panel().querySelector("#panel-action").click()
assert.equal(trigger().getAttribute("aria-expanded"), "true")

const outside = dom.window.document.createElement("button")
outside.id = "outside"
dom.window.document.body.append(outside)
outside.focus()
outside.dispatchEvent(new dom.window.MouseEvent("pointerdown", {bubbles: true}))
await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "false")
trigger().focus(); trigger().dispatchEvent(new dom.window.MouseEvent("pointerdown", {bubbles: true})); trigger().click(); await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "true", "parent reopens before nested Escape")
dom.window.document.querySelector("#nested-overlay").setAttribute("data-overlay-open", "")
dom.window.document.querySelector("#nested-overlay").addEventListener("keydown", (event) => {
  event.preventDefault()
  event.stopPropagation()
}, {once: true})
dom.window.document.querySelector("#nested-overlay").dispatchEvent(new dom.window.KeyboardEvent("keydown", {key: "Escape", bubbles: true}))
await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "true", "nested Escape leaves parent open")
panel().dispatchEvent(new dom.window.KeyboardEvent("keydown", {key: "Escape", bubbles: true}))
await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "true", "panel Escape is blocked while nested overlay is open")
dom.window.document.querySelector("#nested-overlay").removeAttribute("data-overlay-open")
panel().dispatchEvent(new dom.window.KeyboardEvent("keydown", {key: "Escape", bubbles: true}))
await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "false")
assert.equal(dom.window.document.activeElement, trigger(), "Escape restores trigger focus")

trigger().dispatchEvent(new dom.window.MouseEvent("pointerdown", {bubbles: true})); trigger().click(); await flushVue(nextTick)
const peer = dom.window.document.createElement("div")
dom.window.document.body.append(peer)
announcePeer(peer)
await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "false", "peer coordination closes without focus work")

trigger().dispatchEvent(new dom.window.MouseEvent("pointerdown", {bubbles: true})); trigger().click(); await flushVue(nextTick)
identity.value = "widget-details-root"; await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "true")
identity.value = "replacement"; await flushVue(nextTick)
assert.equal(trigger().getAttribute("aria-expanded"), "false")

app.unmount(); await flushVue(nextTick)
assert.equal(dom.window.document.querySelector("#details-trigger"), null)

function announcePeer(root) {
  dom.window.dispatchEvent(new dom.window.CustomEvent("cadence:overlay-opened", {detail: root}))
}

console.log("dashboard_widget_popover_reka_test passed")
