import { createMemoryHistory, createRouter } from "vue-router";
import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { spacecraftId } from "@/api";
import type { Expired, SupersededBy } from "./lifecycle.ts";
import PlanLifecycleCallouts from "./PlanLifecycleCallouts.vue";

async function render(supersededBy: SupersededBy | null, expired: Expired | null) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", component: { render: () => null } },
      { path: "/plan", name: "ops.contacts.plan", component: { render: () => null } },
    ],
  });
  await router.push("/");
  return mount(PlanLifecycleCallouts, {
    props: { day: "2026-11-16", supersededBy, expired },
    global: { plugins: [router] },
  });
}

describe("U61 lifecycle callouts on K1", () => {
  it("names the replacing plan and opens it on the same day", async () => {
    const w = await render(
      {
        plan_id: "contact_plan_44",
        revision: 44,
        author: { kind: "user" as const, id: "u", name: "Mira K." },
        at: "2026-11-16T10:05:00Z",
      },
      null,
    );
    expect(w.text()).toContain("Superseded by R44 (Mira K.) at");
    const open = w.find("a");
    expect(open.text()).toBe("Open R44");
    expect(open.attributes("href")).toBe("/plan?day=2026-11-16&plan=contact_plan_44");
  });

  it("lists what an approval left out under Show N; the review's line says it once (U97)", async () => {
    const w = await render(null, {
      count: 2,
      reservable_count: 1476,
      items: [
        {
          spacecraft: { id: spacecraftId("sc_1"), name: "EARENDIL-001", scid: null },
          station: { ref: "svalbard-1", id: null, code: "SVA", name: null },
          aos: "2026-11-16T00:10:00Z",
        },
        { spacecraft: null, station: null, aos: "2026-11-16T00:20:00Z" },
      ],
    });
    expect(w.text()).not.toContain("Approved.");
    expect(w.text()).toContain("Show 2");
    expect(w.text()).not.toContain("EARENDIL-001");
    const toggle = w.findAll("button").find((b) => b.text() === "Show 2");
    expect(toggle).toBeDefined();
    await toggle?.trigger("click");
    expect(w.text()).toContain("EARENDIL-001 · SVA · AOS");
    expect(w.text()).toContain("Hide");
  });

  it("shows nothing when the plan wasn't replaced and nothing was left out", async () => {
    const w = await render(null, null);
    expect(w.text()).toBe("");
  });
});
