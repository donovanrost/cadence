import assert from "node:assert/strict"
import test from "node:test"

import {createDropdownController} from "../vue/dropdown_controller.js"

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
  }

  listenerCount(type) {
    return this.listeners.get(type)?.size || 0
  }
}

class FakeClassList {
  constructor() {
    this.values = new Set()
  }

  add(value) {
    this.values.add(value)
  }

  contains(value) {
    return this.values.has(value)
  }

  remove(value) {
    this.values.delete(value)
  }
}

class FakeElement extends FakeEventTarget {
  constructor(name, documentObject, {interactive = false} = {}) {
    super()
    this.name = name
    this.documentObject = documentObject
    this.interactive = interactive
    this.attributes = new Map()
    this.classList = new FakeClassList()
    this.focusCount = 0
  }

  closest() {
    return this.interactive ? this : null
  }

  focus() {
    this.focusCount += 1
    this.documentObject.activeElement = this
  }

  setAttribute(name, value) {
    this.attributes.set(name, value)
  }
}

class FakeMenu extends FakeElement {
  constructor(documentObject) {
    super("menu", documentObject)
    this.items = ["first", "second", "third"].map(
      (name) => new FakeElement(name, documentObject, {interactive: true}),
    )
  }

  querySelectorAll(selector) {
    assert.equal(selector, "[role='menuitem'], a, button")
    return this.items
  }
}

class FakeRoot extends FakeElement {
  constructor(documentObject) {
    super("root", documentObject)
    this.trigger = new FakeElement("trigger", documentObject, {interactive: true})
    this.menu = new FakeMenu(documentObject)
  }

  contains(target) {
    return target === this || target === this.trigger || target === this.menu || this.menu.items.includes(target)
  }

  querySelector(selector) {
    if (selector === "[data-dropdown-trigger]") return this.trigger
    if (selector === "[role='menu']") return this.menu
    return null
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

const setup = () => {
  const documentObject = new FakeEventTarget()
  documentObject.activeElement = null
  const root = new FakeRoot(documentObject)
  const controller = createDropdownController({rootElement: root, documentObject})
  controller.mount()
  return {controller, documentObject, root}
}

test("click toggles aria-expanded, initial focus, focus return, and document listeners", () => {
  const {controller, documentObject, root} = setup()

  assert.equal(root.trigger.attributes.get("aria-expanded"), "false")
  assert.equal(root.trigger.listenerCount("click"), 1)
  assert.equal(root.trigger.listenerCount("keydown"), 1)
  assert.equal(root.menu.listenerCount("click"), 1)
  assert.equal(documentObject.listenerCount("pointerdown"), 0)
  assert.equal(documentObject.listenerCount("keydown"), 0)

  const openEvent = event("click")
  root.trigger.dispatchEvent(openEvent)

  assert.equal(openEvent.defaultPrevented, true)
  assert.equal(controller.isOpen(), true)
  assert.equal(root.trigger.attributes.get("aria-expanded"), "true")
  assert.equal(documentObject.activeElement, root.menu.items[0])
  assert.equal(documentObject.listenerCount("pointerdown"), 1)
  assert.equal(documentObject.listenerCount("keydown"), 1)

  root.trigger.dispatchEvent(event("click"))

  assert.equal(controller.isOpen(), false)
  assert.equal(root.trigger.attributes.get("aria-expanded"), "false")
  assert.equal(documentObject.activeElement, root.trigger)
  assert.equal(documentObject.listenerCount("pointerdown"), 0)
  assert.equal(documentObject.listenerCount("keydown"), 0)
})

test("ArrowDown opens and ArrowUp/Down/Home/End move focus with wrapping", () => {
  const {controller, documentObject, root} = setup()
  const openEvent = event("keydown", {key: "ArrowDown"})

  root.trigger.dispatchEvent(openEvent)

  assert.equal(openEvent.defaultPrevented, true)
  assert.equal(controller.isOpen(), true)
  assert.equal(documentObject.activeElement, root.menu.items[0])

  documentObject.dispatchEvent(event("keydown", {key: "ArrowDown"}))
  assert.equal(documentObject.activeElement, root.menu.items[1])

  documentObject.dispatchEvent(event("keydown", {key: "ArrowUp"}))
  assert.equal(documentObject.activeElement, root.menu.items[0])

  documentObject.dispatchEvent(event("keydown", {key: "ArrowUp"}))
  assert.equal(documentObject.activeElement, root.menu.items[2])

  documentObject.dispatchEvent(event("keydown", {key: "ArrowDown"}))
  assert.equal(documentObject.activeElement, root.menu.items[0])

  documentObject.dispatchEvent(event("keydown", {key: "End"}))
  assert.equal(documentObject.activeElement, root.menu.items[2])

  documentObject.dispatchEvent(event("keydown", {key: "Home"}))
  assert.equal(documentObject.activeElement, root.menu.items[0])
})

test("Escape and outside pointer close with focus return", () => {
  const {controller, documentObject, root} = setup()

  controller.open()
  const escapeEvent = event("keydown", {key: "Escape"})
  documentObject.dispatchEvent(escapeEvent)

  assert.equal(escapeEvent.defaultPrevented, true)
  assert.equal(controller.isOpen(), false)
  assert.equal(documentObject.activeElement, root.trigger)

  controller.open()
  const outside = new FakeElement("outside", documentObject)
  documentObject.dispatchEvent(event("pointerdown", {target: outside}))

  assert.equal(controller.isOpen(), false)
  assert.equal(documentObject.activeElement, root.trigger)
})

test("Tab and menu activation close without returning focus", () => {
  const {controller, documentObject, root} = setup()

  controller.open()
  documentObject.dispatchEvent(event("keydown", {key: "Tab"}))

  assert.equal(controller.isOpen(), false)
  assert.equal(documentObject.activeElement, root.menu.items[0])

  controller.open()
  root.menu.items[1].focus()
  root.menu.dispatchEvent(event("click", {target: root.menu.items[1]}))

  assert.equal(controller.isOpen(), false)
  assert.equal(documentObject.activeElement, root.menu.items[1])
})

test("destroy removes local and document listeners and resets transient state", () => {
  const {controller, documentObject, root} = setup()

  controller.mount()
  controller.open()
  controller.destroy()

  assert.equal(controller.isOpen(), false)
  assert.equal(root.trigger.attributes.get("aria-expanded"), "false")
  assert.equal(root.trigger.listenerCount("click"), 0)
  assert.equal(root.trigger.listenerCount("keydown"), 0)
  assert.equal(root.menu.listenerCount("click"), 0)
  assert.equal(documentObject.listenerCount("pointerdown"), 0)
  assert.equal(documentObject.listenerCount("keydown"), 0)
})
