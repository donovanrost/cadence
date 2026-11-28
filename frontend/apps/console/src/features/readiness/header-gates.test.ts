import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import { answerByPath, configState } from "@/features/changes/fixtures.ts";
import { areaKeys } from "./api.ts";
import ReadinessScreen from "./ReadinessScreen.vue";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  // #1160: an operator who isn't an organization admin.
  useMissionScope: () =>
    computed(() => ({
      mission: { id: missionId("m-1"), name: "EARENDIL" },
      organization: { id: "org-1", capabilities: [] },
    })),
  useSession: () => ({ user: { id: "u-op" }, capabilities: [] }),
}));
afterEach(() => vi.unstubAllGlobals());

const readiness = (permissions: readonly string[]) => ({
  evaluated_at: "2026-11-08T02:41:17Z",
  verdict: { blocker: 0, caution: 0, stale: 0, not_set_up: 0, optional: 0 },
  areas: areaKeys.map((key) => ({
    key,
    status: "ready",
    count: 1,
    unit: "things",
    secondary_count: null,
    secondary_unit: null,
    detail: null,
  })),
  findings: [],
  recent_changes: [],
  permissions,
});

async function header(stage: readonly string[], catalog: readonly string[]) {
  vi.stubGlobal(
    "fetch",
    answerByPath({
      "/missions/m-1/config": configState(stage),
      "/missions/m-1/readiness": readiness(catalog),
    }),
  );
  const stub = { template: "<div />" };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC; the lint type service can't resolve .vue imports.
      { path: "/", name: "setup.readiness", component: ReadinessScreen },
      { path: "/spacecraft/new", name: "setup.spacecraft.new", component: stub },
      { path: "/catalog/import", name: "setup.catalog.import", component: stub },
    ],
  });
  await router.push("/");
  // The areas, findings and changes link elsewhere; only the header is under test here.
  const panels = { AreaTile: true, FindingsPanel: true, RecentChangesPanel: true };
  const w = mount({ template: "<RouterView />" }, { global: { plugins: [router], stubs: panels } });
  await flushPromises();
  const names = w.findAll("a").map((a) => a.text());
  w.unmount();
  return names.filter((n) => n === "Add spacecraft" || n === "Import catalog");
}

describe("Readiness header actions, each from its own check (#1160 rows 1 and 3)", () => {
  it("offers an operator who isn't an admin both when the server sends both", async () => {
    expect(await header(["config.stage"], ["catalog.import"])).toEqual([
      "Add spacecraft",
      "Import catalog",
    ]);
  });

  it("offers each action by its own token, and neither without them", async () => {
    expect(await header(["config.stage"], [])).toEqual(["Add spacecraft"]);
    expect(await header([], ["catalog.import"])).toEqual(["Import catalog"]);
    expect(await header([], [])).toEqual([]);
  });
});
