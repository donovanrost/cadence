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

describe("retired app surfaces (sweep row 2, qa 11:22Z)", () => {
  it("send a bookmark to its console home without asking for the retired surface's host", async () => {
    const urls: string[] = [];
    vi.stubGlobal("fetch", (input: string) => {
      urls.push(input);
      return Promise.resolve(new Response(JSON.stringify({ data: { apps: [], permissions: [] } })));
    });
    const stub = { template: "<div />" };
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: "/apps", name: "setup.apps", component: stub },
        { path: "/apps/:appKey/:surface?", name: "setup.app", component: AppSurfaceScreen },
        { path: "/spacecraft", name: "setup.spacecraft", component: stub },
        { path: "/spacecraft/new", name: "setup.spacecraft.new", component: stub },
        { path: "/profiles/new", name: "setup.profile.new", component: stub },
        { path: "/spacecraft/:spacecraftId", name: "setup.spacecraft.one", component: stub },
      ],
    });
    await router.push("/apps/spacecraft/new");
    const w = mount({ template: "<RouterView />" }, { global: { plugins: [router] } });
    await flushPromises();
    expect(router.currentRoute.value.name).toBe("setup.spacecraft.new");
    expect(urls.some((u) => u.includes("/surfaces/new/host"))).toBe(false);
    w.unmount();
  });
});
