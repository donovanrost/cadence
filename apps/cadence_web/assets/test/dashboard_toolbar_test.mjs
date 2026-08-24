import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const testDirectory = dirname(fileURLToPath(import.meta.url))
const toolbarPath = resolve(testDirectory, "../vue/DashboardToolbar.vue")
const menuPath = resolve(testDirectory, "../vue/DashboardToolbarMenu.vue")
const serverPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_toolbar_components.ex",
)
const warningPresenterPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_toolbar_warning_presentation.ex",
)
const appPath = resolve(testDirectory, "../js/app.js")

const [source, menuSource, serverSource, warningPresenterSource, appSource] = await Promise.all([
  readFile(toolbarPath, "utf8"),
  readFile(menuPath, "utf8"),
  readFile(serverPath, "utf8"),
  readFile(warningPresenterPath, "utf8"),
  readFile(appPath, "utf8"),
])
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

const scenarioLedger = Object.freeze([
  "one parent LiveVue host",
  "direct runtime context child",
  "direct runtime controls child",
  "direct canonical time picker child",
  "direct comparison toggle child",
  "direct editor actions child",
  "direct warning badge children",
  "direct action menu child",
  "no nested LiveVue roots",
  "time picker payload forwarding",
  "operational scope popover contract",
  "data health popover contract",
  "cross-overlay opened coordination",
  "viewport gutter positioning",
  "update-state preservation",
  "Escape close and focus return",
  "outside-click close without focus theft",
  "popover listener cleanup",
  "menu focus and keyboard semantics",
  "global Overlay hook retained",
])
const coveredScenarios = []
const cover = (name, callback) => {
  assert.equal(name, scenarioLedger[coveredScenarios.length])
  callback()
  coveredScenarios.push(name)
}

cover("one parent LiveVue host", () => {
  assert.equal((serverSource.match(/<\.vue/g) || []).length, 1)
  assert.equal((serverSource.match(/v-component="DashboardToolbar"/g) || []).length, 1)
})

cover("direct runtime context child", () => {
  assert.match(source, /import DashboardRuntimeContextSelector from "\.\/DashboardRuntimeContextSelector\.vue"/)
  assert.match(template, /<DashboardRuntimeContextSelector/)
})

cover("direct runtime controls child", () => {
  assert.match(source, /import DashboardRuntimeControls from "\.\/DashboardRuntimeControls\.vue"/)
  assert.match(template, /<DashboardRuntimeControls/)
})

cover("direct canonical time picker child", () => {
  assert.match(source, /import DashboardTimePicker from "\.\/DashboardTimePicker\.vue"/)
  assert.match(template, /<DashboardTimePicker/)
  assert.match(serverSource, /Map\.put\(:quick_query, assigns\.time_quick_query\)/)
  assert.match(serverSource, /Map\.put\(:recent_ranges, assigns\.time_recent_ranges\)/)
  assert.match(
    serverSource,
    /DashboardTimePickerComponents\.time_toolbar_presentation\(time_picker_assigns\)/,
  )
})

cover("direct comparison toggle child", () => {
  assert.match(source, /import DashboardComparisonToggle from "\.\/DashboardComparisonToggle\.vue"/)
  assert.match(template, /<DashboardComparisonToggle/)
})

cover("direct editor actions child", () => {
  assert.match(source, /import DashboardEditorActions from "\.\/DashboardEditorActions\.vue"/)
  assert.match(template, /<DashboardEditorActions/)
})

