import { mount } from "@vue/test-utils";
import { defineComponent, h, ref, useTemplateRef } from "vue";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { trapTab, useTabTrap } from "./trapTab.ts";

/** a11y A3 (#243): the phone Search sheet keeps Tab inside it. */
function sheet() {
  const outside = document.createElement("button");
  const root = document.createElement("div");
  root.innerHTML = `<input id="q" /><button id="cancel">Cancel</button><a id="r" href="#">Result</a>`;
  document.body.append(outside, root);
  const get = (id: string) => {
    const el = document.getElementById(id);
    if (!el) throw new Error(id);
    return el;
  };
  return { root, outside, q: get("q"), r: get("r") };
}
const tab = (shiftKey = false) =>
  new KeyboardEvent("keydown", { key: "Tab", shiftKey, cancelable: true });
afterEach(() => {
  document.body.innerHTML = "";
});

describe("trapTab", () => {
  it("wraps Tab from the last control to the first, and Shift+Tab from the first to the last", () => {
    const { root, q, r } = sheet();
    r.focus();
    const forward = tab();
    trapTab(root, forward);
    expect(forward.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(q);
    const back = tab(true);
    trapTab(root, back);
    expect(document.activeElement).toBe(r);
  });

  it("leaves Tab between inner controls to the browser", () => {
    const { root, q } = sheet();
    q.focus();
    const middle = tab();
    trapTab(root, middle);
    expect(middle.defaultPrevented).toBe(false);
  });

  it("brings focus that left the sheet back to its first control", () => {
    const { root, outside, q } = sheet();
    outside.focus();
    const stray = tab();
    trapTab(root, stray);
    expect(document.activeElement).toBe(q);
  });
});

// dashboards #458: a control that removes itself (Show all N, Try again) drops focus to <body>;
// the trap listens on the document, so the next Tab still comes back into the sheet.
const Sheet = defineComponent({
  setup() {
    const root = useTemplateRef<HTMLElement>("root");
    useTabTrap(root);
    const more = ref(true);
    return () =>
      h("div", { ref: "root", role: "dialog", "aria-modal": "true" }, [
        h("input", { id: "q" }),
        more.value
          ? h("button", { id: "all", onClick: () => (more.value = false) }, "Show all 9")
          : null,
        h("a", { id: "r", href: "#" }, "Result"),
      ]);
  },
});

describe("useTabTrap on a mounted sheet", () => {
  it("brings Tab back into the sheet after a focused control removed itself", async () => {
    const outside = document.createElement("button");
    document.body.append(outside);
    const w = mount(Sheet, { attachTo: document.body });
    const all = w.get("#all");
    if (all.element instanceof HTMLElement) all.element.focus();
    await all.trigger("click");
    expect(document.activeElement).toBe(document.body);
    const press = new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true });
    document.body.dispatchEvent(press);
    expect(press.defaultPrevented).toBe(true);
    expect(document.activeElement?.id).toBe("q");
    w.unmount();
  });

  it("closes on Esc from anywhere while it's up, focus on <body> included", () => {
    let closed = 0;
    const Closing = defineComponent({
      setup() {
        const root = useTemplateRef<HTMLElement>("root");
        useTabTrap(root, () => (closed += 1));
        return () => h("div", { ref: "root" }, [h("input")]);
      },
    });
    const w = mount(Closing, { attachTo: document.body });
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(closed).toBe(1);
    w.unmount();
  });

  it("stops listening once the sheet is gone", () => {
    const w = mount(Sheet, { attachTo: document.body });
    w.unmount();
    const press = new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true });
    document.body.dispatchEvent(press);
    expect(press.defaultPrevented).toBe(false);
  });
});
