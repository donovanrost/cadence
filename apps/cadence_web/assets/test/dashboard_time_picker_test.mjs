import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/DashboardTimePicker.vue")
const source = await readFile(componentPath, "utf8")
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

const controllerStart = "// DASHBOARD_TIME_PICKER_CONTROLLER_START"
const controllerEnd = "// DASHBOARD_TIME_PICKER_CONTROLLER_END"
const start = source.indexOf(controllerStart)
const end = source.indexOf(controllerEnd)

assert.ok(template, "DashboardTimePicker.vue must have a template block")
assert.ok(start >= 0, "DashboardTimePicker.vue should expose its colocated overlay controller")
assert.ok(end > start, "DashboardTimePicker.vue should close its controller boundary")
assert.match(source, /from "\.\/DashboardAbsoluteRangePane\.vue"/)
assert.match(source, /from "\.\/DashboardQuickRangeList\.vue"/)
assert.match(source, /from "\.\/DashboardTimeReplay\.vue"/)
assert.match(source, /from "\.\/DashboardSelectedDatumActions\.vue"/)
assert.match(source, /onBeforeUpdate/)
assert.match(source, /onUpdated/)
assert.match(source, /onBeforeUnmount/)
assert.match(template, /v-bind="props\.presentation\.overlay\.root\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.overlay\.trigger\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.overlay\.panel\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.shift_back\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.shift_forward\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.zoom_out\.attrs"/)
assert.match(template, /@recents-loaded="forwardRecentsLoaded"/)
assert.match(template, /@select-range="forwardSelectRange"/)
assert.match(template, /v-bind="props\.presentation\.time_picker\.absolute_range_host\.attrs"/)
assert.match(template, /:presentation="props\.presentation\.time_picker\.quick_ranges"/)
assert.match(template, /v-bind="props\.presentation\.time_picker\.quick_ranges_host\.attrs"/)
assert.match(template, /v-bind="props\.presentation\.replay_host\.attrs"/)
assert.match(template, /:presentation="props\.presentation\.replay"/)
assert.match(template, /v-bind="props\.presentation\.selected_datum_host\.attrs"/)
assert.match(template, /:presentation="props\.presentation\.selected_datum"/)
assert.doesNotMatch(source, /phx-hook|hooks\/overlay|\bOverlay\b/)
assert.doesNotMatch(source, /data-name/)
assert.doesNotMatch(source, /<script(?! setup)/)

const controllerSource = source.slice(start + controllerStart.length, end)
assert.doesNotMatch(controllerSource, /setTimeout|setInterval/)

const context = {}
vm.createContext(context)
vm.runInContext(
  `${controllerSource}\nglobalThis.createDashboardTimePickerController = createDashboardTimePickerController`,
  context,
  {filename: componentPath},
)

const createController = context.createDashboardTimePickerController
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

const firstRoot = new FakeRoot("dashboard-time-controls")
firstRoot.panel.rect = {left: 900, right: 1000}
const first = createController({rootElement: firstRoot, documentObject, windowObject})
first.mounted()

assert.equal(first.state.open, false, "the time popover must begin closed")
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

const formAction = new FakeElement("dashboard-apply-time-range")
firstRoot.panel.append(formAction)
firstRoot.panel.dispatchEvent(event("click", {target: formAction}))
assert.equal(first.state.open, true, "time-control actions must not implicitly close the popover")

const toggleCloseEvent = event("click")
firstRoot.trigger.dispatchEvent(toggleCloseEvent)
assert.equal(toggleCloseEvent.defaultPrevented, true)
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.trigger.focusCount, 1, "toggle close must restore trigger focus")

firstRoot.trigger.dispatchEvent(event("click"))
documentObject.dispatchEvent(event("pointerdown", {target: new FakeElement("outside")}))
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.focusCount, 1, "outside dismissal must not steal focus")

firstRoot.trigger.dispatchEvent(event("click"))
const escapeEvent = event("keydown", {key: "Escape"})
documentObject.dispatchEvent(escapeEvent)
assert.equal(escapeEvent.defaultPrevented, true)
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.focusCount, 2, "Escape dismissal must restore trigger focus")

firstRoot.trigger.dispatchEvent(event("click"))
windowObject.dispatchEvent(
  new FakeCustomEvent("cadence:overlay-opened", {detail: new FakeRoot("external-overlay")}),
)
assert.equal(first.state.open, false, "another overlay opening must close the time popover")
assert.equal(firstRoot.trigger.focusCount, 2, "coordination dismissal must not steal focus")

firstRoot.trigger.dispatchEvent(event("click"))
const oldTrigger = firstRoot.trigger
const oldPanel = firstRoot.panel
first.beforeUpdate()
assert.equal(oldPanel.style.transform, "", "beforeUpdate must clear stale positioning")
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.trigger = new FakeElement("dashboard-time-controls-toggle-updated")
firstRoot.panel = new FakeElement("dashboard-time-controls-panel-updated")
firstRoot.panel.hidden = true
firstRoot.panel.rect = {left: -4, right: 96}
first.updated()

assert.equal(first.state.open, true, "the stable overlay identity must preserve open state")
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
firstRoot.id = "dashboard-time-controls-replacement"
first.updated()
assert.equal(first.state.open, false, "an overlay identity replacement must close")
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.panel.style.transform, "")

firstRoot.trigger.dispatchEvent(event("click"))
const removedTrigger = firstRoot.trigger
const removedPanel = firstRoot.panel
first.beforeUpdate()
firstRoot.trigger = null
firstRoot.panel = null
first.updated()
assert.equal(first.state.open, false, "removed overlay elements must close")
assert.equal(removedTrigger.listenerCount("click"), 0)
assert.equal(removedPanel.listenerCount("click"), 0)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

firstRoot.id = "dashboard-time-controls"
firstRoot.trigger = new FakeElement("dashboard-time-controls-toggle")
firstRoot.panel = new FakeElement("dashboard-time-controls-panel")
firstRoot.panel.hidden = true
first.updated()
firstRoot.trigger.dispatchEvent(event("click"))

const secondRoot = new FakeRoot("dashboard-time-controls-second")
const second = createController({rootElement: secondRoot, documentObject, windowObject})
second.mounted()
secondRoot.trigger.dispatchEvent(event("click"))

assert.equal(first.state.open, false, "opening another local time picker must close the first")
assert.equal(second.state.open, true)
assert.equal(firstRoot.trigger.focusCount, 0, "one-open coordination must not move focus")
assert.equal(documentObject.listenerCount("pointerdown"), 1)
assert.equal(documentObject.listenerCount("keydown"), 1)

windowObject.dispatchEvent(
  new FakeCustomEvent("cadence:overlay-opened", {detail: new FakeRoot("other-component")}),
)
assert.equal(second.state.open, false, "cross-component overlay coordination must close")
assert.equal(secondRoot.trigger.focusCount, 0)

firstRoot.trigger.dispatchEvent(event("click"))
first.destroyed()
assert.equal(first.state.open, false)
assert.equal(firstRoot.trigger.attributes.get("aria-expanded"), "false")
assert.equal(firstRoot.panel.hidden, true)
assert.equal(firstRoot.hasAttribute("data-overlay-open"), false)
assert.equal(firstRoot.panel.style.transform, "")
assert.equal(firstRoot.trigger.listenerCount("click"), 0)
assert.equal(firstRoot.panel.listenerCount("click"), 0)
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 1)
assert.equal(documentObject.listenerCount("pointerdown"), 0)
assert.equal(documentObject.listenerCount("keydown"), 0)

second.destroyed()
assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 0)

console.log("dashboard_time_picker_test passed")
