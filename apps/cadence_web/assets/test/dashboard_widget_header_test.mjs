import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const nodeScenarioLedger = [
  "direct presenter composition and single host preserve the global Overlay registration",
  "mount toggle viewport positioning and panel clicks preserve popover state",
  "outside click and Escape preserve dismissal and focus behavior",
  "global overlay coordination closes the widget details popover without stealing focus",
  "component updates preserve only the matching open overlay identity",
  "component teardown clears overlay state position focus listeners and document listeners",
]

assert.equal(nodeScenarioLedger.length, 6)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/DashboardWidgetHeader.vue")
const componentsPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/components.ex",
)
const appPath = resolve(__dirname, "../js/app.js")
const overlayHookPath = resolve(__dirname, "../js/hooks/overlay.js")

const [source, componentsSource, appSource, overlayHookSource] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(componentsPath, "utf8"),
  readFile(appPath, "utf8"),
  readFile(overlayHookPath, "utf8"),
])

const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const controllerStart = "// DASHBOARD_WIDGET_HEADER_CONTROLLER_START"
const controllerEnd = "// DASHBOARD_WIDGET_HEADER_CONTROLLER_END"
const start = source.indexOf(controllerStart)
const end = source.indexOf(controllerEnd)
const headerHostSource = componentsSource.match(
  /defp widget_header\(assigns\) do[\s\S]*?def widget_header_presentation\(assigns\) do/,
)?.[0]

assert.ok(template, "DashboardWidgetHeader.vue must have a template block")
assert.ok(start >= 0, "DashboardWidgetHeader.vue should expose its colocated controller")
assert.ok(end > start, "DashboardWidgetHeader.vue should close its controller boundary")
assert.ok(headerHostSource, "Components.widget_header/1 must remain an auditable host boundary")

assert.match(source, /import WidgetDataLinks from "\.\/WidgetDataLinks\.vue"/)
assert.match(source, /import WidgetQueryDiagnostics from "\.\/WidgetQueryDiagnostics\.vue"/)
assert.match(source, /import WidgetWarning from "\.\/WidgetWarning\.vue"/)
assert.match(template, /<WidgetDataLinks/)
assert.match(template, /<WidgetQueryDiagnostics/)
assert.match(template, /<WidgetWarning/)
assert.match(template, /:id="warning\.component_id"/)
assert.match(template, /actions\.query\.component_id/)
assert.match(template, /actions\.data_links\.component_id/)
assert.match(template, /v-bind="props\.presentation\.root\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.actions\.details\.overlay\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.actions\.details\.trigger\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.actions\.details\.panel\.attrs"/)
assert.doesNotMatch(source, /phx-hook|data-name=|<\.vue|v-component=/)

assert.match(headerHostSource, /v-component="DashboardWidgetHeader"/)
assert.match(headerHostSource, /v-ssr=\{false\}/)
assert.match(headerHostSource, /class="contents"/)
assert.equal(headerHostSource.match(/<\.vue/g)?.length, 1)
assert.doesNotMatch(headerHostSource, /phx-hook="Overlay"|WidgetDataLinks|WidgetQueryDiagnostics|WidgetWarning/)

assert.match(appSource, /import Overlay from "\.\/hooks\/overlay"/)
assert.match(appSource, /Overlay,/)
assert.match(overlayHookSource, /const Overlay = \{/)
assert.match(overlayHookSource, /cadence:overlay-opened/)

const controllerSource = source.slice(start + controllerStart.length, end)
assert.doesNotMatch(controllerSource, /setTimeout|setInterval/)

const context = {}
vm.createContext(context)
vm.runInContext(
  `${controllerSource}\nglobalThis.createDashboardWidgetHeaderController = createDashboardWidgetHeaderController`,
  context,
  {filename: componentPath},
)

const createController = context.createDashboardWidgetHeaderController
assert.equal(typeof createController, "function")

class FakeEventTarget {
  constructor() {
    this.listeners = new Map()
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) || new Set()
    listeners.add(listener)
    this.listeners.set(type, listeners)
  }

  removeEventListener(type, listener) {
    this.listeners.get(type)?.delete(listener)
  }

  dispatchEvent(event) {
    event.target ||= this
    for (const listener of this.listeners.get(event.type) || []) listener(event)
    return true
  }

  listenerCount(type) {
    return this.listeners.get(type)?.size || 0
  }
}

class FakeElement extends FakeEventTarget {
  constructor(name) {
    super()
    this.name = name
    this.id = name
    this.attributes = new Map()
    this.children = []
    this.hidden = false
    this.style = {transform: ""}
    this.isConnected = true
    this.focusCount = 0
    this.rect = {left: 20, right: 200}
  }

  append(...children) {
    this.children.push(...children)
  }

  setAttribute(name, value) {
    this.attributes.set(name, value)
  }

  toggleAttribute(name, force) {
    if (force) this.attributes.set(name, "")
    else this.attributes.delete(name)
  }

  hasAttribute(name) {
    return this.attributes.has(name)
  }

  contains(target) {
    return target === this || this.children.some((child) => child.contains(target))
  }

  focus() {
    this.focusCount += 1
  }

  getBoundingClientRect() {
    return this.rect
  }
}

