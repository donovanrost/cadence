import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import { viewJson } from "../fixtures.test-support.ts";

// No live socket in a unit test: invalidation is the shell's concern.
vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useMissionScope: () =>
    computed(() => ({ mission: { id: missionIdReader("m-1"), name: "EARENDIL" } })),
}));

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** D5 answers for the viewer; D14 is author-only (403 for a member); D17 an empty feed. */
function stubApi(canEdit: boolean) {
  const urls: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      urls.push(url);
      const path = new URL(url, "http://console.test").pathname;
      if (path.endsWith("/dashboards/dashboard"))
        return reply(200, { data: { ...viewJson(), can_edit: canEdit, snapshot: null } });
      if (path.endsWith("/activity")) return reply(200, { data: { events: [], next: null } });
      if (path.endsWith("/settings"))
        return canEdit ? reply(500, {}) : reply(403, { error: { code: "forbidden" } });
      return reply(404, { error: { code: "not_found" } });
    }),
  );
  return urls;
}

async function open(tab: string) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/d", name: "ops.dashboards", component: { render: () => null } },
      { path: "/d/:dashboardId", name: "ops.dashboard", component: { render: () => null } },
      {
        path: "/d/:dashboardId/settings/:tab?",
        name: "ops.dashboard.settings",
        // Lazily, as the app registers it (the .vue import reads as untyped to the linter).
        component: () => import("./SettingsScreen.vue"),
      },
    ],
  });
  await router.push(`/d/dashboard/settings/${tab}`);
  await router.isReady();
  const wrapper = mount({ template: "<RouterView />" }, { global: { plugins: [router] } });
  await flushPromises();
  return { router, wrapper };
}

/**
 * ux Dashboards.md § Settings and dashboards (L8b parity): someone who isn't an author reads
 * Activity and Diagnostics only. Dev can't show this live (author_dashboards == operate_mission),
 * so this is the evidence (lead, 11-14).
 */
// Mounting the router and screen takes ~5 s at load 40-50 (dashboards): a longer budget per test.
const MOUNT_TIMEOUT = 30_000;

describe("dashboard settings for someone who isn't an author", () => {
  afterEach(() => vi.unstubAllGlobals());

  it(
    "lands a General link on Activity, shows two tabs and no Export, and never reads D14",
    async () => {
      const urls = stubApi(false);
      const { router, wrapper } = await open("general");

      expect(router.currentRoute.value.path).toBe("/d/dashboard/settings/activity");
      const tabs = wrapper.findAll("nav[aria-label='Settings sections'] a").map((a) => a.text());
      expect(tabs).toEqual(["Activity", "Diagnostics"]);
      expect(wrapper.text()).not.toContain("Export");
      expect(wrapper.text()).toContain("Bus overview");
      expect(
        urls.some((u) => new URL(u, "http://console.test").pathname.endsWith("/settings")),
      ).toBe(false);
      wrapper.unmount();
    },
    MOUNT_TIMEOUT,
  );

  it(
    "gives an author all four tabs and Export",
    async () => {
      stubApi(true);
      const { wrapper } = await open("activity");

      const tabs = wrapper.findAll("nav[aria-label='Settings sections'] a").map((a) => a.text());
      expect(tabs).toEqual(["General", "Sharing", "Activity", "Diagnostics"]);
      expect(wrapper.text()).toContain("Export");
      wrapper.unmount();
    },
    MOUNT_TIMEOUT,
  );
});
