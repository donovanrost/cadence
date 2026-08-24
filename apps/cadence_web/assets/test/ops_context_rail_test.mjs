import assert from "node:assert/strict"
import {existsSync} from "node:fs"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {createNavRailController} from "../vue/nav_rail_controller.js"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/OpsContextRail.vue")
const appPath = resolve(__dirname, "../js/app.js")
const legacyHookPath = resolve(__dirname, "../js/hooks/nav_rail.js")
const source = await readFile(componentPath, "utf8")
const appSource = await readFile(appPath, "utf8")
const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

// The context rail keeps its browser contract while Vue owns presentation and lifecycle.
assert.ok(script, "OpsContextRail.vue must have a script setup block")
assert.ok(template, "OpsContextRail.vue must have a template block")
assert.match(script, /import \{createNavRailController\} from "\.\/nav_rail_controller\.js"/)
assert.doesNotMatch(script, /const createNavRailController\s*=/)
assert.match(template, /^  <aside\n/)
assert.match(template, /:id="props\.rail\.id"/)
assert.match(template, /data-ops-context-rail/)
assert.match(template, /:data-storage-key="props\.rail\.storage_key"/)
assert.match(template, /:data-rail-role="props\.rail\.role"/)
assert.match(
  template,
  /class="group\/ctx relative w-12 data-\[expanded\]:w-72 shrink-0 flex flex-col border-l border-primary\/20 bg-base-200 hud-grid overflow-hidden transition-\[width\] duration-150"/
)
assert.match(template, /data-ops-context-rail-toggle/)
assert.match(
  template,
  /class="absolute inset-y-0 left-0 z-10 w-1\.5 cursor-col-resize touch-none hover:bg-primary\/40 active:bg-primary\/60 hidden group-data-\[expanded\]\/ctx:block"/
)
assert.match(template, /:data-ops-context-collapsed-section="section\.key"/)
assert.match(template, /:data-ops-context-section="section\.key"/)
assert.match(template, /:data-ops-context-module-freshness="section\.freshness"/)
assert.match(template, /:data-ops-context-followed-command=/)
assert.match(
  template,
  /class="inline-flex items-center gap-1 text-\[0\.65rem\] font-semibold text-primary hover:underline"/
)
assert.match(template, /data-phx-link="redirect"/)
assert.match(template, /data-phx-link-state="push"/)
assert.doesNotMatch(template, /phx-hook/)
assert.doesNotMatch(appSource, /NavRail|hooks\/nav_rail/)
assert.equal(existsSync(legacyHookPath), false, "the retired Phoenix hook must stay removed")

class FakeEventTarget {
  constructor() {
    this.listeners = new Map()
  }

  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set())
    this.listeners.get(type).add(listener)
  }

  removeEventListener(type, listener) {
    this.listeners.get(type)?.delete(listener)
  }

  dispatchEvent(event) {
    for (const listener of Array.from(this.listeners.get(event.type) || [])) listener(event)
    return true
  }

  listenerCount(type) {
    return this.listeners.get(type)?.size || 0
  }
}

class FakeHandle extends FakeEventTarget {
  setPointerCapture(pointerId) {
    this.capturedPointerId = pointerId
  }
}

class FakeElement extends FakeEventTarget {
  constructor({role, storageKey, width, handle}) {
    super()
    this.dataset = {storageKey, railRole: role}
    this.style = {transition: "", width: ""}
    this.attributes = new Map()
    this.rectWidth = width
    this.handle = handle
  }

  getBoundingClientRect() {
    return {width: this.style.width ? Number.parseFloat(this.style.width) : this.rectWidth}
  }

  hasAttribute(name) {
    return this.attributes.has(name)
  }

  querySelector(selector) {
    return selector === "[data-rail-resize]" ? this.handle : null
  }

  removeAttribute(name) {
    this.attributes.delete(name)
  }

  setAttribute(name, value) {
    this.attributes.set(name, value)
  }
}

class FakeStorage {
  constructor() {
    this.values = new Map()
  }

  getItem(key) {
    return this.values.get(key) ?? null
  }

  setItem(key, value) {
    this.values.set(key, value)
  }
}

class FakeCustomEvent {
  constructor(type, options) {
    this.type = type
    this.detail = options.detail
  }
}

const makeEnvironment = ({handle = new FakeHandle(), innerWidth = 1000} = {}) => {
  const storage = new FakeStorage()
  const root = new FakeElement({
    role: "context",
    storageKey: "cadence-ops-context-rail",
    width: 48,
    handle
  })
  const peer = new FakeElement({
    role: "navigation",
    storageKey: "cadence-ops-rail",
    width: 224,
    handle: null
  })
  const windowObject = new FakeEventTarget()
  windowObject.CustomEvent = FakeCustomEvent
  windowObject.innerWidth = innerWidth
  windowObject.localStorage = storage
  const documentObject = {
    querySelectorAll(selector) {
      assert.equal(selector, "[data-rail-role]")
      return [root, peer]
    }
  }

  return {documentObject, handle, peer, root, storage, windowObject}
}

const controllerState = controller => {
  const state = controller.state()
  return {expanded: state.expanded, width: state.width}
}

// Default collapse, persistence, coordinated peer collapse, update, and teardown.
const lifecycleEnvironment = makeEnvironment()
const lifecycleController = createNavRailController({
  el: lifecycleEnvironment.root,
  windowObject: lifecycleEnvironment.windowObject,
  documentObject: lifecycleEnvironment.documentObject,
  storage: lifecycleEnvironment.storage
})

