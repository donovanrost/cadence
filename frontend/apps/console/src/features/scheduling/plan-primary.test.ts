import { describe, expect, it } from "vite-plus/test";
import { stationId as stationIdReader } from "@/api/index.ts";
import type { PlanDetail } from "./api.ts";
import { planHeaderTail, planPrimary, type PlanPrimary } from "./plan-primary.ts";

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
            ground_station_id: stationIdReader("gs-sva"),
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
    expect(planPrimary(plan({ state: "failed" }), true, { openRepairRun: "run_1" })).toMatchObject({
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

describe("planPrimary sheet titles name the act without the count (U36, ux)", () => {
  const sentBack = {
    decision: "rejected" as const,
    actor: { kind: "user" as const, id: "u", name: "Mira K." },
    at: "2026-11-09T10:52:00Z",
    reason: "Move 004 off HBK",
    exceptions: [],
  };
  const titleOf = (p: PlanPrimary) => (p.kind === "sheet" ? p.title : null);
  it("asks members for approval, or again, and has admins approve and book in every round", () => {
    expect(titleOf(planPrimary(plan({}), false))).toBe("Request approval");
    expect(titleOf(planPrimary(plan({ approval: sentBack }), false))).toBe("Submit the plan again");
    for (const p of [plan({}), plan({ approval: sentBack }), plan({ state: "pending_approval" })])
      expect(titleOf(planPrimary(p, true))).toBe("Approve and book the plan");
  });
});

describe("planPrimary interrupted (ux 1a906155)", () => {
  it("offers Continue booking unless nothing is left to send", () => {
    expect(planPrimary(plan({ state: "interrupted" }), true).kind).toBe("execute");
    expect(planPrimary(plan({ state: "interrupted" }), true, { requestsLeft: 3 }).kind).toBe(
      "execute",
    );
    expect(planPrimary(plan({ state: "interrupted" }), true, { requestsLeft: 0 })).toEqual({
      kind: "none",
      note: null,
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

describe("unconfirmed and unknown states (#52, U30)", () => {
  it("offers no action for unconfirmed and degrades an unknown state", () => {
    expect(planPrimary(plan({ state: "unconfirmed" }), true)).toEqual({ kind: "none", note: null });
    expect(planHeaderTail(plan({ state: "unconfirmed" }))).toBe("unconfirmed");
    expect(planPrimary(plan({ state: "unrecognized" }), true).kind).toBe("none");
  });
});

describe("booking progress (qa: the count must climb)", () => {
  const exec = (o: Partial<NonNullable<PlanDetail["execution"]>>) => ({
    requested: 40,
    sent: 0,
    never_sent: 40,
    confirmed: 0,
    uncertain: 0,
    rejected: 0,
    failed: 0,
    ...o,
  });
  it("counts sent while executing, booked while confirmations arrive, then settles", () => {
    expect(planHeaderTail(plan({ state: "executing", execution: exec({ sent: 12 }) }))).toBe(
      "booking · 12 of 40 sent",
    );
    expect(
      planHeaderTail(
        plan({
          state: "executing",
          execution: exec({ sent: 30, never_sent: 10, confirmed: 5, uncertain: 25 }),
        }),
      ),
    ).toBe("booking · 30 of 40 sent · 5 booked");
    const settling = plan({
      state: "partially_reserved",
      execution: exec({ sent: 40, never_sent: 0, confirmed: 7, uncertain: 33 }),
    });
    expect(planHeaderTail(settling)).toBe("booking · 7 of 40 booked");
    expect(planPrimary(settling, true)).toEqual({ kind: "none", note: null });
    const settled = plan({
      state: "partially_reserved",
      execution: exec({ sent: 40, never_sent: 0, confirmed: 38, rejected: 2 }),
    });
    expect(planHeaderTail(settled)).toBe("38 of 40 booked");
    expect(planPrimary(settled, true).kind).toBe("link");
  });
});
