import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import AppSurfaceScreen from "./AppSurfaceScreen.vue";

vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useMissionScope: () => computed(() => ({ mission: { id: missionId("m-1"), name: "EARENDIL" } })),
}));

afterEach(() => vi.unstubAllGlobals());

const row = (surface_id: string, order: number, purpose: string) => ({
  surface_id,
  label: surface_id,
  order,
  purpose,
  area: "setup",
  scope: "mission",
});
const comms = {
  key: "comms",
  name: "Communications",
  description: null,
  installed: true,
  state: "installed",
  version: 1,
  consequence_if_missing: null,
  surfaces: [
    row("overview", 10, "overview"),
    row("transports", 30, "collection"),
    row("transport", 40, "subject_detail"),
    row("routing_detail", 60, "subject_detail"),
    row("ground_stations", 70, "collection"),
    row("ground_station", 80, "subject_detail"),
    row("ground_station_new", 140, "configuration"),
    row("ground_station_edit", 150, "configuration"),
  ],
};

function setup() {
  const urls: string[] = [];
  vi.stubGlobal("fetch", (input: string) => {
    urls.push(input);
    return Promise.resolve(
      new Response(JSON.stringify({ data: { apps: [comms], permissions: [] } })),
    );
  });
  const stub = { template: "<div />" };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/apps", name: "setup.apps", component: stub },
      { path: "/apps/:appKey/:surface?", name: "setup.app", component: AppSurfaceScreen },
      { path: "/comms", name: "setup.comms", component: stub },
      { path: "/comms/transports/:transportId?", name: "setup.comms.transports", component: stub },
      { path: "/stations/:stationId?", name: "setup.stations", component: stub },
    ],
  });
  return { urls, router };
}

describe("one-record app surfaces (lead, qa 11-16: Edit Ground Station opened with no station)", () => {
  it("leave the tab bar: only surfaces that work without a record are tabs", async () => {
    const { router } = setup();
    await router.push("/apps/comms/overview");
    const w = mount({ template: "<RouterView />" }, { global: { plugins: [router] } });
    await flushPromises();
    const tabs = w.findAll('nav[aria-label="App pages"] a').map((a) => a.text());
    expect(tabs).toEqual(["overview", "transports", "ground_stations", "ground_station_new"]);
    w.unmount();
  });

  it.each([
    ["/apps/comms/ground_station_edit?ground_station_id=gs-1", "/stations/gs-1"],
    ["/apps/comms/ground_station?ground_station_id=gs-1", "/stations/gs-1"],
    ["/apps/comms/ground_station_edit", "/stations"],
    ["/apps/comms/transport?transport_id=tr-9", "/comms/transports/tr-9"],
    ["/apps/comms/routing_detail?routing_rule_id=r-2", "/comms"],
  ])("a direct open of %s goes to %s without asking for its host", async (from, to) => {
    const { router, urls } = setup();
    await router.push(from);
    const w = mount({ template: "<RouterView />" }, { global: { plugins: [router] } });
    await flushPromises();
    expect(router.currentRoute.value.fullPath).toBe(to);
    expect(urls.some((u) => u.includes("/host"))).toBe(false);
    w.unmount();
  });
});
