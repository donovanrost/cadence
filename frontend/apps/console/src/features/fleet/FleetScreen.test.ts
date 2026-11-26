import { flushPromises, mount } from "@vue/test-utils";
import { createMemoryHistory, createRouter } from "vue-router";
import { describe, expect, it, vi } from "vite-plus/test";
import FleetScreen from "./FleetScreen.vue";

const screen = vi.hoisted(() => ({ small: false }));
vi.mock("@/shell/index.ts", async (original) => {
  const { computed } = await import("vue");
  return {
    ...(await original<typeof import("@/shell/index.ts")>()),
    useMissionScope: () =>
      computed(() => ({
        organization: { id: "org-1", slug: "reflect-orbital", name: "Reflect Orbital" },
        mission: { id: "m1", slug: "earendil", name: "Earendil" },
      })),
    useSmallScreen: () => computed(() => screen.small),
  };
});
vi.mock("./useFleet.ts", async () => {
  const { computed } = await import("vue");
  const { fleetOf: fleet, spacecraftRow: row } = await import("./fixtures.ts");
  const value = fleet(Array.from({ length: 300 }, (_, i) => row(i + 1)));
  return {
    useFleet: () => ({
      state: computed(() => ({ status: "ready", value, receivedAt: new Date() })),
      refetch: () => undefined,
    }),
  };
});

async function fleetScreen(small: boolean) {
  screen.small = small;
  const blank = { render: () => null };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/fleet", name: "ops.fleet", component: blank },
      { path: "/spacecraft/:scId/:tab?", name: "ops.spacecraft", component: blank },
    ],
  });
  await router.push("/fleet");
  const w = mount(FleetScreen, { global: { plugins: [router] }, attachTo: document.body });
  await flushPromises();
  return w;
}

/**
 * #176 follow-up (Fleet's longest task): one list for the viewport. The phone's list renders a
 * link per craft; hidden with CSS on a desktop it still cost Fleet's first render at 1,000.
 */
describe("FleetScreen's table view", () => {
  it("mounts only the table on a desktop, never the phone's row list", async () => {
    const w = await fleetScreen(false);
    expect(w.find('ul[aria-label="Fleet"]').exists()).toBe(false);
    expect(w.find("table").exists()).toBe(true);
    w.unmount();
  });

  it("mounts only the row list on a phone", async () => {
    const w = await fleetScreen(true);
    expect(w.find('ul[aria-label="Fleet"]').exists()).toBe(true);
    expect(w.find("table").exists()).toBe(false);
    w.unmount();
  });
});
