import assert from "node:assert/strict";
import { test } from "vite-plus/test";
import { createNavRailController } from "./nav_rail_controller.js";
test("rail coordination, persistence, resize bounds, and listener cleanup", () => {
  class FakeEventTarget {
    constructor() {
      this.listeners = new Map();
    }

    addEventListener(type, listener) {
      if (!this.listeners.has(type)) this.listeners.set(type, new Set());
      this.listeners.get(type).add(listener);
    }

    removeEventListener(type, listener) {
      this.listeners.get(type)?.delete(listener);
    }

    dispatchEvent(event) {
      for (const listener of Array.from(this.listeners.get(event.type) || [])) listener(event);
      return true;
    }

    listenerCount(type) {
      return this.listeners.get(type)?.size || 0;
    }
  }

  class FakeElement extends FakeEventTarget {
    constructor({ role = "navigation", width = 224, handle = null } = {}) {
      super();
      this.dataset = { storageKey: "cadence-ops-rail", railRole: role };
      this.style = { transition: "", width: "" };
      this.attributes = new Map();
      this.rectWidth = width;
      this.handle = handle;
    }

    getBoundingClientRect() {
      return { width: this.style.width ? Number.parseFloat(this.style.width) : this.rectWidth };
    }

    hasAttribute(name) {
      return this.attributes.has(name);
    }

    querySelector(selector) {
      return selector === "[data-rail-resize]" ? this.handle : null;
    }

    removeAttribute(name) {
      this.attributes.delete(name);
    }

    setAttribute(name, value) {
      this.attributes.set(name, value);
    }
  }

  class FakeHandle extends FakeEventTarget {
    setPointerCapture(pointerId) {
      this.capturedPointerId = pointerId;
    }
  }

  class FakeStorage {
    constructor() {
      this.values = new Map();
    }

    getItem(key) {
      return this.values.get(key) ?? null;
    }

    setItem(key, value) {
      this.values.set(key, value);
    }
  }

  class FakeCustomEvent {
    constructor(type, options) {
      this.type = type;
      this.detail = options.detail;
    }
  }

  const makeEnvironment = ({ handle = null, innerWidth = 1000, peerWidth = 200 } = {}) => {
    const storage = new FakeStorage();
    const root = new FakeElement({ handle });
    const peer = new FakeElement({ role: "context", width: peerWidth });
    const windowObject = new FakeEventTarget();
    windowObject.CustomEvent = FakeCustomEvent;
    windowObject.innerWidth = innerWidth;
    windowObject.localStorage = storage;
    const documentObject = {
      querySelectorAll(selector) {
        assert.equal(selector, "[data-rail-role]");
        return [root, peer];
      },
    };

    return { documentObject, peer, root, storage, windowObject };
  };

  const lifecycleEnvironment = makeEnvironment();
  const createController = (options) =>
    createNavRailController({
      windowObject: lifecycleEnvironment.windowObject,
      documentObject: lifecycleEnvironment.documentObject,
      storage: lifecycleEnvironment.storage,
      ...options,
    });
  const component = { createNavRailController: createController };
  const controllerState = (controller) => controller.state();
  const lifecycleController = createController({ el: lifecycleEnvironment.root });
  lifecycleController.mount();
  assert.deepEqual(controllerState(lifecycleController), { expanded: false, width: null });
  assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), false);
  assert.equal(lifecycleEnvironment.root.listenerCount("click"), 1);
  assert.equal(lifecycleEnvironment.windowObject.listenerCount("resize"), 1);
  assert.equal(lifecycleEnvironment.windowObject.listenerCount("cadence:rail-expanded"), 1);

  let expandedEvents = 0;
  lifecycleEnvironment.windowObject.addEventListener("cadence:rail-expanded", (event) => {
    if (event.detail === lifecycleEnvironment.root) expandedEvents += 1;
  });

  lifecycleEnvironment.root.dispatchEvent({
    type: "click",
    target: { closest: (selector) => (selector === "[data-rail-toggle]" ? {} : null) },
  });

  assert.deepEqual(controllerState(lifecycleController), { expanded: true, width: null });
  assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), true);
  assert.equal(expandedEvents, 1);
  assert.deepEqual(JSON.parse(lifecycleEnvironment.storage.getItem("cadence-ops-rail")), {
    state: "expanded",
    width: null,
  });

  lifecycleEnvironment.windowObject.dispatchEvent(
    new FakeCustomEvent("cadence:rail-expanded", { detail: lifecycleEnvironment.peer }),
  );

  assert.deepEqual(controllerState(lifecycleController), { expanded: false, width: null });
  assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), false);
  assert.equal(
    JSON.parse(lifecycleEnvironment.storage.getItem("cadence-ops-rail")).state,
    "collapsed",
  );

  lifecycleEnvironment.root.setAttribute("data-expanded", "");
  lifecycleController.update();
  assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), false);

  lifecycleController.destroy();

  assert.equal(lifecycleEnvironment.root.listenerCount("click"), 0);
  assert.equal(lifecycleEnvironment.windowObject.listenerCount("resize"), 0);

  // The pre-resize bare-string storage format remains compatible.
  const legacyEnvironment = makeEnvironment();
  legacyEnvironment.storage.setItem("cadence-ops-rail", "expanded");
  const legacyController = component.createNavRailController({
    el: legacyEnvironment.root,
    windowObject: legacyEnvironment.windowObject,
    documentObject: legacyEnvironment.documentObject,
    storage: legacyEnvironment.storage,
  });

  legacyController.mount();
  assert.deepEqual(controllerState(legacyController), { expanded: true, width: null });
  assert.equal(legacyEnvironment.root.hasAttribute("data-expanded"), true);
  legacyController.destroy();

  // JSON restoration, drag resize, max/canvas constraints, snap collapse, update
  // preservation, and active-drag cleanup retain the extracted hook contract.
  const handle = new FakeHandle();
  const resizeEnvironment = makeEnvironment({ handle });
  resizeEnvironment.storage.setItem(
    "cadence-ops-rail",
    JSON.stringify({ state: "expanded", width: 320 }),
  );
  const resizeController = component.createNavRailController({
    el: resizeEnvironment.root,
    windowObject: resizeEnvironment.windowObject,
    documentObject: resizeEnvironment.documentObject,
    storage: resizeEnvironment.storage,
  });

  resizeController.mount();
  assert.deepEqual(controllerState(resizeController), { expanded: true, width: 320 });
  assert.equal(resizeEnvironment.root.style.width, "320px");
  assert.equal(handle.listenerCount("pointerdown"), 1);

  let prevented = 0;
  handle.dispatchEvent({
    type: "pointerdown",
    pointerId: 7,
    clientX: 500,
    preventDefault: () => (prevented += 1),
  });
  assert.equal(prevented, 1);
  assert.equal(handle.capturedPointerId, 7);
  assert.equal(resizeEnvironment.root.style.transition, "none");

  resizeEnvironment.windowObject.dispatchEvent({ type: "pointermove", clientX: 0 });
  assert.deepEqual(controllerState(resizeController), { expanded: true, width: 480 });
  assert.equal(resizeEnvironment.root.style.width, "440px");

  resizeEnvironment.windowObject.dispatchEvent({ type: "pointerup" });
  assert.equal(resizeEnvironment.root.style.transition, "");
  assert.deepEqual(JSON.parse(resizeEnvironment.storage.getItem("cadence-ops-rail")), {
    state: "expanded",
    width: 480,
  });

  resizeEnvironment.windowObject.innerWidth = 700;
  resizeEnvironment.windowObject.dispatchEvent({ type: "resize" });
  assert.equal(resizeEnvironment.root.style.width, "140px");

  resizeEnvironment.windowObject.innerWidth = 1300;
  resizeEnvironment.windowObject.dispatchEvent({ type: "resize" });
  assert.equal(resizeEnvironment.root.style.width, "480px");

  handle.dispatchEvent({
    type: "pointerdown",
    pointerId: 8,
    clientX: 500,
    preventDefault() {},
  });
  resizeEnvironment.windowObject.dispatchEvent({ type: "pointermove", clientX: 880 });
  assert.deepEqual(controllerState(resizeController), { expanded: false, width: 480 });
  assert.equal(resizeEnvironment.root.style.width, "");
  resizeEnvironment.windowObject.dispatchEvent({ type: "pointerup" });
  assert.deepEqual(JSON.parse(resizeEnvironment.storage.getItem("cadence-ops-rail")), {
    state: "collapsed",
    width: 480,
  });

  resizeEnvironment.root.dispatchEvent({
    type: "click",
    target: { closest: () => ({}) },
  });
  assert.equal(resizeEnvironment.root.style.width, "480px");

  resizeEnvironment.root.removeAttribute("data-expanded");
  resizeEnvironment.root.style.width = "";
  resizeController.update();
  assert.equal(resizeEnvironment.root.hasAttribute("data-expanded"), true);
  assert.equal(resizeEnvironment.root.style.width, "480px");

  handle.dispatchEvent({
    type: "pointerdown",
    pointerId: 9,
    clientX: 500,
    preventDefault() {},
  });
  assert.equal(resizeEnvironment.windowObject.listenerCount("pointermove"), 1);
  resizeController.destroy();
  assert.equal(handle.listenerCount("pointerdown"), 0);
  assert.equal(resizeEnvironment.windowObject.listenerCount("pointermove"), 0);
  assert.equal(resizeEnvironment.windowObject.listenerCount("pointerup"), 0);
  assert.equal(resizeEnvironment.windowObject.listenerCount("pointercancel"), 0);
  assert.equal(resizeEnvironment.windowObject.listenerCount("resize"), 0);
  assert.equal(resizeEnvironment.windowObject.listenerCount("cadence:rail-expanded"), 0);
  assert.equal(resizeEnvironment.root.listenerCount("click"), 0);
  assert.equal(resizeEnvironment.root.style.transition, "");

  console.log("ops_nav_rail_test passed");
});
