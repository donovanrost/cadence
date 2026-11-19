import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { PlanDetail } from "./api.ts";
import ExpiredUpFront from "./ExpiredUpFront.vue";

const plan = (over: Partial<PlanDetail>): PlanDetail => ({
  id: "plan_1",
  version: 41,
  state: "draft",
  window: { from: null, to: null },
  author: null,
  counts: { passes: 12, minutes: 96, conflicts: 0, unsatisfied: 0 },
  ready_to_approve: true,
  updated_at: "2026-11-09T10:00:00Z",
  created_at: null,
  passes: [],
  demand: { rule_met: 3, rule_total: 3, spacecraft: [], rules: [] },
  unmet: [],
  conflicts: [],
  at_risk: [],
  unconfirmed: null,
  chain: null,
  execution: null,
  provider_freeze: null,
  approval: null,
  submission: null,
  previous_round: null,
  chain_head: null,
  superseded: null,
  repair_of: null,
  superseded_by: null,
  latest_version: undefined,
  repair: undefined,
  approval_setting: undefined,
  expired: undefined,
  expired_digest: undefined,
  next_expiry_at: undefined,
  ...over,
});

const item = (id: string, reason: "opportunity_expired" | "no_booking_window") => ({
  snapshot_id: id,
  spacecraft: null,
  station: null,
  aos: "2026-11-16T00:10:00Z",
  expires_at: reason === "no_booking_window" ? null : "2026-11-15T23:00:00Z",
  reason,
});
const closed = (count: number, reservable: number, items = [item("a", "opportunity_expired")]) => ({
  count,
  reservable_count: reservable,
  items,
});

/** #273 (director's condition 2; #340, #341): the approver sees what an approval would skip. */
describe("ExpiredUpFront", () => {
  it("says how many passes can't be booked and what approving books, with the list", async () => {
    const w = mount(ExpiredUpFront, {
      props: { plan: plan({ state: "pending_approval", expired: closed(36, 1476) }) },
    });
    expect(w.text()).toContain(
      "36 of R41's passes can't be booked any more: their booking window has closed. Approving books the other 1,476; the 36 are recorded as skipped.",
    );
    await w.get("button").trigger("click");
    expect(w.text()).toContain("AOS");
  });
  it("adds 'or the provider gave none' when a listed pass has no window, and words the proposal", () => {
    const w = mount(ExpiredUpFront, {
      props: {
        plan: plan({ expired: closed(3, 37, [item("a", "no_booking_window")]) }),
        proposal: true,
      },
    });
    expect(w.text()).toContain(
      "3 of the proposal's passes can't be booked any more: their booking window has closed, or the provider gave none. Applying it books the other 37; the 3 are recorded as skipped.",
    );
  });
  it("says one pass in the singular and notes a capped list", async () => {
    const one = mount(ExpiredUpFront, { props: { plan: plan({ expired: closed(1, 5) }) } });
    expect(one.text()).toContain(
      "1 of R41's passes can't be booked any more: its booking window has closed. Approving books the other 5; it's recorded as skipped.",
    );
    const capped = mount(ExpiredUpFront, { props: { plan: plan({ expired: closed(6200, 10) }) } });
    await capped.get("button").trigger("click");
    expect(capped.text()).toContain("Showing the first 1 of 6,200.");
  });
  it("shows nothing when nothing closed or everything did (Approve's reason says that)", () => {
    expect(mount(ExpiredUpFront, { props: { plan: plan({}) } }).text()).toBe("");
    expect(mount(ExpiredUpFront, { props: { plan: plan({ expired: closed(4, 0) }) } }).text()).toBe(
      "",
    );
  });
  it("says to reload once the server's next close has passed, never keyed on AOS", () => {
    const past = mount(ExpiredUpFront, {
      props: { plan: plan({ next_expiry_at: "2000-01-01T00:00:00Z" }) },
    });
    expect(past.text()).toBe(
      "A pass's booking window has closed since this loaded. Reload to update the list.",
    );
    const future = mount(ExpiredUpFront, {
      props: { plan: plan({ next_expiry_at: "2999-01-01T00:00:00Z" }) },
    });
    expect(future.text()).toBe("");
  });
});
