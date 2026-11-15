import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { nextTick } from "vue";
import MoreMenu from "./MoreMenu.vue";

const items = [
  { id: "up", label: "Move up", disabled: "It's already first." },
  { id: "down", label: "Move down" },
  { id: "remove", label: "Remove section…" },
];
let wrapper: ReturnType<typeof open> | null = null;
function open() {
  return mount(MoreMenu, {
    props: { items, label: "More section actions" },
    attachTo: document.body,
  });
}
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});
const focused = () => document.activeElement?.textContent?.trim() ?? "";
async function press(target: Element | null, key: string, shiftKey = false) {
  target?.dispatchEvent(new KeyboardEvent("keydown", { key, shiftKey, bubbles: true }));
  await nextTick();
}
async function opened() {
  wrapper = open();
  await wrapper.get("button[aria-haspopup]").trigger("click");
  await nextTick();
  return wrapper;
}

describe("⋯ menu button (design-language §6)", () => {
  it("announces a menu and moves focus to the first item on open, disabled or not", async () => {
    const w = await opened();
    expect(w.get("button[aria-haspopup]").attributes("aria-haspopup")).toBe("menu");
    expect(w.find('[role="menu"]').exists()).toBe(true);
    expect(focused()).toContain("Move up");
  });
  it("keeps a disabled item focusable and describes it by its reason", async () => {
    const w = await opened();
    const up = w.findAll('[role="menuitem"]')[0];
    expect(up?.attributes("aria-disabled")).toBe("true");
    const why = up?.attributes("aria-describedby") ?? "";
    expect(document.getElementById(why)?.textContent).toBe("It's already first.");
    await up?.trigger("click");
    expect(w.emitted("select")).toBeUndefined();
  });
  it("cycles with ↑/↓ and jumps with Home/End", async () => {
    const w = await opened();
    const menu = w.get('[role="menu"]').element;
    await press(document.activeElement, "ArrowDown");
    expect(focused()).toBe("Move down");
    await press(document.activeElement, "ArrowDown");
    await press(document.activeElement, "ArrowDown");
    expect(focused()).toContain("Move up");
    await press(document.activeElement, "ArrowUp");
    expect(focused()).toBe("Remove section…");
    await press(document.activeElement, "Home");
    expect(focused()).toContain("Move up");
    await press(document.activeElement, "End");
    expect(focused()).toBe("Remove section…");
    expect(menu.isConnected).toBe(true);
  });
  it("closes on Esc and returns focus to the trigger", async () => {
    const w = await opened();
    await press(document.activeElement, "Escape");
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(w.get("button[aria-haspopup]").element);
  });
  it("closes on Tab without pulling focus back", async () => {
    const w = await opened();
    const item = document.activeElement;
    await press(item, "Tab");
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).not.toBe(w.get("button[aria-haspopup]").element);
  });
  it("opens on ↓ / ↑ from the trigger, and a chosen item hands focus back to it", async () => {
    wrapper = open();
    const trigger = wrapper.get("button[aria-haspopup]").element;
    await press(trigger, "ArrowUp");
    expect(focused()).toBe("Remove section…");
    await wrapper.findAll('[role="menuitem"]')[1]?.trigger("click");
    expect(wrapper.emitted("select")?.[0]).toEqual(["down"]);
    expect(document.activeElement).toBe(trigger);
  });
  it("does nothing on Enter or Space on a disabled item: no action, still open, reason read", async () => {
    const w = await opened();
    const up = w.findAll('[role="menuitem"]')[0];
    expect(document.activeElement).toBe(up?.element);
    // A focused <button> turns Enter/Space into a click; send both, as a browser would.
    for (const key of ["Enter", " "]) {
      await press(document.activeElement, key);
      await up?.trigger("click");
    }
    expect(w.emitted("select")).toBeUndefined();
    expect(w.find('[role="menu"]').exists()).toBe(true);
    expect(document.activeElement).toBe(up?.element);
    expect(up?.attributes("aria-describedby")).toBeTruthy();
  });
});
