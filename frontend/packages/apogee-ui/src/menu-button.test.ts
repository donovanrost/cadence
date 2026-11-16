import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { defineComponent, h, nextTick } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import ApMenuButton from "./ApMenuButton.vue";
import ApMenuItem from "./ApMenuItem.vue";

const chosen = vi.fn();
const Harness = defineComponent({
  setup() {
    return () =>
      h(
        ApMenuButton,
        { label: "More section actions" },
        {
          default: () => [
            h(
              ApMenuItem,
              { disabled: "It's already first.", onSelect: () => chosen("up") },
              () => "Move up",
            ),
            h(ApMenuItem, { onSelect: () => chosen("down") }, () => "Move down"),
            h("p", { role: "none" }, "Danger"),
            h(ApMenuItem, { to: "/elsewhere", onSelect: () => chosen("link") }, () => "Open"),
          ],
        },
      );
  },
});
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { path: "/", component: { render: () => null } },
    { path: "/elsewhere", component: { render: () => null } },
  ],
});

let wrapper: ReturnType<typeof mount> | null = null;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  chosen.mockReset();
});
function render() {
  wrapper = mount(Harness, { attachTo: document.body, global: { plugins: [router] } });
  return wrapper;
}
const focused = () => document.activeElement?.textContent?.trim() ?? "";
async function press(target: Element | null, key: string) {
  target?.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }));
  await nextTick();
}
async function opened() {
  const w = render();
  await w.get("button[aria-haspopup]").trigger("click");
  await nextTick();
  return w;
}
const trigger = (w: ReturnType<typeof mount>) => w.get("button[aria-haspopup]").element;

describe("ApMenuButton (design-language §6)", () => {
  it("names the trigger and the menu, and wires aria-haspopup / aria-expanded / aria-controls", async () => {
    const w = render();
    const button = w.get("button[aria-haspopup]");
    expect(button.attributes("aria-haspopup")).toBe("menu");
    expect(button.attributes("aria-expanded")).toBe("false");
    expect(button.attributes("aria-label")).toBe("More section actions");
    await button.trigger("click");
    const menu = w.get('[role="menu"]');
    expect(button.attributes("aria-expanded")).toBe("true");
    expect(button.attributes("aria-controls")).toBe(menu.attributes("id"));
    expect(menu.attributes("aria-label")).toBe("More section actions");
  });

  it("moves focus to the first item on open, even when it is disabled", async () => {
    await opened();
    expect(focused()).toContain("Move up");
  });

  it("keeps a disabled item focusable, describes it by its reason, and never runs it", async () => {
    const w = await opened();
    const up = w.findAll('[role="menuitem"]')[0];
    expect(up?.attributes("aria-disabled")).toBe("true");
    expect(document.getElementById(up?.attributes("aria-describedby") ?? "")?.textContent).toBe(
      "It's already first.",
    );
    for (const key of ["Enter", " "]) {
      await press(document.activeElement, key);
      await up?.trigger("click");
    }
    expect(chosen).not.toHaveBeenCalled();
    expect(w.find('[role="menu"]').exists()).toBe(true);
    expect(document.activeElement).toBe(up?.element);
  });

  it("cycles with ↑/↓ over items only (not role=none content) and jumps with Home/End", async () => {
    await opened();
    await press(document.activeElement, "ArrowDown");
    expect(focused()).toBe("Move down");
    await press(document.activeElement, "ArrowDown");
    expect(focused()).toBe("Open");
    await press(document.activeElement, "ArrowDown");
    expect(focused()).toContain("Move up");
    await press(document.activeElement, "ArrowUp");
    expect(focused()).toBe("Open");
    await press(document.activeElement, "Home");
    expect(focused()).toContain("Move up");
    await press(document.activeElement, "End");
    expect(focused()).toBe("Open");
  });

  it("opens on ↓ at the first item and on ↑ at the last, from the trigger", async () => {
    const w = render();
    await press(trigger(w), "ArrowUp");
    expect(focused()).toBe("Open");
    await press(document.activeElement, "Escape");
    await press(trigger(w), "ArrowDown");
    expect(focused()).toContain("Move up");
  });

  it("closes on Esc and returns focus to the trigger", async () => {
    const w = await opened();
    await press(document.activeElement, "Escape");
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger(w));
    expect(w.get("button[aria-haspopup]").attributes("aria-expanded")).toBe("false");
  });

  it("closes on Tab without pulling focus back to the trigger", async () => {
    const w = await opened();
    await press(document.activeElement, "Tab");
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).not.toBe(trigger(w));
  });

  it("a chosen item closes the menu and hands focus back to the trigger before its action", async () => {
    const w = await opened();
    chosen.mockImplementation(() => {
      expect(document.activeElement).toBe(trigger(w));
    });
    await w.findAll('[role="menuitem"]')[1]?.trigger("click");
    expect(chosen).toHaveBeenCalledWith("down");
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger(w));
  });

  it("a link item is a menuitem that navigates and closes the menu", async () => {
    const w = await opened();
    const link = w.get('a[role="menuitem"]');
    expect(link.attributes("tabindex")).toBe("-1");
    await link.trigger("click");
    await router.isReady();
    await nextTick();
    expect(chosen).toHaveBeenCalledWith("link");
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger(w));
  });

  it("closes on a click outside", async () => {
    const w = await opened();
    document.body.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
    await nextTick();
    expect(w.find('[role="menu"]').exists()).toBe(false);
  });
});