cover("direct warning badge children", () => {
  assert.match(source, /import WidgetWarning from "\.\/WidgetWarning\.vue"/)
  assert.match(template, /<WidgetWarning :presentation="warning"/)
  assert.match(serverSource, /DashboardToolbarWarningPresentation\.build\(/)
  assert.doesNotMatch(serverSource, /WidgetWarningComponents/)
  assert.match(warningPresenterSource, /def build\(id, warning\)/)
  assert.match(warningPresenterSource, /EvidenceAttrs\.warning\(nil\)/)
  assert.match(warningPresenterSource, /"phx-click" => "open_evidence"/)
  assert.match(warningPresenterSource, /"phx-click" => "open_data_link"/)
})

cover("direct action menu child", () => {
  assert.match(source, /import DashboardToolbarMenu from "\.\/DashboardToolbarMenu\.vue"/)
  assert.match(template, /<DashboardToolbarMenu :presentation="props\.presentation\.menu"/)
})

cover("no nested LiveVue roots", () => {
  assert.doesNotMatch(source, /v-component|data-name|phx-hook|hooks\/overlay/)
  assert.doesNotMatch(menuSource, /v-component|data-name|phx-hook|hooks\/overlay/)
})

cover("time picker payload forwarding", () => {
  assert.match(template, /@recents-loaded="forwardRecentsLoaded"/)
  assert.match(template, /@select-range="forwardSelectRange"/)
  assert.match(serverSource, /v-on:recents-loaded=\{JS\.push\("time_recents_loaded"\)\}/)
  assert.match(serverSource, /v-on:select-range=\{JS\.push\("set_chart_time_range"\)\}/)
})

const controllerStart = "// DASHBOARD_TOOLBAR_POPOVER_CONTROLLER_START"
const controllerEnd = "// DASHBOARD_TOOLBAR_POPOVER_CONTROLLER_END"
const start = source.indexOf(controllerStart)
const end = source.indexOf(controllerEnd)
assert.ok(start >= 0 && end > start, "DashboardToolbar must expose its popover controller")
const controllerSource = source.slice(start + controllerStart.length, end)
assert.doesNotMatch(controllerSource, /setTimeout|setInterval/)

const menuControllerStart = "// DASHBOARD_TOOLBAR_MENU_CONTROLLER_START"
const menuControllerEnd = "// DASHBOARD_TOOLBAR_MENU_CONTROLLER_END"
const menuStart = menuSource.indexOf(menuControllerStart)
const menuEnd = menuSource.indexOf(menuControllerEnd)
assert.ok(menuStart >= 0 && menuEnd > menuStart, "DashboardToolbarMenu must expose its controller")
const menuControllerSource = menuSource.slice(menuStart + menuControllerStart.length, menuEnd)

const context = {}
vm.createContext(context)
vm.runInContext(
  `${controllerSource}\n${menuControllerSource}\n` +
    "globalThis.createPopover = createDashboardToolbarPopoverController;" +
    "globalThis.createMenu = createDashboardToolbarMenuController;",
  context,
  {filename: toolbarPath},
)
const createPopover = context.createPopover
const createMenu = context.createMenu

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
  constructor(id, documentObject = null) {
    super()
    this.id = id
    this.documentObject = documentObject
    this.attributes = new Map()
    this.children = []
    this.hidden = false
    this.disabled = false
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
    if (this.documentObject) this.documentObject.activeElement = this
  }

  closest() {
    return this
  }

  getBoundingClientRect() {
    return this.rect
  }

  querySelectorAll() {
    return this.children
  }
}

class FakeRoot extends FakeElement {
  constructor(id, documentObject) {
    super(id, documentObject)
    this.trigger = new FakeElement(`${id}-trigger`, documentObject)
    this.panel = new FakeElement(`${id}-panel`, documentObject)
    this.trigger.setAttribute("aria-expanded", "false")
    this.panel.hidden = true
  }

  querySelector(selector) {
    if (selector === ":scope > [data-overlay-trigger]") return this.trigger
    if (selector === ":scope > [data-overlay-panel]") return this.panel
    return null
  }

