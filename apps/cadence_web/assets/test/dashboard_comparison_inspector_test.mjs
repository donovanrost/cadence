import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const inspectorPath = resolve(__dirname, "../vue/DashboardComparisonInspector.vue")
const rollupPath = resolve(__dirname, "../vue/DashboardComparisonRollup.vue")
const inspectorSource = await readFile(inspectorPath, "utf8")
const rollupSource = await readFile(rollupPath, "utf8")
const script = rollupSource.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = rollupSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "DashboardComparisonRollup.vue must have a script setup block")
assert.ok(template, "DashboardComparisonRollup.vue must have a template block")
assert.match(inspectorSource, /import ClipboardButton from "\.\/ClipboardButton\.vue"/)
assert.match(
  inspectorSource,
  /import DashboardComparisonInspectorHeader from "\.\/DashboardComparisonInspectorHeader\.vue"/
)
assert.match(
  inspectorSource,
  /import DashboardComparisonRollup from "\.\/DashboardComparisonRollup\.vue"/
)
assert.match(inspectorSource, /presentation: \{type: Object, required: true\}/)
assert.match(
  inspectorSource,
  /<DashboardComparisonInspectorHeader :presentation="presentation\.inspector\.header" \/>/
)
assert.equal(
  inspectorSource.match(/<ClipboardButton v-bind="presentation\.rollup\.[^"]+\.props" \/>/g)
    ?.length,
  4,
  "both inspector and standalone paths directly compose both clipboard controls"
)
assert.doesNotMatch(inspectorSource, /v-component|<\.vue/)
assert.doesNotMatch(inspectorSource, /data-name/)
assert.match(inspectorSource, /<DashboardComparisonRollup v-else/)
assert.match(template, /v-bind="presentation\.root\.attrs"/)
assert.match(template, /v-bind="presentation\.review_form\.root\.attrs"/)
assert.match(template, /v-bind="presentation\.preset_form\.root\.attrs"/)
assert.match(template, /v-bind="item\.actions\.apply\.attrs"/)
assert.match(template, /v-bind="item\.actions\.delete\.attrs"/)
assert.match(template, /v-bind="action\.attrs"/)
assert.match(
  template,
  /:data-overlay-open="overlayState\(presentation\.saved_presets\)\.dataOverlayOpen"/
)
assert.match(
  template,
  /:aria-expanded="overlayState\(presentation\.details\)\.ariaExpanded"/
)
assert.match(template, /:hidden="overlayState\(presentation\.details\)\.hidden"/)
assert.doesNotMatch(template, /data-name/)

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

const overlay = (id) => ({
  root: {open_attr: "", attrs: {id}},
  trigger: {
    aria_expanded: {open: "true", closed: "false"},
    attrs: {id: `${id}-trigger`}
  },
  panel: {attrs: {id: `${id}-panel`}}
})

const savedPresets = overlay("dashboard-comparison-saved-presets")
const details = overlay("dashboard-comparison-rollup-detail")
const props = {presentation: {saved_presets: savedPresets, details}}
const elements = new Map()
const rootElement = new FakeElement("dashboard-comparison-rollup")

for (const [item, rect] of [
  [savedPresets, {left: -4, right: 300}],
  [details, {left: 800, right: 1010}]
]) {
  const overlayElement = new FakeElement(item.root.attrs.id)
  const trigger = new FakeElement(item.trigger.attrs.id)
  const panel = new FakeElement(item.panel.attrs.id, rect)
  overlayElement.children.add(trigger)
  overlayElement.children.add(panel)
  rootElement.children.add(overlayElement)
  elements.set(overlayElement.id, overlayElement)
  elements.set(trigger.id, trigger)
  elements.set(panel.id, panel)
}

