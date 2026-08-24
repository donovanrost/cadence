import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/DashboardHealth.vue")
const source = await readFile(componentPath, "utf8")
const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "DashboardHealth.vue must have a script setup block")
assert.ok(template, "DashboardHealth.vue must have a template block")
assert.match(script, /import ClipboardButton from "\.\/ClipboardButton\.vue"/)
assert.match(template, /:id="presentation\.root\.id"/)
assert.match(template, /<ClipboardButton v-bind="presentation\.copy_props" \/>/)
assert.match(template, /:data-overlay-open="isOpen\(group\) \? group\.overlay\.open_attr : undefined"/)
assert.match(template, /:aria-expanded=/)
assert.match(template, /:hidden="!isOpen\(group\)"/)
assert.match(template, /@click="toggle\(group, \$event\)"/)
assert.match(template, /v-bind="presentation\.evidence\.attrs"/)
assert.match(template, /v-bind="presentation\.capture\.attrs"/)
assert.match(template, /v-bind="item\.attrs"/)

const listeners = {document: new Map(), window: new Map()}
const removedListeners = {document: [], window: []}
const dispatchedEvents = []
let mountedCallback
let updatedCallback
let unmountedCallback

class FakeElement {
  constructor(id, rect = {left: 20, right: 200}) {
    this.id = id
    this.rect = rect
    this.style = {transform: ""}
    this.children = new Set()
    this.focusCount = 0
  }

  contains(node) {
    return node === this || this.children.has(node)
  }

  getBoundingClientRect() {
    return this.rect
  }

  focus() {
    this.focusCount += 1
  }
}

const group = (name) => ({
  overlay: {
    id: `dashboard-health-group-${name}`,
    trigger: {id: `dashboard-health-group-${name}-trigger`},
    panel: {id: `dashboard-health-group-${name}-panel`}
  }
})

const blocked = group("blocked")
const degraded = group("degraded")
const props = {presentation: {groups: [blocked, degraded]}}
const elements = new Map()
const rootElement = new FakeElement("dashboard-health-rollup")

for (const [item, rect] of [
  [blocked, {left: -4, right: 300}],
  [degraded, {left: 800, right: 1010}]
]) {
  const overlay = new FakeElement(item.overlay.id)
  const trigger = new FakeElement(item.overlay.trigger.id)
  const panel = new FakeElement(item.overlay.panel.id, rect)
  overlay.children.add(trigger)
  overlay.children.add(panel)
  rootElement.children.add(overlay)
  elements.set(overlay.id, overlay)
  elements.set(trigger.id, trigger)
  elements.set(panel.id, panel)
}

const context = {
  ClipboardButton: {},
  CustomEvent: class {
    constructor(type, options) {
      this.type = type
      this.detail = options.detail
    }
  },
  HTMLElement: FakeElement,
  defineProps(definition) {
    assert.equal(definition.presentation.required, true)
    return props
  },
  document: {
    addEventListener(type, listener) {
      listeners.document.set(type, listener)
    },
    removeEventListener(type, listener) {
      assert.equal(listeners.document.get(type), listener)
      listeners.document.delete(type)
      removedListeners.document.push(type)
    },
    getElementById(id) {
      return elements.get(id) || null
    }
  },
  window: {
    innerWidth: 1000,
    addEventListener(type, listener) {
      listeners.window.set(type, listener)
    },
    removeEventListener(type, listener) {
      assert.equal(listeners.window.get(type), listener)
      listeners.window.delete(type)
      removedListeners.window.push(type)
    },
    dispatchEvent(event) {
      dispatchedEvents.push(event)
      listeners.window.get(event.type)?.(event)
    }
  },
  Vue: {
    nextTick(callback) {
      return callback ? Promise.resolve().then(callback) : Promise.resolve()
    },
    onBeforeUnmount(callback) {
      unmountedCallback = callback
    },
    onMounted(callback) {
      mountedCallback = callback
    },
    onUpdated(callback) {
      updatedCallback = callback
    },
    ref(value) {
      return {value}
    }
  }
}