  contains(target) {
    return target === this || this.trigger?.contains(target) || this.panel?.contains(target) || false
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
documentObject.activeElement = null
const windowObject = new FakeEventTarget()
windowObject.CustomEvent = FakeCustomEvent
windowObject.innerWidth = 1000

const scopeRoot = new FakeRoot("dashboard-data-controls", documentObject)
const healthRoot = new FakeRoot("dashboard-data-issues", documentObject)
const scope = createPopover({rootElement: scopeRoot, documentObject, windowObject})
const health = createPopover({rootElement: healthRoot, documentObject, windowObject})
scope.mounted()
health.mounted()

cover("operational scope popover contract", () => {
  scopeRoot.trigger.dispatchEvent(event("click"))
  assert.equal(scope.state.open, true)
  assert.equal(scopeRoot.trigger.attributes.get("aria-expanded"), "true")
  assert.equal(scopeRoot.panel.hidden, false)
})

cover("data health popover contract", () => {
  healthRoot.trigger.dispatchEvent(event("click"))
  assert.equal(health.state.open, true)
  assert.equal(healthRoot.trigger.attributes.get("aria-expanded"), "true")
  assert.equal(healthRoot.panel.hidden, false)
})

cover("cross-overlay opened coordination", () => {
  assert.equal(scope.state.open, false, "opening data health must close operational scope")
  scopeRoot.trigger.dispatchEvent(event("click"))
  assert.equal(scope.state.open, true)
  assert.equal(health.state.open, false, "opening operational scope must close data health")
})

cover("viewport gutter positioning", () => {
  scope.close({restoreFocus: false})
  scopeRoot.panel.rect = {left: 900, right: 1000}
  scope.show()
  assert.equal(scopeRoot.panel.style.transform, "translateX(-16px)")
})

cover("update-state preservation", () => {
  const oldTrigger = scopeRoot.trigger
  scope.beforeUpdate()
  scopeRoot.trigger = new FakeElement("dashboard-data-controls-toggle-updated", documentObject)
  scopeRoot.panel = new FakeElement("dashboard-data-controls-panel-updated", documentObject)
  scopeRoot.panel.rect = {left: -4, right: 96}
  scope.updated(scopeRoot)
  assert.equal(scope.state.open, true)
  assert.equal(oldTrigger.listenerCount("click"), 0)
  assert.equal(scopeRoot.panel.style.transform, "translateX(20px)")
})

cover("Escape close and focus return", () => {
  const escapeEvent = event("keydown", {key: "Escape"})
  documentObject.dispatchEvent(escapeEvent)
  assert.equal(escapeEvent.defaultPrevented, true)
  assert.equal(scope.state.open, false)
  assert.equal(scopeRoot.trigger.focusCount, 1)
})

cover("outside-click close without focus theft", () => {
  scope.show()
  documentObject.dispatchEvent(event("pointerdown", {target: new FakeElement("outside")}))
  assert.equal(scope.state.open, false)
  assert.equal(scopeRoot.trigger.focusCount, 1)
})

cover("popover listener cleanup", () => {
  scope.show()
  scope.destroyed()
  health.destroyed()
  assert.equal(documentObject.listenerCount("pointerdown"), 0)
  assert.equal(documentObject.listenerCount("keydown"), 0)
  assert.equal(windowObject.listenerCount("cadence:overlay-opened"), 0)
  assert.equal(scopeRoot.trigger.listenerCount("click"), 0)
})

cover("menu focus and keyboard semantics", () => {
  const menuRoot = new FakeRoot("dashboard-menu", documentObject)
  const firstItem = new FakeElement("dashboard-versions-button", documentObject)
  const secondItem = new FakeElement("dashboard-diagnostics-button", documentObject)
  menuRoot.panel.append(firstItem, secondItem)
  const menu = createMenu({rootElement: menuRoot, documentObject, windowObject})
  menu.mounted()
  menuRoot.trigger.dispatchEvent(event("click"))
  assert.equal(firstItem.focusCount, 1, "opening the menu must focus its first item")
  documentObject.dispatchEvent(event("keydown", {key: "ArrowDown"}))
  assert.equal(secondItem.focusCount, 1, "ArrowDown must move menu focus")
  menuRoot.panel.dispatchEvent(event("click", {target: secondItem}))
  assert.equal(menu.state.open, false, "activating a menu item must close the menu")
  menu.destroyed()
})

cover("global Overlay hook retained", () => {
  assert.match(appSource, /import Overlay from "\.\/hooks\/overlay"/)
  assert.match(appSource, /\bOverlay,/)
})

assert.deepEqual(coveredScenarios, scenarioLedger)
console.log(`dashboard_toolbar_test passed (${scenarioLedger.length} scenarios)`)
