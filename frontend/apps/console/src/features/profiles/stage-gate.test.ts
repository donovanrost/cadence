import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import { answerByPath, configState } from "@/features/changes/fixtures.ts";
import ProfilesListScreen from "./ProfilesListScreen.vue";

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

async function screen(permissions: readonly string[]) {
  vi.stubGlobal(
    "fetch",
    answerByPath({
      "/missions/m-1/config": configState(permissions),
      "/missions/m-1/profiles": { profiles: [] },
    }),
  );
  const stub = { template: "<div />" };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC; the lint type service can't resolve .vue imports.
      { path: "/profiles", name: "setup.profiles", component: ProfilesListScreen },
      { path: "/profiles/new", name: "setup.profile.new", component: stub },
    ],
  });
  await router.push("/profiles");
  const w = mount({ template: "<RouterView />" }, { global: { plugins: [router] } });
  await flushPromises();
  return w;
}

describe("Setup › Profiles, New profile (#1160 row 1)", () => {
  it("is offered to an operator who isn't an admin when the server sends config.stage", async () => {
    const w = await screen(["config.stage"]);
    expect(w.findAll("a").map((a) => a.text())).toContain("New profile");
    w.unmount();
  });

  it("is not offered without config.stage", async () => {
    const w = await screen([]);
    expect(w.findAll("a").map((a) => a.text())).not.toContain("New profile");
    w.unmount();
  });
});