const context = {
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
  script.replace(
    'import {nextTick, onBeforeUnmount, onMounted, onUpdated, ref} from "vue"',
    "const {nextTick, onBeforeUnmount, onMounted, onUpdated, ref} = globalThis.Vue"
  ) +
  "\nglobalThis.dashboardComparisonRollup = {root, openOverlayId, isOpen, overlayState, toggle, close, onDocumentPointerDown, onDocumentKeyDown, onOverlayOpened}"

vm.createContext(context)
vm.runInContext(testableScript, context, {filename: rollupPath})

const controller = context.dashboardComparisonRollup
controller.root.value = rootElement

const assertOverlayState = (item, {ariaExpanded, hidden, dataOverlayOpen}) => {
  const state = controller.overlayState(item)
  assert.equal(state.ariaExpanded, ariaExpanded)
  assert.equal(state.hidden, hidden)
  assert.equal(state.dataOverlayOpen, dataOverlayOpen)
}

assert.equal(typeof mountedCallback, "function")
assert.equal(typeof updatedCallback, "function")
assert.equal(typeof unmountedCallback, "function")

mountedCallback()
assert.deepEqual(Array.from(listeners.document.keys()), ["pointerdown", "keydown"])
assert.deepEqual(Array.from(listeners.window.keys()), ["cadence:overlay-opened"])
assertOverlayState(savedPresets, {
  ariaExpanded: "false",
  hidden: true,
  dataOverlayOpen: undefined
})

let prevented = 0
await controller.toggle(savedPresets, {preventDefault: () => (prevented += 1)})
assert.equal(prevented, 1)
assert.equal(controller.isOpen(savedPresets), true)
assert.equal(controller.isOpen(details), false)
assertOverlayState(savedPresets, {ariaExpanded: "true", hidden: false, dataOverlayOpen: ""})
assert.equal(dispatchedEvents.length, 1)
assert.equal(dispatchedEvents.at(-1).type, "cadence:overlay-opened")
assert.equal(dispatchedEvents.at(-1).detail.id, savedPresets.root.attrs.id)
assert.equal(elements.get(savedPresets.panel.attrs.id).style.transform, "translateX(20px)")

await controller.toggle(savedPresets, {preventDefault: () => (prevented += 1)})
await Promise.resolve()
assert.equal(prevented, 2)
assert.equal(controller.openOverlayId.value, null)
assert.equal(elements.get(savedPresets.trigger.attrs.id).focusCount, 1)

await controller.toggle(savedPresets, {preventDefault: () => (prevented += 1)})
await controller.toggle(details, {preventDefault: () => (prevented += 1)})
assert.equal(controller.isOpen(savedPresets), false)
assert.equal(controller.isOpen(details), true)
assert.equal(elements.get(details.panel.attrs.id).style.transform, "translateX(-26px)")
assert.equal(dispatchedEvents.length, 3)

const updatedSavedPresets = overlay("dashboard-comparison-saved-presets")
const updatedDetails = overlay("dashboard-comparison-rollup-detail")
props.presentation.saved_presets = updatedSavedPresets
props.presentation.details = updatedDetails
updatedCallback()
assert.equal(controller.isOpen(updatedDetails), true, "updates preserve an existing overlay")

listeners.document.get("pointerdown")({target: new FakeElement("outside")})
assert.equal(controller.openOverlayId.value, null)
assert.equal(elements.get(details.trigger.attrs.id).focusCount, 0)

await controller.toggle(updatedSavedPresets, {preventDefault: () => (prevented += 1)})
let escapePrevented = 0
listeners.document.get("keydown")({
  key: "Escape",
  preventDefault: () => (escapePrevented += 1)
})
await Promise.resolve()
assert.equal(escapePrevented, 1)
assert.equal(controller.openOverlayId.value, null)
assert.equal(elements.get(savedPresets.trigger.attrs.id).focusCount, 2)

await controller.toggle(updatedSavedPresets, {preventDefault: () => (prevented += 1)})
listeners.window.get("cadence:overlay-opened")({detail: new FakeElement("another-overlay")})
assert.equal(controller.openOverlayId.value, null)
assert.equal(elements.get(savedPresets.trigger.attrs.id).focusCount, 2)

await controller.toggle(updatedDetails, {preventDefault: () => (prevented += 1)})
props.presentation.details = null
updatedCallback()
assert.equal(controller.openOverlayId.value, null, "removing the open overlay closes it on update")

unmountedCallback()
assert.deepEqual(removedListeners.document, ["pointerdown", "keydown"])
assert.deepEqual(removedListeners.window, ["cadence:overlay-opened"])
assert.equal(listeners.document.size, 0)
assert.equal(listeners.window.size, 0)

console.log("dashboard_comparison_inspector_test passed")
