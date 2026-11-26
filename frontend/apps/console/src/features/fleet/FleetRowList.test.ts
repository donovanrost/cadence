import { flushPromises, mount } from "@vue/test-utils";
import { createMemoryHistory, createRouter } from "vue-router";
import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "./fixtures.ts";
import FleetRowList from "./FleetRowList.vue";

const blank = { render: () => null };

async function listOf(count: number) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", component: blank },
      { path: "/spacecraft/:scId/:tab?", name: "ops.spacecraft", component: blank },
    ],
  });
  await router.push("/");
  const rows = Array.from({ length: count }, (_, i) => spacecraftRow(i + 1));
  const w = mount(FleetRowList, {
    props: { rows, total: count },
    global: { plugins: [router] },
    attachTo: document.body,
  });
  await flushPromises();
  return w;
}

/** #868: the phone's Fleet list windows its rows like FleetTable, never rendering all 1,000. */
describe("FleetRowList", () => {
  it("renders a window of 1,000 craft, each with its name link and place in the whole list", async () => {
    const w = await listOf(1000);
    const items = w.findAll("li");
    expect(items.length).toBeGreaterThan(0);
    expect(items.length).toBeLessThan(60);
    expect(items[0]?.attributes("aria-setsize")).toBe("1000");
    expect(items.map((li) => li.attributes("aria-posinset"))).toEqual(
      items.map((_, i) => String(i + 1)),
    );
    expect(items[0]?.get("a").text()).toBe("EARENDIL-001");
    expect(items[0]?.get("a").attributes("href")).toContain("/spacecraft/1");
    // The skipped rows keep their height, so the list scrolls as if every row were there.
    const style = w.get("ul").attributes("style") ?? "";
    expect(style).toContain(`padding-bottom: ${(1000 - items.length) * 75}px`);
    expect(w.text()).toContain("1,000 of 1,000");
    w.unmount();
  });

  it("renders every row of a short fleet", async () => {
    const w = await listOf(5);
    expect(w.findAll("li")).toHaveLength(5);
    w.unmount();
  });
});
