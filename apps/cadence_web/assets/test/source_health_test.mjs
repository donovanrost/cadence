import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/SourceHealth.vue")
const source = await readFile(componentPath, "utf8")
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

const controllerStart = "// SOURCE_HEALTH_CONTROLLER_START"
const controllerEnd = "// SOURCE_HEALTH_CONTROLLER_END"
const start = source.indexOf(controllerStart)
const end = source.indexOf(controllerEnd)

assert.ok(template, "SourceHealth.vue must have a template block")
assert.ok(start >= 0, "SourceHealth.vue should expose its colocated popover controller")
assert.ok(end > start, "SourceHealth.vue should close its controller boundary")
assert.match(source, /<script setup lang="ts">/)
assert.match(source, /onBeforeUpdate/)
assert.match(source, /onUpdated/)
assert.match(source, /onBeforeUnmount/)
assert.match(template, /:id="presentation\.root\.id"/)
assert.match(template, /v-bind="presentation\.root\.attrs"/)
assert.match(template, /v-bind="source\.overlay\.attrs"/)
assert.match(template, /v-bind="source\.trigger\.attrs"/)
assert.match(template, /v-bind="source\.badge\.attrs"/)
assert.match(template, /v-bind="source\.panel\.attrs"/)
assert.match(template, /v-if="source\.details\.circuit\.visible"/)
assert.match(template, /v-bind="source\.details\.evidence\.attrs"/)
assert.match(template, /v-bind="row\.value\.attrs"/)
assert.match(template, /:key="source\.key"/)
assert.match(template, /:key="row\.key"/)
assert.doesNotMatch(template, /open_evidence|Source status|Inspect evidence|bottom-end|badge-/)
assert.doesNotMatch(source, /<script(?! setup)/)

const controllerSource = source.slice(start + controllerStart.length, end)
assert.doesNotMatch(controllerSource, /setTimeout|setInterval/)

const context = {}
vm.createContext(context)
vm.runInContext(
  `${controllerSource}\nglobalThis.createSourceHealthController = createSourceHealthController`,
  context,
  {filename: componentPath},
)

const createController = context.createSourceHealthController
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
  constructor(id, attrs = []) {
    super()
    this.id = id
    this.attributes = new Map(attrs.map((name) => [name, ""]))
    this.children = []
    this.parent = null
    this.hidden = false
    this.style = {transform: ""}
    this.isConnected = true
    this.focusCount = 0
    this.rect = {left: 20, right: 200}
  }

  append(...children) {
    for (const child of children) {
      child.parent = this
      this.children.push(child)
    }
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

  closest(selector) {
    const attr = selector.match(/^\[([^=\]]+)/)?.[1]
    if (attr && this.hasAttribute(attr)) return this
    return this.parent?.closest(selector) || null
  }

  querySelector(selector) {
    if (selector === ":scope > [data-overlay-trigger]") {
      return this.children.find((child) => child.hasAttribute("data-overlay-trigger")) || null
    }
    if (selector === ":scope > [data-overlay-panel]") {
      return this.children.find((child) => child.hasAttribute("data-overlay-panel")) || null
    }
    return null
  }

  querySelectorAll(selector) {
    if (selector === ":scope > [data-overlay-kind='popover']") {
      return this.children.filter(
        (child) => child.attributes.get("data-overlay-kind") === "popover",
      )
    }
    return []
  }

  getBoundingClientRect() {
    return this.rect
  }

  focus() {
    this.focusCount += 1
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

const popover = (id, rect) => {
  const overlay = new FakeElement(id, ["data-overlay-kind"])
  overlay.attributes.set("data-overlay-kind", "popover")
  const trigger = new FakeElement(`${id}-trigger`, ["data-overlay-trigger"])
  const badge = new FakeElement(`${id}-badge`)
  const panel = new FakeElement(`${id}-panel`, ["data-overlay-panel"])
  const evidence = new FakeElement(`${id}-evidence`)
  panel.hidden = true
  panel.rect = rect
  trigger.append(badge)
  panel.append(evidence)
  overlay.append(trigger, panel)
  return {overlay, trigger, badge, panel, evidence}
}

const documentObject = new FakeEventTarget()
const windowObject = new FakeEventTarget()
windowObject.CustomEvent = FakeCustomEvent
windowObject.innerWidth = 1000

const rootElement = new FakeElement("dashboard-source-health")
let first = popover("source-health-first", {left: 900, right: 1000})
let second = popover("source-health-second", {left: 20, right: 200})
rootElement.append(first.overlay, second.overlay)

const controller = createController({rootElement, documentObject, windowObject})
controller.mounted()

assert.equal(rootElement.listenerCount("click"), 1)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 1)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)
assert.equal(first.trigger.attributes.get("aria-expanded"), "false")
assert.equal(first.panel.hidden, true)
assert.equal(first.overlay.hasAttribute("data-overlay-open"), false)

