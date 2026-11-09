import { describe, expect, it } from "vite-plus/test";
import type { PlanDetail } from "./api.ts";
import { planHeaderTail, planPrimary } from "./plan-primary.ts";

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
  superseded: null,
  repair_of: null,
  ...over,
});
const gap = { requirement_id: "r1", requirement_version: 1, spacecraft_id: "sc1", why: [] };

describe("planPrimary", () => {
  it("blocks on a station_unavailable conflict with the station wording (U26)", () => {
    const p = planPrimary(
      plan({
        conflicts: [
          {
            code: "station_unavailable",
            spacecraft_id: undefined,
            snapshot_ids: ["c"],
            ground_station_id: "gs-sva",
            window_id: "w1",
            kind: "outage",
          },
        ],
      }),
      true,
    );
    expect(p).toMatchObject({
      kind: "blocked",
      reason: "1 drafted pass on a station that's down. Move or remove it to submit.",
    });
  });

  it("blocks on conflicts with the reason, whoever submits", () => {
    const p = planPrimary(
      plan({
        conflicts: [
          {
            code: "selected_contacts_overlap",
            spacecraft_id: "sc1",
            snapshot_ids: ["a", "b"],
            ground_station_id: undefined,
            window_id: undefined,
            kind: undefined,
          },
        ],
      }),
      true,
    );
    expect(p).toMatchObject({
      kind: "blocked",
      reason: "1 conflict. Move or remove a pass to submit.",
    });
  });

  it("asks admins to accept gaps and submit, members to request approval", () => {
    expect(planPrimary(plan({ unmet: [gap] }), true)).toMatchObject({
      kind: "sheet",
      label: "Accept 1 gap and submit",
    });
    expect(planPrimary(plan({ unmet: [gap] }), false)).toMatchObject({
      kind: "sheet",
      label: "Accept 1 gap and request approval",
    });
    expect(planPrimary(plan({}), true)).toMatchObject({
      kind: "sheet",
      label: "Submit and book 12 passes",
    });
  });

  it("lets only admins act on pending approval and offers Continue on interruption", () => {
    expect(planPrimary(plan({ state: "pending_approval" }), false).kind).toBe("none");
    expect(planPrimary(plan({ state: "failed" }), true, "run_1")).toMatchObject({
      kind: "link",
      label: "Open the re-plan proposal",
      to: { query: { run: "run_1" } },
    });
    expect(planPrimary(plan({ state: "pending_approval" }), true)).toMatchObject({
      label: "Approve and book 12 passes",
    });
    expect(planPrimary(plan({ state: "interrupted" }), true)).toMatchObject({
      kind: "execute",
      label: "Continue booking",
    });
  });
});

describe("planHeaderTail drafter (ux: reviewer ≠ author)", () => {
  it("names the drafter while waiting for an admin", () => {
    expect(
      planHeaderTail(
        plan({ state: "pending_approval", author: { kind: "user", id: "u", name: "Mira K." } }),
      ),
    ).toBe("waiting for an admin · drafted by Mira K.");
    expect(planHeaderTail(plan({ state: "pending_approval" }))).toBe("waiting for an admin");
  });
});
