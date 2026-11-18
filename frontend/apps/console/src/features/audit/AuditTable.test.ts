import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import type { AuditEvent } from "./api.ts";
import AuditTable from "./AuditTable.vue";

vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useConsoleScope: () =>
    computed(() => ({
      kind: "organization" as const,
      organization: {
        id: "org_1",
        slug: "reflect-orbital",
        name: "Reflect Orbital",
        role: null,
        capabilities: [],
        missions: [{ id: missionIdReader("mission_1"), slug: "earendil", name: "Earendil" }],
      },
    })),
}));

const row = (over: Partial<AuditEvent>): AuditEvent => ({
  id: "e1",
  at: "2026-11-14T21:50:00Z",
  actor: { kind: "service", id: null, name: "Cadence" },
  kind: "commanding",
  action: "Submitted SET_MODE for 1 spacecraft",
  target: { kind: "command_group", id: "group_7", label: "SET_MODE for 1 spacecraft" },
  mission: { id: "mission_1", name: "Earendil" },
  reason: null,
  subject: undefined,
  admin_mode: undefined,
  change: undefined,
  ...over,
});

async function render(events: readonly AuditEvent[]) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", component: { render: () => null } },
      {
        path: "/console/:org/:mission/commands/:requestId/:view?",
        name: "ops.commands.request",
        component: { render: () => null },
      },
    ],
  });
  await router.push("/");
  return mount(AuditTable, { props: { events }, global: { plugins: [router] } });
}

describe("audit rows that open a page (qa 11-14)", () => {
  it("links the action itself when it already names the target (no hidden link)", async () => {
    const wrapper = await render([row({})]);
    const link = wrapper.find("a");
    expect(link.exists()).toBe(true);
    expect(link.text()).toBe("Submitted SET_MODE for 1 spacecraft");
    expect(link.attributes("href")).toBe("/console/reflect-orbital/earendil/commands/group_7");
    // The dedupe holds: the label isn't repeated after the action.
    expect(wrapper.text()).not.toContain("· SET_MODE for 1 spacecraft");
  });

  it("leaves a single request's row as text", async () => {
    const wrapper = await render([
      row({
        target: { kind: "command_request", id: "req_1", label: "NOOP" },
        action: "Requested NOOP",
      }),
    ]);
    expect(wrapper.find("a").exists()).toBe(false);
    expect(wrapper.text()).toContain("Requested NOOP");
  });

  it("tags an actor who decided in admin mode, only when true (P3 #228, ux U89)", async () => {
    const wrapper = await render([
      row({ id: "a", admin_mode: true }),
      row({ id: "b", admin_mode: false }),
      row({ id: "c", admin_mode: null }),
      row({ id: "d" }),
    ]);
    const tags = wrapper.findAll('[aria-label^="Acting as a platform admin"]');
    expect(tags).toHaveLength(1);
    expect(tags[0]?.text()).toBe("Admin mode");
  });
});
