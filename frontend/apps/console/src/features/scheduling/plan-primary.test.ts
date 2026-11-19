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
  repair: undefined,
  approval_setting: undefined,
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

  it("asks everyone to request approval unless the mission applies without approval (U97)", () => {
    for (const setting of [undefined, null, "independent"] as const) {
      expect(planPrimary(plan({ unmet: [gap], approval_setting: setting }), true)).toMatchObject({
        kind: "sheet",
        act: "submit",
        label: "Accept 1 gap and request approval",
      });
      expect(planPrimary(plan({ approval_setting: setting }), true)).toMatchObject({
        kind: "sheet",
        act: "submit",
        label: "Request approval",
        note: null,
      });
    }
    expect(planPrimary(plan({ approval_setting: "direct" }), false)).toMatchObject({
      act: "submit",
      label: "Request approval",
    });
  });

  it("gives an org admin ONE act under direct: submit, then approve (U97)", () => {
    expect(planPrimary(plan({ approval_setting: "direct" }), true)).toEqual({
      kind: "sheet",
      act: "submit_approve",
      label: "Approve and book 12 passes",
      title: "Approve and book the plan",
      confirm: "This sends R41 and approves it, and booking starts for its 12 passes.",
      note: "No second person's approval is needed, as this mission's setting allows. Sending and approving are both recorded.",
    });
    expect(planPrimary(plan({ approval_setting: "direct", unmet: [gap] }), true)).toMatchObject({
      act: "submit_approve",
      label: "Accept 1 gap, approve and book",
    });
  });

  it("approves a pending plan with approve only; the submitter under independent gets none (U97)", () => {
    const sub = {
      round: 1,
      actor: { kind: "user" as const, id: "u-me", name: "Me" },
      at: "2026-11-19T03:40:00Z",
      note: null,
      unchanged: false,
    };
    const pending = (setting: PlanDetail["approval_setting"]) =>
      plan({ state: "pending_approval", submission: sub, approval_setting: setting });
    expect(planPrimary(pending("independent"), true, { userId: "u-other" })).toMatchObject({
      kind: "sheet",
      act: "approve",
      label: "Approve and book 12 passes",
    });
    expect(planPrimary(pending("independent"), true, { userId: "u-me" })).toEqual({
      kind: "none",
      note: "You submitted this plan, so another org admin approves it.",
    });
    // Under direct, or a setting the read doesn't carry, the submitter may approve (403 = backstop).
    for (const setting of ["direct", undefined] as const)
      expect(planPrimary(pending(setting), true, { userId: "u-me" })).toMatchObject({
        act: "approve",
      });
    expect(
      planPrimary(pending("direct"), true, { userId: "u-me", refusedBecause: "edited" }),
    ).toEqual({
      kind: "blocked",
      label: "Approve and book 12 passes",
      reason: "You drafted this version of the plan, so another org admin approves it.",
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
  it("asks for approval, or again, and has admins approve and book under direct and on review", () => {
    for (const admin of [false, true]) {
      expect(titleOf(planPrimary(plan({}), admin))).toBe("Request approval");
      expect(titleOf(planPrimary(plan({ approval: sentBack }), admin))).toBe(
        "Submit the plan again",
      );
    }
    const direct = { approval_setting: "direct" as const };
    for (const p of [
      plan(direct),
      plan({ ...direct, approval: sentBack }),
      plan({ state: "pending_approval" }),
    ])
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
