import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { decode, missionId } from "@/api/index.ts";
import { answerByPath, configState } from "@/features/changes/fixtures.ts";
import { modelRevisionReader } from "./approval/api.ts";
import RevisionRollout from "./approval/RevisionRollout.vue";
import CatalogScreen from "./CatalogScreen.vue";
import ImportScreen from "./ImportScreen.vue";

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

const run = (permissions: readonly string[]) => ({
  id: "run-1",
  status: "failed",
  started_at: "2026-11-10T10:00:00Z",
  completed_at: "2026-11-10T10:00:04Z",
  file: { name: "earendil.xtce", format_label: "XTCE", size_bytes: 1024 },
  failure_reason: "The file isn't XTCE.",
  declaration_count: null,
  diagnostics: [],
  revision: null,
  base_revision: null,
  diff: null,
  permissions,
});

async function at(path: string, routes: Readonly<Record<string, unknown>>) {
  vi.stubGlobal("fetch", answerByPath(routes));
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC; the lint type service can't resolve .vue imports.
      { path: "/catalog", name: "setup.catalog", component: CatalogScreen },
      // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC; the lint type service can't resolve .vue imports.
      { path: "/catalog/import/:importId?", name: "setup.catalog.import", component: ImportScreen },
    ],
  });
  await router.push(path);
  const w = mount({ template: "<RouterView />" }, { global: { plugins: [router] } });
  await flushPromises();
  return w;
}
const links = (w: Awaited<ReturnType<typeof at>>) => w.findAll("a").map((a) => a.text());

describe("catalog import gates read catalog.import (#1160 row 3)", () => {
  it("offers an operator who isn't an admin Import a new revision when the server sends it", async () => {
    const index = (permissions: readonly string[]) => ({
      "/missions/m-1/catalog": { databases: [], database: null, permissions },
    });
    const w = await at("/catalog", index(["catalog.import"]));
    expect(links(w)).toContain("Import a new revision");
    w.unmount();
    const without = await at("/catalog", index([]));
    expect(links(without)).not.toContain("Import a new revision");
    without.unmount();
  });

  it("offers Replace file on a finished import run only with catalog.import", async () => {
    const path = "/missions/m-1/catalog/imports/run-1";
    const w = await at("/catalog/import/run-1", { [path]: run(["catalog.import"]) });
    expect(links(w)).toContain("Replace file");
    w.unmount();
    const without = await at("/catalog/import/run-1", { [path]: run([]) });
    expect(links(without)).not.toContain("Replace file");
    without.unmount();
  });
});

describe("C3 Roll out to on a revision's page reads config.stage (#1160 row 1)", () => {
  const revision = () => {
    const r = decode(modelRevisionReader, {
      id: "mm-1",
      status: "candidate",
      imported_at: null,
      imported_by: null,
      catalog_revision: { id: "cr-4", number: 4, label: null, database_id: "db-1" },
      decision: null,
      viewer_can_decide: false,
      affected_groups: null,
      affected_groups_count: null,
      viewer_is_importer: false,
      cannot_decide_because: null,
      plans_ready: true,
      comparison: null,
    });
    if (!r.ok) throw new Error(r.error.message);
    return r.value;
  };
  const shown = async (permissions: readonly string[]) => {
    vi.stubGlobal("fetch", answerByPath({ "/missions/m-1/config": configState(permissions) }));
    const w = mount(RevisionRollout, { props: { revision: revision() } });
    await flushPromises();
    const text = w.text();
    w.unmount();
    return text;
  };

  it("shows an operator who isn't an admin where the revision can go, and no one without it", async () => {
    expect(await shown(["config.stage"])).toContain(
      "Spacecraft can't move to rev 4 until it's approved.",
    );
    expect(await shown([])).toBe("");
  });
});
