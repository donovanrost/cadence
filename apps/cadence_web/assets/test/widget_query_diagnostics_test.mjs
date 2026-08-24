import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/WidgetQueryDiagnostics.vue")
const source = await readFile(componentPath, "utf8")
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

const controllerStart = "// WIDGET_QUERY_DIAGNOSTICS_CONTROLLER_START"
const controllerEnd = "// WIDGET_QUERY_DIAGNOSTICS_CONTROLLER_END"
const start = source.indexOf(controllerStart)
const end = source.indexOf(controllerEnd)

assert.ok(template, "WidgetQueryDiagnostics.vue must have a template block")
assert.ok(start >= 0, "WidgetQueryDiagnostics.vue should expose its colocated controller")
assert.ok(end > start, "WidgetQueryDiagnostics.vue should close its controller boundary")
assert.match(source, /<script setup lang="ts">/)
assert.match(source, /onBeforeUpdate/)
assert.match(source, /onUpdated/)
assert.match(source, /onBeforeUnmount/)
assert.match(template, /:id="props\.presentation\.overlay\.id"/)
assert.match(template, /v-bind="props\.presentation\.overlay\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.trigger\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.trigger\.content\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.panel\.attrs"/)
assert.match(template, /v-bind="row\.label\.attrs"/)
assert.match(template, /v-bind="row\.value\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.body\.evidence_button\.attrs"/)
assert.match(template, /:key="row\.key"/)
assert.doesNotMatch(template, /Widget query|Open query evidence|open_evidence|hero-|btn |cadence-/)
assert.doesNotMatch(source, /phx-hook|from ["']\.\.\/js\/hooks\/overlay/)
assert.doesNotMatch(source, /<script(?! setup)/)

const controllerSource = source.slice(start + controllerStart.length, end)
assert.doesNotMatch(controllerSource, /setTimeout|setInterval/)

const context = {}
vm.createContext(context)
vm.runInContext(
  `${controllerSource}\nglobalThis.createWidgetQueryDiagnosticsController = createWidgetQueryDiagnosticsController`,
  context,
  {filename: componentPath},
)

const createController = context.createWidgetQueryDiagnosticsController
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

const firstRoot = new FakeRoot("widget-query-first")
firstRoot.panel.rect = {left: 900, right: 1000}
const first = createController({rootElement: firstRoot, documentObject, windowObject})
first.mounted()

assert.equal(first.state.open, false, "the controller must begin closed")
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.trigger.listenerCount("click"), 1)
assert.equal(firstRoot.panel.listenerCount("click"), 1)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 1)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

const openEvent = event("click")
firstRoot.trigger.dispatchEvent(openEvent)

assert.equal(openEvent.defaultPrevented, true)
assert.equal(first.state.open, true)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "true")
assert.equal(firstRoot.panel.hidden, false)
assert.equal(firstRoot.hasAttribute("data-overlay-open"), true)
assert.equal(firstRoot.panel.style.transform, "translateX(-16px)")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)

const panelAction = new FakeElement("query-evidence-action")
firstRoot.panel.append(panelAction)
firstRoot.panel.dispatchEvent(event("click", {target: panelAction}))
assert.equal(first.state.open, true, "popover panel actions must not implicitly close")

const toggleCloseEvent = event("click")
firstRoot.trigger.dispatchEvent(toggleCloseEvent)

assert.equal(toggleCloseEvent.defaultPrevented, true)
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.trigger.focusCount, 1, "toggle close must restore trigger focus")
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.trigger.dispatchEvent(event("click"))
documentObject.dispatchEvent(event("pointerdown", {target: new FakeElement("outside")}))
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.focusCount, 1, "outside dismissal must not restore focus")

firstRoot.trigger.dispatchEvent(event("click"))
const escapeEvent = event("keydown", {key: "Escape"})
documentObject.dispatchEvent(escapeEvent)
assert.equal(escapeEvent.defaultPrevented, true)
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.focusCount, 2, "Escape dismissal must restore trigger focus")

firstRoot.trigger.dispatchEvent(event("click"))
windowObject.dispatchEvent(
  new FakeCustomEvent("cadence:overlay-opened", {detail: new FakeRoot("external-island")}),
)
assert.equal(first.state.open, false, "an external island opening must close this popover")
assert.equal(firstRoot.trigger.focusCount, 2, "cross-island close must not restore focus")

firstRoot.trigger.dispatchEvent(event("click"))
const oldTrigger = firstRoot.trigger
const oldPanel = firstRoot.panel
first.beforeUpdate()

assert.equal(oldPanel.style.transform, "", "beforeUpdate must clear stale positioning")
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.trigger = new FakeElement("widget-query-first-trigger-updated")
firstRoot.panel = new FakeElement("widget-query-first-panel-updated")
firstRoot.panel.hidden = true
firstRoot.panel.rect = {left: -4, right: 96}
first.updated()

assert.equal(first.state.open, true, "the same overlay identity must preserve open state")
assert.equal(oldTrigger.listenerCount("click"), 0)
assert.equal(oldPanel.listenerCount("click"), 0)
assert.equal(firstRoot.trigger.listenerCount("click"), 1)
assert.equal(firstRoot.panel.listenerCount("click"), 1)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "true")
assert.equal(firstRoot.panel.hidden, false)
assert.equal(firstRoot.panel.style.transform, "translateX(20px)")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)

first.beforeUpdate()
firstRoot.id = "widget-query-first-replacement"
first.updated()

assert.equal(first.state.open, false, "an overlay identity replacement must close")
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.panel.style.transform, "")
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.trigger.dispatchEvent(event("click"))
const removedTrigger = firstRoot.trigger
const removedPanel = firstRoot.panel
first.beforeUpdate()
firstRoot.trigger = null
firstRoot.panel = null
first.updated()

assert.equal(first.state.open, false, "a removed overlay identity must close")
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(removedTrigger.listenerCount("click"), 0)
assert.equal(removedPanel.listenerCount("click"), 0)
assert.equal(removedPanel.style.transform, "")
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.trigger = new FakeElement("widget-query-first-replacement-trigger")
firstRoot.panel = new FakeElement("widget-query-first-replacement-panel")
firstRoot.panel.hidden = true
firstRoot.panel.rect = {left: 900, right: 1000}
first.updated()
firstRoot.trigger.dispatchEvent(event("click"))

const secondRoot = new FakeRoot("widget-query-second")
const second = createController({rootElement: secondRoot, documentObject, windowObject})
second.mounted()
secondRoot.trigger.dispatchEvent(event("click"))

assert.equal(first.state.open, false, "opening another local diagnostics island closes the first")
assert.equal(second.state.open, true)
assert.equal(firstRoot.trigger.focusCount, 0, "one-open coordination must not steal focus")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 2)

windowObject.dispatchEvent(
  new FakeCustomEvent("cadence:overlay-opened", {detail: new FakeRoot("other-component")}),
)
assert.equal(second.state.open, false, "cross-component overlay coordination must close")
assert.equal(secondRoot.trigger.focusCount, 0)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.trigger.dispatchEvent(event("click"))
assert.notEqual(firstRoot.panel.style.transform, "")
first.destroyed()

assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.panel.style.transform, "", "destroy must clear positioning styles")
assert.equal(firstRoot.trigger.listenerCount("click"), 0)
assert.equal(firstRoot.panel.listenerCount("click"), 0)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 1)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

second.destroyed()
assert.equal(secondRoot.trigger.listenerCount("click"), 0)
assert.equal(secondRoot.panel.listenerCount("click"), 0)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 0)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

console.log("widget_query_diagnostics_test passed")
