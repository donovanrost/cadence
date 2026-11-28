import { flushPromises, mount, RouterLinkStub } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { computed, defineComponent, h } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import type { PlanningSummary } from "./api.ts";
import PolicyTab from "./PolicyTab.vue";
import RequirementScreen from "./RequirementScreen.vue";
import RequirementsTab from "./RequirementsTab.vue";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  // #1160: an operator who isn't an organization admin; the gates read the server's tokens only.
  useMissionScope: () =>
    computed(() => ({
      mission: { id: missionId("m-1"), name: "EARENDIL" },
      organization: { id: "org-1", capabilities: [] },
    })),
  useSession: () => ({ user: { id: "u-op" }, capabilities: [] }),
}));
afterEach(() => vi.unstubAllGlobals());

/** Answers `fetch` by path (`/api/v1` dropped) with `{data}`, 404 otherwise. */
function serve(routes: Readonly<Record<string, unknown>>) {
  vi.stubGlobal("fetch", (input: string) => {
    const path = new URL(input, "http://x").pathname.replace(/^\/api\/v1/, "");
    const data = routes[path];
    return Promise.resolve(
      data === undefined
        ? new Response(JSON.stringify({ error: { code: "not_found" } }), { status: 404 })
        : new Response(JSON.stringify({ data })),
    );
  });
}

const OPERATOR = ["planning.requirement.edit"];
const ADMIN = [
  "planning.template.manage",
  "fleet_planning_policy.manage",
  "planning.requirement.edit",
  "planning.approve",
];

describe("the Requirements tab: each gate reads its own token (#1160 rows 4 and 5)", () => {
  const Panel = defineComponent({
    props: { canEdit: Boolean },
    setup: (p) => () => h("p", p.canEdit ? "requirements editable" : "requirements read-only"),
  });
  const tab = (permissions: readonly string[]) => {
    const summary: PlanningSummary = {
      policy: null,
      coverage: {
        spacecraft_total: 0,
        covered: 0,
        contacts_per_day: null,
        uplink_passes_per_day: null,
      },
      templates: [],
      not_covered: [],
      permissions,
    };
    const w = mount(RequirementsTab, {
      props: { summary, missionId: missionId("m-1") },
      global: {
        stubs: { PlanningStats: true, RequirementsPanel: Panel, RouterLink: RouterLinkStub },
      },
    });
    const text = w.text();
    const newTemplate = w.html().includes("New template");
    w.unmount();
    return { text, newTemplate };
  };

  it("lets an operator who isn't an admin edit requirements, but not templates", () => {
    const t = tab(OPERATOR);
    expect(t.text).toContain("requirements editable");
    expect(t.newTemplate).toBe(false);
  });

  it("offers templates only with planning.template.manage, and nothing with no token", () => {
    expect(tab(ADMIN).newTemplate).toBe(true);
    expect(tab(["planning.template.manage"]).text).toContain("requirements read-only");
    const none = tab([]);
    expect(none.text).toContain("requirements read-only");
    expect(none.newTemplate).toBe(false);
  });
});

describe("the planning policy's Save reads fleet_planning_policy.manage (#1160 row 5)", () => {
  const policy = (permissions: readonly string[]) => ({
    policy_id: null,
    version: null,
    active_version: null,
    document: null,
    pending: null,
    schema: [],
    defaults: null,
    permissions,
  });
  const shown = async (permissions: readonly string[]) => {
    serve({ "/missions/m-1/contact-planning/policy": policy(permissions) });
    const w = mount(PolicyTab, { props: { missionId: missionId("m-1") } });
    await flushPromises();
    const text = w.text();
    w.unmount();
    return text;
  };

  it("isn't offered to an operator who edits requirements, and says who changes the policy", async () => {
    const text = await shown(OPERATOR);
    expect(text).not.toContain("Create policy");
    expect(text).toContain("Org admins change the planning policy.");
  });

  it("is offered with fleet_planning_policy.manage", async () => {
    expect(await shown(["fleet_planning_policy.manage"])).toContain("Create policy");
  });
});

describe("one requirement reads planning.requirement.edit (#1160 row 4)", () => {
  const base = "/missions/m-1/contact-planning/requirements";
  const detail = (permissions: readonly string[]) => ({
    id: "req_1",
    state: "active",
    version: 2,
    spacecraft: { id: "sc_1", name: "EARENDIL-1", scid: 1 },
    template_id: null,
    template_version: null,
    content: {},
    updated_at: "2026-11-20T06:00:00Z",
    state_changed: null,
    rule_summary: null,
    versions: [],
    held_by: null,
    permissions,
  });
  const at = async (path: string, routes: Readonly<Record<string, unknown>>) => {
    serve(routes);
    const stub = { template: "<div />" };
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: "/", name: "setup.contact-planning", component: stub },
        {
          path: "/r/:requirementId",
          name: "setup.contact-planning.requirement",
          // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC; the lint type service can't resolve .vue imports.
          component: RequirementScreen,
        },
      ],
    });
    await router.push(path);
    const Editor = defineComponent({ setup: () => () => h("p", "requirement form") });
    const w = mount(
      { template: "<RouterView />" },
      {
        global: {
          plugins: [router],
          stubs: { RequirementEditor: Editor, RequirementView: true },
        },
      },
    );
    await flushPromises();
    const text = w.text();
    const edit = w.findAll("button").some((b) => b.text() === "Edit");
    w.unmount();
    return { text, edit };
  };
  const schema = (permissions: readonly string[]) => ({ fields: [], defaults: null, permissions });

  it("opens the New form for an operator who isn't an admin", async () => {
    const r = await at("/r/new", { [`${base}/schema`]: schema(OPERATOR) });
    expect(r.text).toContain("requirement form");
    expect(r.text).not.toContain("Mission operators add requirements.");
  });

  it("without the token, says who adds requirements instead of the form", async () => {
    const r = await at("/r/new", { [`${base}/schema`]: schema([]) });
    expect(r.text).not.toContain("requirement form");
    expect(r.text).toContain("Mission operators add requirements.");
  });

  it("offers Edit on an active one-off only with the token", async () => {
    expect((await at("/r/req_1", { [`${base}/req_1`]: detail(OPERATOR) })).edit).toBe(true);
    expect((await at("/r/req_1", { [`${base}/req_1`]: detail([]) })).edit).toBe(false);
  });
});
