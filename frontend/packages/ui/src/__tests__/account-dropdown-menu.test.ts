import { required } from "../../../../test-support/required";
import assert from "node:assert/strict";
import { test } from "vite-plus/test";
import { createApp, defineComponent, h, nextTick } from "vue";
import AccountDropdownMenu from "../AccountDropdownMenu.vue";
import CadenceMenuItem from "../CadenceMenuItem.vue";
import { flushVue, installDom } from "../../../../test-support/mounted-contract";
const dom = installDom();
const scenarioLedger = [
  "click toggles aria-expanded, initial focus, focus return, and document listeners",
  "ArrowDown opens and ArrowUp/Down/Home/End move focus with wrapping",
  "Escape restores trigger focus and outside pointer closes without stealing focus",
  "Tab and menu activation close without returning focus",
  "destroy removes local and document listeners and resets transient state",
] as const;
const dispatchKey = (element: Element, key: string) => {
  const event = new dom.window.KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    key,
  });
  element.dispatchEvent(event);
  return event;
};

const trackedDocumentListeners = (documentObject: Document) => {
  const active = new Map<string, Set<EventListenerOrEventListenerObject>>();
  const originalAdd = documentObject.addEventListener.bind(documentObject);
  const originalRemove = documentObject.removeEventListener.bind(documentObject);

  documentObject.addEventListener = (
    type: string,
    listener: EventListenerOrEventListenerObject | null,
    options?: boolean | AddEventListenerOptions,
  ) => {
    const listeners = active.get(type) ?? new Set();
    if (listener) listeners.add(listener);
    active.set(type, listeners);
    if (listener) originalAdd(type, listener, options);
  };
  documentObject.removeEventListener = (
    type: string,
    listener: EventListenerOrEventListenerObject | null,
    options?: boolean | EventListenerOptions,
  ) => {
    if (listener) active.get(type)?.delete(listener);
    if (listener) originalRemove(type, listener, options);
  };

  return {
    activeCount: () => [...active.values()].reduce((count, listeners) => count + listeners.size, 0),
    restore() {
      documentObject.addEventListener = originalAdd;
      documentObject.removeEventListener = originalRemove;
    },
  };
};

const setup = async ({ auditListeners = false } = {}) => {
  const container = dom.window.document.createElement("div");
  const outside = dom.window.document.createElement("button");
  outside.id = "outside-account-menu";
  outside.type = "button";
  dom.window.document.body.append(container, outside);

  const listenerAudit = auditListeners ? trackedDocumentListeners(dom.window.document) : null;
  const activations: string[] = [];
  let triggerClicks = 0;

  const RuntimeOracle = defineComponent({
    name: "AccountDropdownMenuRuntimeOracle",
    setup() {
      return () =>
        h(
          AccountDropdownMenu,
          {
            class: "dropdown dropdown-end",
            "data-server-root": "preserved",
          },
          {
            trigger: ({ open }: { open: boolean }) =>
              h(
                "button",
                {
                  type: "button",
                  class: "server-trigger",
                  "data-server-trigger": "preserved",
                  "aria-haspopup": "menu",
                  "aria-expanded": String(open),
                  "aria-controls": "account-menu-panel",
                  onClick: () => (triggerClicks += 1),
                },
                "Account",
              ),
            content: ({ open, onItemSelect }: { open: boolean; onItemSelect: () => void }) => {
              const menuItem = (id: string, label: string, element = "a") =>
                h("li", { role: "presentation", "data-server-item-wrapper": id }, [
                  h(
                    CadenceMenuItem,
                    { active: open, onSelect: onItemSelect },
                    {
                      default: () =>
                        h(
                          element,
                          {
                            id,
                            ...(element === "a"
                              ? { href: `/account/${id}`, "data-phx-link": "redirect" }
                              : { type: "button" }),
                            class: "server-menu-item",
                            role: "menuitem",
                            "data-server-item": "preserved",
                            onClick: (event: Event) => {
                              if (element === "a") event.preventDefault();
                              activations.push(id);
                            },
                          },
                          label,
                        ),
                    },
                  ),
                ]);

              return h(
                "div",
                {
                  id: "account-menu-panel",
                  class: "dropdown-content menu server-panel",
                  role: "menu",
                  "data-server-panel": "preserved",
                },
                [
                  h("li", { class: "menu-title" }, "Account actions"),
                  menuItem("first-account-item", "First"),
                  menuItem("second-account-item", "Second"),
                  menuItem("third-account-item", "Third", "button"),
                ],
              );
            },
          },
        );
    },
  });

  const app = createApp(RuntimeOracle);
  app.mount(container);
  await flushVue(nextTick);

  const query = (selector: string) => container.querySelector<HTMLElement>(selector);
  const root = required(query("[data-server-root]"));
  const trigger = required(query("[data-dropdown-trigger]"));
  const panel = () => query("#account-menu-panel");
  const items = () =>
    [
      required(query("#first-account-item")),
      required(query("#second-account-item")),
      required(query("#third-account-item")),
    ] as const;

  return {
    activations,
    app,
    container,
    items,
    listenerAudit,
    outside,
    panel,
    root,
    trigger,
    triggerClicks: () => triggerClicks,
    async cleanup() {
      app.unmount();
      await flushVue(nextTick);
      listenerAudit?.restore();
      container.remove();
      outside.remove();
    },
  };
};