lifecycleController.mount()
assert.deepEqual(controllerState(lifecycleController), {expanded: false, width: null})
assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), false)
assert.equal(lifecycleEnvironment.root.listenerCount("click"), 1)
assert.equal(lifecycleEnvironment.handle.listenerCount("pointerdown"), 1)
assert.equal(lifecycleEnvironment.windowObject.listenerCount("resize"), 1)
assert.equal(lifecycleEnvironment.windowObject.listenerCount("cadence:rail-expanded"), 1)

let expandedEvents = 0
const observeExpansion = event => {
  if (event.detail === lifecycleEnvironment.root) expandedEvents += 1
}
lifecycleEnvironment.windowObject.addEventListener("cadence:rail-expanded", observeExpansion)
lifecycleEnvironment.root.dispatchEvent({
  type: "click",
  target: {closest: selector => (selector === "[data-rail-toggle]" ? {} : null)}
})
assert.deepEqual(controllerState(lifecycleController), {expanded: true, width: null})
assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), true)
assert.equal(expandedEvents, 1)
assert.deepEqual(
  JSON.parse(lifecycleEnvironment.storage.getItem("cadence-ops-context-rail")),
  {state: "expanded", width: null}
)

lifecycleEnvironment.root.removeAttribute("data-expanded")
lifecycleController.update()
assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), true)

lifecycleEnvironment.windowObject.dispatchEvent(
  new FakeCustomEvent("cadence:rail-expanded", {detail: lifecycleEnvironment.peer})
)
assert.deepEqual(controllerState(lifecycleController), {expanded: false, width: null})
assert.equal(
  JSON.parse(lifecycleEnvironment.storage.getItem("cadence-ops-context-rail")).state,
  "collapsed"
)

lifecycleEnvironment.windowObject.removeEventListener("cadence:rail-expanded", observeExpansion)
lifecycleController.destroy()
assert.equal(lifecycleEnvironment.root.listenerCount("click"), 0)
assert.equal(lifecycleEnvironment.handle.listenerCount("pointerdown"), 0)
assert.equal(lifecycleEnvironment.windowObject.listenerCount("resize"), 0)
assert.equal(lifecycleEnvironment.windowObject.listenerCount("cadence:rail-expanded"), 0)

// Bare-string storage from the legacy hook remains readable.
const legacyEnvironment = makeEnvironment()
legacyEnvironment.storage.setItem("cadence-ops-context-rail", "expanded")
const legacyController = createNavRailController({
  el: legacyEnvironment.root,
  windowObject: legacyEnvironment.windowObject,
  documentObject: legacyEnvironment.documentObject,
  storage: legacyEnvironment.storage
})
legacyController.mount()
assert.deepEqual(controllerState(legacyController), {expanded: true, width: null})
assert.equal(legacyEnvironment.root.hasAttribute("data-expanded"), true)
legacyController.destroy()

// Stored width, viewport constraints, snap collapse, pointer cleanup, and width restoration.
const resizeEnvironment = makeEnvironment()
resizeEnvironment.storage.setItem(
  "cadence-ops-context-rail",
  JSON.stringify({state: "expanded", width: 320})
)
const resizeController = createNavRailController({
  el: resizeEnvironment.root,
  windowObject: resizeEnvironment.windowObject,
  documentObject: resizeEnvironment.documentObject,
  storage: resizeEnvironment.storage
})
resizeController.mount()
assert.deepEqual(controllerState(resizeController), {expanded: true, width: 320})
assert.equal(resizeEnvironment.root.style.width, "320px")

resizeEnvironment.handle.dispatchEvent({
  type: "pointerdown",
  pointerId: 7,
  clientX: 500,
  preventDefault() {}
})
assert.equal(resizeEnvironment.handle.capturedPointerId, 7)
assert.equal(resizeEnvironment.root.style.transition, "none")
resizeEnvironment.windowObject.dispatchEvent({type: "pointermove", clientX: 0})
assert.deepEqual(controllerState(resizeController), {expanded: true, width: 480})
assert.equal(resizeEnvironment.root.style.width, "416px")
resizeEnvironment.windowObject.dispatchEvent({type: "pointerup"})
assert.equal(resizeEnvironment.root.style.transition, "")

resizeEnvironment.windowObject.innerWidth = 700
resizeEnvironment.windowObject.dispatchEvent({type: "resize"})
assert.equal(resizeEnvironment.root.style.width, "140px")
resizeEnvironment.windowObject.innerWidth = 1300
resizeEnvironment.windowObject.dispatchEvent({type: "resize"})
assert.equal(resizeEnvironment.root.style.width, "480px")

resizeEnvironment.handle.dispatchEvent({
  type: "pointerdown",
  pointerId: 8,
  clientX: 500,
  preventDefault() {}
})
resizeEnvironment.windowObject.dispatchEvent({type: "pointermove", clientX: 880})
assert.deepEqual(controllerState(resizeController), {expanded: false, width: 480})
resizeEnvironment.windowObject.dispatchEvent({type: "pointerup"})
assert.deepEqual(
  JSON.parse(resizeEnvironment.storage.getItem("cadence-ops-context-rail")),
  {state: "collapsed", width: 480}
)

resizeEnvironment.root.dispatchEvent({
  type: "click",
  target: {closest: () => ({})}
})
assert.equal(resizeEnvironment.root.style.width, "480px")

resizeEnvironment.handle.dispatchEvent({
  type: "pointerdown",
  pointerId: 9,
  clientX: 500,
  preventDefault() {}
})
assert.equal(resizeEnvironment.windowObject.listenerCount("pointermove"), 1)
resizeController.destroy()
assert.equal(resizeEnvironment.windowObject.listenerCount("pointermove"), 0)
assert.equal(resizeEnvironment.windowObject.listenerCount("pointerup"), 0)
assert.equal(resizeEnvironment.windowObject.listenerCount("pointercancel"), 0)
assert.equal(resizeEnvironment.root.style.transition, "")

console.log("ops_context_rail_test passed")
