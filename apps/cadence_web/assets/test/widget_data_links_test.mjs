import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/WidgetDataLinks.vue")
const source = await readFile(componentPath, "utf8")

const controllerStart = "// WIDGET_DATA_LINKS_CONTROLLER_START"
const controllerEnd = "// WIDGET_DATA_LINKS_CONTROLLER_END"
const start = source.indexOf(controllerStart)
const end = source.indexOf(controllerEnd)

assert.ok(start >= 0, "WidgetDataLinks.vue should expose its colocated popover controller")
assert.ok(end > start, "WidgetDataLinks.vue should close its controller boundary")
assert.match(source, /<script setup lang="ts">/)
assert.match(source, /v-bind="presentation\.overlay\.attrs"/)
assert.match(source, /v-bind="presentation\.trigger\.attrs"/)
assert.match(source, /v-bind="presentation\.trigger\.content\.attrs"/)
assert.match(source, /v-bind="presentation\.panel\.attrs"/)
assert.match(source, /v-bind="item\.attrs"/)
assert.match(source, /:key="item\.key"/)
assert.doesNotMatch(source, /open_data_link|open_evidence/)

const controllerSource = source.slice(start + controllerStart.length, end)
assert.doesNotMatch(controllerSource, /setTimeout|setInterval/)
const context = {}
vm.createContext(context)
vm.runInContext(
  `${controllerSource}\nglobalThis.createWidgetDataLinksController = createWidgetDataLinksController`,
  context,
  {filename: componentPath},
)

const createController = context.createWidgetDataLinksController
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
    this.attributes = new Map()
    this.hidden = true
    this.style = {transform: ""}
    this.isConnected = true
    this.focusCount = 0
    this.rect = {left: 900, right: 1000}
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
  }

  querySelector(selector) {
    if (selector === ":scope > [data-overlay-trigger]") return this.trigger
    if (selector === ":scope > [data-overlay-panel]") return this.panel
    return null
  }

  contains(target) {
    return target === this || target === this.trigger || target === this.panel
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

const firstRoot = new FakeRoot("first")
const first = createController({rootElement: firstRoot, documentObject, windowObject})
first.mounted()

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

firstRoot.panel.dispatchEvent(event("click", {target: firstRoot.panel}))
assert.equal(first.state.open, true, "popover action clicks must not implicitly close the panel")

const closeEvent = event("click")
firstRoot.trigger.dispatchEvent(closeEvent)

assert.equal(closeEvent.defaultPrevented, true)
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.trigger.focusCount, 1)
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
  new FakeCustomEvent("cadence:overlay-opened", {detail: new FakeRoot("other")}),
)
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.focusCount, 2, "another overlay must dismiss without focus restore")

firstRoot.trigger.dispatchEvent(event("click"))
const oldTrigger = firstRoot.trigger
const oldPanel = firstRoot.panel
first.beforeUpdate()
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.trigger = new FakeElement("first-trigger-updated")
firstRoot.panel = new FakeElement("first-panel-updated")
firstRoot.panel.rect = {left: -4, right: 96}
first.updated()

assert.equal(first.state.open, true)
assert.equal(oldTrigger.listenerCount("click"), 0)
assert.equal(oldPanel.listenerCount("click"), 0)
assert.equal(firstRoot.trigger.listenerCount("click"), 1)
assert.equal(firstRoot.panel.listenerCount("click"), 1)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "true")
assert.equal(firstRoot.panel.hidden, false)
assert.equal(firstRoot.panel.style.transform, "translateX(20px)")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)

const secondRoot = new FakeRoot("second")
const second = createController({rootElement: secondRoot, documentObject, windowObject})
second.mounted()
secondRoot.trigger.dispatchEvent(event("click"))

assert.equal(first.state.open, false, "opening another local popover should close the first")
assert.equal(second.state.open, true)
assert.equal(firstRoot.trigger.focusCount, 0)

second.destroyed()
assert.equal(secondRoot.trigger.listenerCount("click"), 0)
assert.equal(secondRoot.panel.listenerCount("click"), 0)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 1)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

first.destroyed()
assert.equal(firstRoot.trigger.listenerCount("click"), 0)
assert.equal(firstRoot.panel.listenerCount("click"), 0)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 0)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

console.log("widget_data_links_test passed")
