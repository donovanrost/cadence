import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { defineComponent, h, nextTick } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import ScopeSwitcher from "./ScopeSwitcher.vue";
import type { ConsoleScope } from "./scope.ts";

const organization = {
  id: "org-1",
  slug: "acme",
  name: "Acme",
  role: null,
  capabilities: [],
  missions: [
    { id: missionId("m1"), slug: "alpha", name: "Alpha" },
    { id: missionId("m2"), slug: "bravo", name: "Bravo" },
  ],
};
const scope: ConsoleScope = {
  kind: "mission",
  organization,
  mission: { id: missionId("m1"), slug: "alpha", name: "Alpha" },
};
const Host = defineComponent(() => () => [
  h(ScopeSwitcher, { scope }),
  h("button", { type: "button", id: "after" }, "Next on the page"),
]);
let wrapper: ReturnType<typeof mount> | null = null;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});
async function opened() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/:org/:mission/now", name: "ops.now", component: { render: () => null } },
      { path: "/:org/:mission/setup", name: "setup.readiness", component: { render: () => null } },
    ],
  });
  wrapper = mount(Host, { global: { plugins: [router] }, attachTo: document.body });
  await wrapper.get("button[aria-expanded]").trigger("click");
  await nextTick();
  return wrapper;
}

describe("ScopeSwitcher: a disclosure of mission links (ux, a11y-checklist B3)", () => {
  it("is a disclosure, not a menu: aria-expanded + aria-controls, no aria-haspopup or menu roles", async () => {
    const w = await opened();
    const button = w.get("button[aria-expanded]");
    expect(button.attributes("aria-haspopup")).toBeUndefined();
    expect(button.attributes("aria-expanded")).toBe("true");
    expect(document.getElementById(button.attributes("aria-controls") ?? "")).not.toBeNull();
    expect(w.find('[role="menu"], [role="menuitem"]').exists()).toBe(false);
  });

  it("names the list by its label and marks the current mission", async () => {
    const w = await opened();
    const list = w.get("ul");
    expect(document.getElementById(list.attributes("aria-labelledby") ?? "")?.textContent).toBe(
      "Missions in Acme",
    );
    const current = w.findAll("a").find((a) => a.attributes("aria-current") === "true");
    expect(current?.text()).toBe("Alpha");
  });

  it("closes when focus moves past the last mission to the page", async () => {
    const w = await opened();
    const links = w.findAll("a");
    const last = links[links.length - 1]?.element;
    const after = w.get("#after").element;
    last?.dispatchEvent(new FocusEvent("focusout", { bubbles: true, relatedTarget: after }));
    await nextTick();
    expect(w.find("ul").exists()).toBe(false);
    expect(w.get("button[aria-expanded]").attributes("aria-expanded")).toBe("false");
  });

  it("stays open while focus moves between its own links", async () => {
    const w = await opened();
    const [first, second] = w.findAll("a");
    first?.element.dispatchEvent(
      new FocusEvent("focusout", { bubbles: true, relatedTarget: second?.element ?? null }),
    );
    await nextTick();
    expect(w.find("ul").exists()).toBe(true);
  });

  it("closes on Esc and returns focus to the button", async () => {
    const w = await opened();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await nextTick();
    expect(w.find("ul").exists()).toBe(false);
    expect(document.activeElement).toBe(w.get("button[aria-expanded]").element);
  });
});