test(scenarioLedger[0], async () => {
  const oracle = await setup({ auditListeners: true });

  assert.equal(oracle.root.className, "dropdown dropdown-end");
  assert.equal(oracle.root.getAttribute("data-server-root"), "preserved");
  assert.equal(oracle.root.children.length, 1, "closed menu renders only its trigger");
  assert.equal(oracle.trigger.getAttribute("aria-expanded"), "false");
  assert.equal(oracle.panel(), null, "closed content must not rely on stylesheet visibility");

  oracle.trigger.click();
  await flushVue(nextTick);

  assert.equal(oracle.trigger.getAttribute("aria-controls"), required(oracle.panel()).id);
  assert.equal(required(oracle.panel()).getAttribute("role"), "menu");
  assert.equal(required(oracle.panel()).getAttribute("data-server-panel"), "preserved");
  assert.equal(oracle.items()[0].getAttribute("data-server-item"), "preserved");
  assert.equal(oracle.items()[0].getAttribute("href"), "/account/first-account-item");
  assert.equal(oracle.triggerClicks(), 1);
  assert.equal(oracle.root.classList.contains("dropdown-open"), true);
  assert.equal(oracle.trigger.getAttribute("aria-expanded"), "true");
  assert.equal(dom.window.document.activeElement, oracle.items()[0]);
  assert.ok(
    required(oracle.listenerAudit).activeCount() > 0,
    "open Reka content owns document listeners",
  );

  oracle.trigger.click();
  await flushVue(nextTick);

  assert.equal(oracle.triggerClicks(), 2);
  assert.equal(oracle.root.className, "dropdown dropdown-end");
  assert.equal(oracle.trigger.getAttribute("aria-expanded"), "false");
  assert.equal(dom.window.document.activeElement, oracle.trigger);
  assert.equal(oracle.panel(), null, "closing removes content and its focusable actions");

  await oracle.cleanup();
});

test(scenarioLedger[1], async () => {
  const oracle = await setup();
  const openEvent = dispatchKey(oracle.trigger, "ArrowDown");
  await flushVue(nextTick);

  assert.equal(openEvent.defaultPrevented, true);
  assert.equal(oracle.root.classList.contains("dropdown-open"), true);
  assert.equal(dom.window.document.activeElement, oracle.items()[0]);

  dispatchKey(oracle.items()[0], "ArrowDown");
  assert.equal(dom.window.document.activeElement, oracle.items()[1]);
  dispatchKey(oracle.items()[1], "ArrowUp");
  assert.equal(dom.window.document.activeElement, oracle.items()[0]);
  dispatchKey(oracle.items()[0], "ArrowUp");
  assert.equal(dom.window.document.activeElement, oracle.items()[2]);
  dispatchKey(oracle.items()[2], "ArrowDown");
  assert.equal(dom.window.document.activeElement, oracle.items()[0]);
  dispatchKey(oracle.items()[0], "End");
  assert.equal(dom.window.document.activeElement, oracle.items()[2]);
  dispatchKey(oracle.items()[2], "Home");
  assert.equal(dom.window.document.activeElement, oracle.items()[0]);

  await oracle.cleanup();
});

test(scenarioLedger[2], async () => {
  const oracle = await setup();

  oracle.trigger.click();
  await flushVue(nextTick);
  const escapeEvent = dispatchKey(oracle.items()[0], "Escape");
  await flushVue(nextTick);

  assert.equal(escapeEvent.defaultPrevented, true);
  assert.equal(oracle.root.classList.contains("dropdown-open"), false);
  assert.equal(dom.window.document.activeElement, oracle.trigger);

  oracle.trigger.click();
  await flushVue(nextTick);
  const outsideEvent = new globalThis.PointerEvent("pointerdown", {
    bubbles: true,
    cancelable: true,
    button: 0,
  });
  oracle.outside.focus();
  oracle.outside.dispatchEvent(outsideEvent);
  await flushVue(nextTick);

  assert.equal(oracle.root.classList.contains("dropdown-open"), false);
  assert.equal(dom.window.document.activeElement, oracle.outside);

  await oracle.cleanup();
});

test(scenarioLedger[3], async () => {
  const oracle = await setup();

  oracle.trigger.click();
  await flushVue(nextTick);
  const firstOpenItem = oracle.items()[0];
  const tabEvent = dispatchKey(firstOpenItem, "Tab");
  await flushVue(nextTick);

  assert.equal(tabEvent.defaultPrevented, false);
  assert.equal(oracle.root.classList.contains("dropdown-open"), false);
  assert.notEqual(dom.window.document.activeElement, oracle.trigger);

  oracle.trigger.click();
  await flushVue(nextTick);
  const secondOpenItem = oracle.items()[1];
  secondOpenItem.click();
  await flushVue(nextTick);

  assert.deepEqual(oracle.activations, ["second-account-item"]);
  assert.equal(oracle.root.classList.contains("dropdown-open"), false);
  assert.notEqual(dom.window.document.activeElement, oracle.trigger);

  await oracle.cleanup();
});

test(scenarioLedger[4], async () => {
  const oracle = await setup({ auditListeners: true });
  oracle.trigger.click();
  await flushVue(nextTick);

  const retainedRoot = oracle.root;
  const retainedTrigger = oracle.trigger;
  let unmountFocusCount = 0;
  retainedTrigger.focus = () => (unmountFocusCount += 1);
  assert.equal(retainedRoot.classList.contains("dropdown-open"), true);
  assert.ok(required(oracle.listenerAudit).activeCount() > 0);

  await oracle.cleanup();

  assert.equal(retainedRoot.classList.contains("dropdown-open"), false);
  assert.equal(retainedTrigger.getAttribute("aria-expanded"), "false");
  assert.equal(unmountFocusCount, 0, "unmount never returns focus to a detached trigger");
  assert.equal(
    required(oracle.listenerAudit).activeCount(),
    0,
    "Reka removes every tracked document listener",
  );
});
