import { jsonFixture } from "../../../../../../test-support/json-fixture";
import { required } from "../../../../../../test-support/required";
import assert from "node:assert/strict";
import { afterEach, test } from "vite-plus/test";
import { createNavRailController, type NavRailOptions } from "./nav_rail_controller";
afterEach(() => {
  document.body.innerHTML = "";
});
test("rail coordination, persistence, resize bounds, and listener cleanup", () => {
  const trackListeners = <T extends EventTarget>(target: T) => {
    const listeners = new Map<string, Set<EventListenerOrEventListenerObject>>();
    const add = target.addEventListener.bind(target);
    const remove = target.removeEventListener.bind(target);
    target.addEventListener = (
      type: string,
      listener: EventListenerOrEventListenerObject | null,
      options?: boolean | AddEventListenerOptions,
    ) => {
      if (listener) {
        const active = listeners.get(type) ?? new Set<EventListenerOrEventListenerObject>();
        active.add(listener);
        listeners.set(type, active);
      }
      add(type, listener, options);
    };
    target.removeEventListener = (
      type: string,
      listener: EventListenerOrEventListenerObject | null,
      options?: boolean | EventListenerOptions,
    ) => {
      if (listener) listeners.get(type)?.delete(listener);
      remove(type, listener, options);
    };
    return Object.assign(target, {
      listenerCount: (type: string) => listeners.get(type)?.size ?? 0,
    });
  };
  const makeHandle = () => {
    const handle = Object.assign(trackListeners(document.createElement("div")), {
      capturedPointerId: 0,
    });
    handle.setAttribute("data-rail-resize", "");
    handle.setPointerCapture = (id: number) => {
      handle.capturedPointerId = id;
    };
    return handle;
  };
  const makeEnvironment = ({
    handle = null,
    innerWidth = 1000,
    peerWidth = 200,
  }: { handle?: HTMLElement | null; innerWidth?: number; peerWidth?: number } = {}) => {
    const iframe = document.createElement("iframe");
    document.body.append(iframe);
    const windowObject = iframe.contentWindow;
    assert.ok(windowObject);
    Object.defineProperty(windowObject, "innerWidth", {
      value: innerWidth,
      writable: true,
      configurable: true,
    });
    const documentObject = windowObject.document;
    const rail = (role: string, width: number) => {
      const element = trackListeners(document.createElement("aside"));
      element.dataset.storageKey = "cadence-ops-rail";
      element.dataset.railRole = role;
      element.getBoundingClientRect = () =>
        new DOMRect(0, 0, element.style.width ? Number.parseFloat(element.style.width) : width, 0);
      documentObject.body.append(element);
      return element;
    };
    const root = rail("navigation", 224),
      peer = rail("context", peerWidth);
    const toggle = document.createElement("button");
    toggle.setAttribute("data-rail-toggle", "");
    root.append(toggle);
    if (handle) root.append(handle);
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => {
        values.set(key, value);
      },
    };
    return {
      documentObject,
      peer,
      root,
      storage,
      windowObject: trackListeners(windowObject),
      toggle,
    };
  };

  const lifecycleEnvironment = makeEnvironment();
  const createController = (options: NavRailOptions) =>
    createNavRailController({
      windowObject: lifecycleEnvironment.windowObject,
      documentObject: lifecycleEnvironment.documentObject,
      storage: lifecycleEnvironment.storage,
      ...options,
    });
  const component = { createNavRailController: createController };
  const controllerState = (controller: ReturnType<typeof createNavRailController>) =>
    controller.state();
  const lifecycleController = createController({ el: lifecycleEnvironment.root });
  lifecycleController.mount();
  assert.deepEqual(controllerState(lifecycleController), { expanded: false, width: null });
  assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), false);
  assert.equal(lifecycleEnvironment.root.listenerCount("click"), 1);
  assert.equal(lifecycleEnvironment.windowObject.listenerCount("resize"), 1);
  assert.equal(lifecycleEnvironment.windowObject.listenerCount("cadence:rail-expanded"), 1);

  let expandedEvents = 0;
  lifecycleEnvironment.windowObject.addEventListener("cadence:rail-expanded", (event) => {
    if (event instanceof CustomEvent && event.detail === lifecycleEnvironment.root)
      expandedEvents += 1;
  });

  lifecycleEnvironment.toggle.click();

  assert.deepEqual(controllerState(lifecycleController), { expanded: true, width: null });
  assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), true);
  assert.equal(expandedEvents, 1);
  assert.deepEqual(
    jsonFixture(required(lifecycleEnvironment.storage.getItem("cadence-ops-rail"))),
    {
      state: "expanded",
      width: null,
    },
  );

  lifecycleEnvironment.windowObject.dispatchEvent(
    new CustomEvent("cadence:rail-expanded", { detail: lifecycleEnvironment.peer }),
  );

  assert.deepEqual(controllerState(lifecycleController), { expanded: false, width: null });
  assert.equal(lifecycleEnvironment.root.hasAttribute("data-expanded"), false);
  assert.equal(
    jsonFixture(required(lifecycleEnvironment.storage.getItem("cadence-ops-rail"))).state,
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
  const handle = makeHandle();
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
  const pointerDown = new PointerEvent("pointerdown", {
    pointerId: 7,
    clientX: 500,
    cancelable: true,
  });
  pointerDown.preventDefault = () => {
    prevented++;
  };
  handle.dispatchEvent(pointerDown);
  assert.equal(prevented, 1);
  assert.equal(handle.capturedPointerId, 7);
  assert.equal(resizeEnvironment.root.style.transition, "none");

  resizeEnvironment.windowObject.dispatchEvent(new PointerEvent("pointermove", { clientX: 0 }));
  assert.deepEqual(controllerState(resizeController), { expanded: true, width: 480 });
  assert.equal(resizeEnvironment.root.style.width, "440px");

  resizeEnvironment.windowObject.dispatchEvent(new Event("pointerup"));
  assert.equal(resizeEnvironment.root.style.transition, "");
  assert.deepEqual(jsonFixture(required(resizeEnvironment.storage.getItem("cadence-ops-rail"))), {
    state: "expanded",
    width: 480,
  });

  Object.defineProperty(resizeEnvironment.windowObject, "innerWidth", { value: 700 });
  resizeEnvironment.windowObject.dispatchEvent(new Event("resize"));
  assert.equal(resizeEnvironment.root.style.width, "140px");

  Object.defineProperty(resizeEnvironment.windowObject, "innerWidth", { value: 1300 });
  resizeEnvironment.windowObject.dispatchEvent(new Event("resize"));
  assert.equal(resizeEnvironment.root.style.width, "480px");

  handle.dispatchEvent(new PointerEvent("pointerdown", { pointerId: 8, clientX: 500 }));
  resizeEnvironment.windowObject.dispatchEvent(new PointerEvent("pointermove", { clientX: 880 }));
  assert.deepEqual(controllerState(resizeController), { expanded: false, width: 480 });
  assert.equal(resizeEnvironment.root.style.width, "");
  resizeEnvironment.windowObject.dispatchEvent(new Event("pointerup"));
  assert.deepEqual(jsonFixture(required(resizeEnvironment.storage.getItem("cadence-ops-rail"))), {
    state: "collapsed",
    width: 480,
  });

  resizeEnvironment.toggle.click();
  assert.equal(resizeEnvironment.root.style.width, "480px");

  resizeEnvironment.root.removeAttribute("data-expanded");
  resizeEnvironment.root.style.width = "";
  resizeController.update();
  assert.equal(resizeEnvironment.root.hasAttribute("data-expanded"), true);
  assert.equal(resizeEnvironment.root.style.width, "480px");

  handle.dispatchEvent(new PointerEvent("pointerdown", { pointerId: 9, clientX: 500 }));
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
