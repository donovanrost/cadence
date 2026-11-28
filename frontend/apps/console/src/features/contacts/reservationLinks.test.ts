import { flushPromises, mount, RouterLinkStub } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import type { PlanRef } from "./planLinks.ts";
import ReservationRecord from "./ReservationRecord.vue";

/** Synthetic reservation reads in contacts.md's shape (#676), not captured from a server. */
const reservation = (plan: unknown, requirement: unknown) => ({
  reservation: {
    id: "res-1",
    provider_revision: 4,
    lifecycle_state: "confirmed",
    provider: { id: "nl", version: 4 },
    transport: null,
    plan,
    requirement,
    scheduled_contact_id: "sc-1",
    last_reconciled_at: null,
  },
  values: [],
  audit: { entries: [], next_cursor: null },
});

afterEach(() => vi.unstubAllGlobals());

async function open(body: unknown, plan: PlanRef | null = null) {
  vi.stubGlobal(
    "fetch",
    vi.fn(() => Promise.resolve(new Response(JSON.stringify({ data: body }), { status: 200 }))),
  );
  const w = mount(ReservationRecord, {
    props: { missionId: missionId("m"), passId: "p-1", providerName: "Northlight", plan },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
  const details = w.get("details");
  details.element.setAttribute("open", "");
  await details.trigger("toggle");
  await flushPromises();
  return w;
}

describe("the reservation record's plan and requirement (#676)", () => {
  it("opens the plan on K1 (on the pass's plan day) and the requirement on its page", async () => {
    const w = await open(reservation({ id: "plan-1", version: 3 }, { id: "req-1", version: 2 }), {
      id: "plan-1",
      version: 3,
      day: "2026-11-14T00:00:00Z",
    });
    const links = w.findAllComponents(RouterLinkStub);
    expect(links.map((l) => l.text())).toEqual(["plan-1 · v3", "req-1 · v2"]);
    expect(links[0]?.props("to")).toEqual({
      name: "ops.contacts.plan",
      query: { plan: "plan-1", day: "2026-11-14", version: "3" },
    });
    expect(links[1]?.props("to")).toEqual({
      name: "setup.contact-planning.requirement",
      params: { requirementId: "req-1" },
    });
  });

  it("opens a plan without its day when the pass names another, and links nothing it lacks", async () => {
    const other = await open(reservation({ id: "plan-2", version: null }, null), {
      id: "plan-1",
      version: 3,
      day: "2026-11-14T00:00:00Z",
    });
    expect(other.findAllComponents(RouterLinkStub).map((l) => l.props("to"))).toEqual([
      { name: "ops.contacts.plan", query: { plan: "plan-2" } },
    ]);
    const direct = await open(reservation(null, null));
    expect(direct.findAllComponents(RouterLinkStub)).toHaveLength(0);
    expect(direct.text()).not.toContain("Plan");
  });
});
