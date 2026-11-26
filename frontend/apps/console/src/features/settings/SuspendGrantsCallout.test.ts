import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import SuspendGrantsCallout from "./SuspendGrantsCallout.vue";
import { suspensionsOf } from "./suspensions.ts";
import type { PendingSuspension } from "./useSectionSave.ts";

/** #499 (ca-ux, U105 #507): the callout in place of the save line, at organization level. */
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
        missions: [{ id: missionIdReader("m-1"), slug: "earendil", name: "Earendil" }],
      },
    })),
}));

const grant = (id: string, mission: string, missionName: string | null) => ({
  id,
  mission: { id: mission, name: missionName },
  service: { id: `svc-${id}`, name: "Nightly planner" },
  allowed_actions: ["plan"],
  valid_until: "2026-12-19T06:40:00Z",
});
function pending(changed = false): PendingSuspension {
  const suspensions = suspensionsOf({
    kind: "conflict",
    code: "approval_tightening_suspends_grants",
    message: "x",
    details: { grants: [grant("a", "m-1", "EARENDIL"), grant("b", "m-9", null)], digest: "d1" },
  });
  if (!suspensions) throw new Error("unread");
  return { values: {}, what: "Saved", outcome: undefined, suspensions, changed };
}

async function render(p: PendingSuspension) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", component: { render: () => null } },
      {
        path: "/console/:org/:mission/setup/contact-planning",
        name: "setup.contact-planning",
        component: { render: () => null },
      },
    ],
  });
  await router.push("/");
  return mount(SuspendGrantsCallout, {
    props: { pending: p, busy: false },
    global: { plugins: [router] },
    attachTo: document.body,
  });
}

describe("the suspension callout (U105)", () => {
  it("alerts, starts focus on Cancel, and links each mission in scope to its grants", async () => {
    const w = await render(pending());
    try {
      expect(w.get("[data-suspend-grants]").attributes("role")).toBe("alert");
      await vi.waitFor(() => expect(document.activeElement?.textContent?.trim()).toBe("Cancel"));
      const links = w.findAll("a");
      expect(links.map((a) => a.text())).toEqual(["Open grants"]);
      expect(links[0]?.attributes("href")).toBe(
        "/console/reflect-orbital/earendil/setup/contact-planning",
      );
      expect(w.text()).toContain("Unknown mission · Nightly planner");
      expect(w.text()).toContain("Save and suspend 2 grants");
      expect(w.text()).not.toContain("changed, so nothing was saved");
    } finally {
      w.unmount();
    }
  });

  it("says the list changed above the new list, and emits confirm and cancel", async () => {
    const w = await render(pending(true));
    try {
      expect(w.text()).toContain(
        "The grants this would suspend changed, so nothing was saved. Check the list, then save again.",
      );
      const button = (label: string) => w.findAll("button").find((b) => b.text().startsWith(label));
      await button("Save and suspend")?.trigger("click");
      await button("Cancel")?.trigger("click");
      expect(w.emitted("confirm")).toHaveLength(1);
      expect(w.emitted("cancel")).toHaveLength(1);
    } finally {
      w.unmount();
    }
  });
});