class FakeRoot extends FakeElement {
  constructor(name) {
    super(name)
    this.trigger = new FakeElement(`${name}-trigger`)
    this.panel = new FakeElement(`${name}-panel`)
    this.trigger.setAttribute("aria-expanded", "false")
    this.panel.hidden = true
  }

  querySelector(selector) {
    if (selector === ":scope > [data-overlay-trigger]") return this.trigger
    if (selector === ":scope > [data-overlay-panel]") return this.panel
    return null
  }

  contains(target) {
    return (
      target === this ||
      this.trigger?.contains(target) ||
      this.panel?.contains(target) ||
      false
    )
  }
}

class FakeCustomEvent {
  constructor(type, options) {
    this.type = type
    this.detail = options.detail
  }
}

const event = (type, attrs = {}) => ({
  type,
  defaultPrevented: false,
  preventDefault() {
    this.defaultPrevented = true
  },
  ...attrs,
})

const documentObject = new FakeEventTarget()
const windowObject = new FakeEventTarget()
windowObject.CustomEvent = FakeCustomEvent
windowObject.innerWidth = 1000

const root = new FakeRoot("widget-details-placement-1")
root.panel.rect = {left: 900, right: 1000}
const controller = createController({rootElement: root, documentObject, windowObject})
controller.mounted()

assert.equal(controller.state.open, false)
assert.equal(root.trigger.attributes.get("aria-expanded"), "false")
assert.equal(root.panel.hidden, true)
assert.equal(root.hasAttribute("data-overlay-open"), false)
assert.equal(root.trigger.listenerCount("click"), 1)
assert.equal(root.panel.listenerCount("click"), 1)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 1)

const openEvent = event("click")
root.trigger.dispatchEvent(openEvent)
assert.equal(openEvent.defaultPrevented, true)
assert.equal(controller.state.open, true)
assert.equal(root.trigger.attributes.get("aria-expanded"), "true")
assert.equal(root.panel.hidden, false)
assert.equal(root.hasAttribute("data-overlay-open"), true)
assert.equal(root.panel.style.transform, "translateX(-16px)")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)

const panelAction = new FakeElement("header-panel-action")
root.panel.append(panelAction)
root.panel.dispatchEvent(event("click", {target: panelAction}))
assert.equal(controller.state.open, true, "popover actions must not implicitly close")

root.trigger.dispatchEvent(event("click"))
assert.equal(controller.state.open, false)
assert.equal(root.trigger.focusCount, 1, "toggle close must restore trigger focus")

root.trigger.dispatchEvent(event("click"))
documentObject.dispatchEvent(event("pointerdown", {target: new FakeElement("outside")}))
assert.equal(controller.state.open, false)
assert.equal(root.trigger.focusCount, 1, "outside dismissal must not restore focus")

root.trigger.dispatchEvent(event("click"))
const escapeEvent = event("keydown", {key: "Escape"})
documentObject.dispatchEvent(escapeEvent)
assert.equal(escapeEvent.defaultPrevented, true)
assert.equal(controller.state.open, false)
assert.equal(root.trigger.focusCount, 2, "Escape dismissal must restore trigger focus")

root.trigger.dispatchEvent(event("click"))
windowObject.dispatchEvent(
  new FakeCustomEvent("cadence:overlay-opened", {detail: new FakeRoot("toolbar-overlay")}),
)
assert.equal(controller.state.open, false, "another overlay must close widget details")
assert.equal(root.trigger.focusCount, 2, "global coordination must not steal focus")

root.trigger.dispatchEvent(event("click"))
const oldTrigger = root.trigger
const oldPanel = root.panel
controller.beforeUpdate()
assert.equal(oldPanel.style.transform, "")
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

root.trigger = new FakeElement("widget-details-placement-1-trigger-updated")
root.panel = new FakeElement("widget-details-placement-1-panel-updated")
root.panel.hidden = true
root.panel.rect = {left: -4, right: 96}
controller.updated()
assert.equal(controller.state.open, true, "the same overlay identity must preserve open state")
assert.equal(oldTrigger.listenerCount("click"), 0)
assert.equal(oldPanel.listenerCount("click"), 0)
assert.equal(root.trigger.listenerCount("click"), 1)
assert.equal(root.panel.listenerCount("click"), 1)
assert.equal(root.panel.style.transform, "translateX(20px)")

controller.beforeUpdate()
root.id = "widget-details-placement-2"
controller.updated()
assert.equal(controller.state.open, false, "an overlay identity replacement must close")
assert.equal(root.trigger.attributes.get("aria-expanded"), "false")
assert.equal(root.panel.hidden, true)
assert.equal(root.panel.style.transform, "")

root.trigger.dispatchEvent(event("click"))
controller.destroyed()
assert.equal(controller.state.open, false)
assert.equal(root.trigger.attributes.get("aria-expanded"), "false")
assert.equal(root.panel.hidden, true)
assert.equal(root.hasAttribute("data-overlay-open"), false)
assert.equal(root.panel.style.transform, "")
assert.equal(root.trigger.listenerCount("click"), 0)
assert.equal(root.panel.listenerCount("click"), 0)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 0)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

console.log("dashboard_widget_header_test passed")
