import { mount } from "@vue/test-utils";
import { defineComponent, h, onMounted, ref } from "vue";
import { createMemoryHistory, createRouter, RouterView } from "vue-router";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { useRouteFocus } from "./route-focus.ts";

/** SPA focus on route change (lead's a11y item): the heading takes focus; the title is announced. */
const page = (title: string) => defineComponent({ render: () => h("h1", title) });
const own = defineComponent({
  setup() {
    const input = ref<HTMLInputElement | null>(null);
    onMounted(() => input.value?.focus());
    return () => h("div", [h("h1", "Own"), h("input", { ref: input, "aria-label": "Name" })]);
  },
});
const late = defineComponent({
  setup() {
    const ready = ref(false);
    onMounted(() => setTimeout(() => (ready.value = true), 30));
    return () => (ready.value ? h("h1", "Late") : h("p", "Loading…"));
  },
});
const plain = defineComponent({ render: () => h("p", "No heading here") });
/** A read that outlasts the heading wait (60 ms in these tests): h1 at ~150 ms. */
const slow = defineComponent({
  setup() {
    const ready = ref(false);
    onMounted(() => setTimeout(() => (ready.value = true), 150));
    return () => (ready.value ? h("h1", "Slow") : h("p", "Loading spacecraft…"));
  },
});

const mounted: { unmount: () => void }[] = [];
afterEach(() => {
  for (const w of mounted.splice(0)) w.unmount();
  document.body.innerHTML = "";
});

async function setup() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/a", component: page("Alpha") },
      { path: "/b", component: page("Beta") },
      { path: "/own", component: own },
      { path: "/late", component: late },
      { path: "/plain", component: plain },
      { path: "/slow", component: slow },
    ],
  });
  router.afterEach((to) => {
    document.title = `${to.path.slice(1)} · Cadence`;
  });
  const Host = defineComponent({
    setup() {
      const main = ref<HTMLElement | null>(null);
      const { announcement } = useRouteFocus(main, { headingWaitMs: 60 });
      return () => [
        h("main", { ref: main, id: "main" }, [h(RouterView)]),
        h("p", { id: "live", role: "status", "aria-live": "polite" }, announcement.value),
      ];
    },
  });
  await router.push("/a");
  await router.isReady();
  const w = mount(Host, { global: { plugins: [router] }, attachTo: document.body });
  mounted.push(w);
  return { router, w };
}
const settle = (ms = 120) => new Promise((r) => setTimeout(r, ms));
const live = (w: Awaited<ReturnType<typeof setup>>["w"]) => w.find("#live").text();

describe("route-change focus", () => {
  it("focuses the new page's h1 (tabindex -1) and announces its title", async () => {
    const { router, w } = await setup();
    await router.push("/b");
    await settle();
    const active = document.activeElement;
    expect(active?.tagName).toBe("H1");
    expect(active?.textContent).toBe("Beta");
    expect(active?.getAttribute("tabindex")).toBe("-1");
    expect(live(w)).toBe("b · Cadence");
  });

  it("waits for a heading that renders after the page's read", async () => {
    const { router } = await setup();
    await router.push("/late");
    await settle();
    expect(document.activeElement?.textContent).toBe("Late");
  });

  it("falls back to <main> when the page has no h1", async () => {
    const { router } = await setup();
    await router.push("/plain");
    await settle();
    expect(document.activeElement?.id).toBe("main");
  });

  it("moves from <main> to a heading that arrives after the wait, if focus is still on <main>", async () => {
    const { router } = await setup();
    await router.push("/slow");
    await settle(100);
    expect(document.activeElement?.id).toBe("main");
    await settle(150);
    expect(document.activeElement?.textContent).toBe("Slow");
  });

  it("but not if the user moved on while it loaded", async () => {
    const { router } = await setup();
    const field = document.createElement("input");
    document.body.appendChild(field);
    await router.push("/slow");
    await settle(100);
    field.focus();
    await settle(150);
    expect(document.activeElement).toBe(field);
  });

  it("leaves focus alone when the page takes it itself", async () => {
    const { router } = await setup();
    await router.push("/own");
    await settle();
    expect(document.activeElement?.tagName).toBe("INPUT");
  });

  it("never steals focus back from the user while waiting for a late heading", async () => {
    const { router } = await setup();
    const field = document.createElement("input");
    document.body.appendChild(field);
    await router.push("/late");
    // The user tabs into a field before the late heading renders (it arrives at ~30 ms).
    field.focus();
    await settle();
    expect(document.activeElement).toBe(field);
  });

  it("moves focus off the link that navigated, even when that link stays (a rail item)", async () => {
    const { router } = await setup();
    const rail = document.createElement("a");
    rail.href = "#";
    document.body.appendChild(rail);
    rail.focus();
    await router.push("/b");
    await settle();
    expect(document.activeElement?.textContent).toBe("Beta");
  });

  it("does nothing for a query-only change or the first load", async () => {
    const { router, w } = await setup();
    expect(live(w)).toBe("");
    const button = document.createElement("button");
    document.body.appendChild(button);
    button.focus();
    await router.push("/a?tab=2");
    await settle();
    expect(document.activeElement).toBe(button);
    expect(live(w)).toBe("");
    button.remove();
  });
});