const openEvent = event("click", {target: first.badge})
rootElement.dispatchEvent(openEvent)

assert.equal(openEvent.defaultPrevented, true)
assert.equal(controller.state.openIndex, 0)
assert.equal(first.trigger.attributes.get("aria-expanded"), "true")
assert.equal(first.panel.hidden, false)
assert.equal(first.overlay.hasAttribute("data-overlay-open"), true)
assert.equal(first.panel.style.transform, "translateX(-16px)")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)

rootElement.dispatchEvent(event("click", {target: first.evidence}))
assert.equal(controller.state.openIndex, 0, "popover actions must not implicitly close")

const secondOpenEvent = event("click", {target: second.trigger})
rootElement.dispatchEvent(secondOpenEvent)
assert.equal(secondOpenEvent.defaultPrevented, true)
assert.equal(controller.state.openIndex, 1)
assert.equal(first.panel.hidden, true)
assert.equal(first.overlay.hasAttribute("data-overlay-open"), false)
assert.equal(first.trigger.focusCount, 0, "one-open dismissal must not restore focus")
assert.equal(second.panel.hidden, false)

const toggleCloseEvent = event("click", {target: second.trigger})
rootElement.dispatchEvent(toggleCloseEvent)
assert.equal(toggleCloseEvent.defaultPrevented, true)
assert.equal(controller.state.openIndex, null)
assert.equal(second.trigger.focusCount, 1)
assert.equal(second.trigger.attributes.get("aria-expanded"), "false")
assert.equal(second.panel.hidden, true)
assert.equal(second.overlay.hasAttribute("data-overlay-open"), false)

rootElement.dispatchEvent(event("click", {target: first.trigger}))
documentObject.dispatchEvent(event("pointerdown", {target: new FakeElement("outside")}))
assert.equal(controller.state.openIndex, null)
assert.equal(first.trigger.focusCount, 0, "outside dismissal must not restore focus")

rootElement.dispatchEvent(event("click", {target: first.trigger}))
const escapeEvent = event("keydown", {key: "Escape"})
documentObject.dispatchEvent(escapeEvent)
assert.equal(escapeEvent.defaultPrevented, true)
assert.equal(controller.state.openIndex, null)
assert.equal(first.trigger.focusCount, 1, "Escape dismissal must restore trigger focus")

rootElement.dispatchEvent(event("click", {target: first.trigger}))
windowObject.dispatchEvent(
  new FakeCustomEvent("cadence:overlay-opened", {
    detail: new FakeElement("external-overlay"),
  }),
)
assert.equal(controller.state.openIndex, null)
assert.equal(first.trigger.focusCount, 1, "external overlay dismissal must not restore focus")

rootElement.dispatchEvent(event("click", {target: first.trigger}))
controller.beforeUpdate()
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

first = popover("source-health-first", {left: -4, right: 96})
second = popover("source-health-second", {left: 20, right: 200})
rootElement.children = []
rootElement.append(first.overlay, second.overlay)
controller.updated()

assert.equal(controller.state.openIndex, 0)
assert.equal(first.trigger.attributes.get("aria-expanded"), "true")
assert.equal(first.panel.hidden, false)
assert.equal(first.overlay.hasAttribute("data-overlay-open"), true)
assert.equal(first.panel.style.transform, "translateX(20px)")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)

controller.beforeUpdate()
first = popover("source-health-first", {left: 20, right: 200})
second = popover("source-health-second", {left: 20, right: 200})
rootElement.children = []
rootElement.append(second.overlay, first.overlay)
controller.updated()
assert.equal(controller.state.openIndex, 1, "updates must preserve the open overlay by identity")
assert.equal(first.panel.hidden, false)
assert.equal(second.panel.hidden, true)

controller.beforeUpdate()
rootElement.children = []
controller.updated()
assert.equal(controller.state.openIndex, null, "a removed open overlay must close on update")
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

controller.destroyed()
assert.equal(rootElement.listenerCount("click"), 0)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 0)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

console.log("source_health_test passed")