const testableScript =
  script
    .replace(
      'import ClipboardButton from "./ClipboardButton.vue"',
      "const ClipboardButton = globalThis.ClipboardButton"
    )
    .replace(
      'import {nextTick, onBeforeUnmount, onMounted, onUpdated, ref} from "vue"',
      "const {nextTick, onBeforeUnmount, onMounted, onUpdated, ref} = globalThis.Vue"
    ) +
  "\nglobalThis.dashboardHealth = {root, openGroupId, isOpen, toggle, close, onDocumentPointerDown, onDocumentKeyDown, onOverlayOpened}"

vm.createContext(context)
vm.runInContext(testableScript, context, {filename: componentPath})

const controller = context.dashboardHealth
controller.root.value = rootElement

assert.equal(typeof mountedCallback, "function")
assert.equal(typeof updatedCallback, "function")
assert.equal(typeof unmountedCallback, "function")

mountedCallback()
assert.deepEqual(Array.from(listeners.document.keys()), ["pointerdown", "keydown"])
assert.deepEqual(Array.from(listeners.window.keys()), ["cadence:overlay-opened"])

let prevented = 0
await controller.toggle(blocked, {preventDefault: () => (prevented += 1)})
assert.equal(prevented, 1)
assert.equal(controller.isOpen(blocked), true)
assert.equal(controller.isOpen(degraded), false)
assert.equal(dispatchedEvents.at(-1).type, "cadence:overlay-opened")
assert.equal(dispatchedEvents.at(-1).detail.id, blocked.overlay.id)
assert.equal(elements.get(blocked.overlay.panel.id).style.transform, "translateX(20px)")

await controller.toggle(blocked, {preventDefault: () => (prevented += 1)})
await Promise.resolve()
assert.equal(prevented, 2)
assert.equal(controller.openGroupId.value, null)
assert.equal(elements.get(blocked.overlay.trigger.id).focusCount, 1)

await controller.toggle(blocked, {preventDefault: () => (prevented += 1)})
await controller.toggle(degraded, {preventDefault: () => (prevented += 1)})
assert.equal(controller.isOpen(blocked), false)
assert.equal(controller.isOpen(degraded), true)
assert.equal(elements.get(blocked.overlay.trigger.id).focusCount, 1)
assert.equal(elements.get(degraded.overlay.panel.id).style.transform, "translateX(-26px)")

updatedCallback()
assert.equal(controller.isOpen(degraded), true, "updates preserve an existing open group")

listeners.document.get("pointerdown")({target: new FakeElement("outside")})
assert.equal(controller.openGroupId.value, null)
assert.equal(elements.get(degraded.overlay.trigger.id).focusCount, 0)

await controller.toggle(blocked, {preventDefault: () => (prevented += 1)})
let escapePrevented = 0
listeners.document.get("keydown")({
  key: "Escape",
  preventDefault: () => (escapePrevented += 1)
})
await Promise.resolve()
assert.equal(escapePrevented, 1)
assert.equal(controller.openGroupId.value, null)
assert.equal(elements.get(blocked.overlay.trigger.id).focusCount, 2)

await controller.toggle(blocked, {preventDefault: () => (prevented += 1)})
listeners.window.get("cadence:overlay-opened")({detail: new FakeElement("another-overlay")})
assert.equal(controller.openGroupId.value, null)
assert.equal(elements.get(blocked.overlay.trigger.id).focusCount, 2)

await controller.toggle(degraded, {preventDefault: () => (prevented += 1)})
props.presentation.groups = [blocked]
updatedCallback()
assert.equal(controller.openGroupId.value, null, "removing an open group closes it on update")

unmountedCallback()
assert.deepEqual(removedListeners.document, ["pointerdown", "keydown"])
assert.deepEqual(removedListeners.window, ["cadence:overlay-opened"])
assert.equal(listeners.document.size, 0)
assert.equal(listeners.window.size, 0)

console.log("dashboard_health_test passed")
