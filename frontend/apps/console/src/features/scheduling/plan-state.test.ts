import { describe, expect, it } from "vite-plus/test";
// Static, not `await import` in a test body: the module's transform and load counted against the
// 5 s test timeout and timed out under load (devops' flake tracker, 11-17).
import { planDetailReader, plansReader, type Draft, type PlanSummary } from "./api.ts";
import { planView } from "./plan-state.ts";

const ready = <T>(value: T) => ({ status: "ready" as const, value, receivedAt: new Date(0) });
const run = (state: Draft["run"]["state"]): Draft => ({
  run: {
    id: "run_1",
    state,
    phase: "searching",
    horizon: { from: "2026-11-10T00:00:00Z", to: "2026-11-11T00:00:00Z" },
    failure: null,
    started_at: "2026-11-09T10:00:00Z",
    updated_at: "2026-11-09T10:01:00Z",
    stopped_at: "2026-11-09T10:01:00Z",
  },
  plan: null,
});
const noPlans = ready({ plans: [] as PlanSummary[] });

describe("planView", () => {
  it("prefers not-set-up, then the followed run", () => {
    expect(
      planView({
        notSetUp: ["fleet_planning_policy"],
        runId: null,
        draft: null,
        plans: noPlans,
        plan: null,
      }).kind,
    ).toBe("not_set_up");
    expect(
      planView({
        notSetUp: null,
        runId: "run_1",
        draft: ready(run("running")),
        plans: noPlans,
        plan: null,
      }),
    ).toMatchObject({ kind: "drafting", phase: "searching" });
    expect(
      planView({
        notSetUp: null,
        runId: "run_1",
        draft: ready(run("interrupted")),
        plans: noPlans,
        plan: null,
      }).kind,
    ).toBe("interrupted");
  });

  it("never reports a finished run without a plan as a plan", () => {
    expect(
      planView({
        notSetUp: null,
        runId: "run_1",
        draft: ready(run("completed")),
        plans: noPlans,
        plan: null,
      }).kind,
    ).toBe("draft_failed");
  });

  it("offers a draft when the day has no current plan", () => {
    expect(
      planView({ notSetUp: null, runId: null, draft: null, plans: noPlans, plan: null }).kind,
    ).toBe("no_draft");
  });
});

describe("planOfDay (superseded state)", () => {
  it("opens the newest plan when it's a superseded draft and nothing current exists", async () => {
    const { planOfDay } = await import("./plan-state.ts");
    const row = (
      id: string,
      state: PlanSummary["state"],
      superseded: PlanSummary["superseded"],
    ): PlanSummary => ({
      id,
      version: 1,
      state,
      window: { from: null, to: null },
      author: null,
      counts: { passes: 40, minutes: 320, conflicts: 0, unsatisfied: 0 },
      ready_to_approve: false,
      updated_at: "2026-11-10T10:00:00Z",
      created_at: null,
      superseded,
      repair_of: null,
    });
    const why = {
      at: "2026-11-10T11:00:00Z",
      by: null,
      reason: "template_changed" as const,
      changes: [],
    };
    expect(planOfDay([row("old", "superseded", why)])?.id).toBe("old");
    expect(planOfDay([row("new", "draft", null), row("old", "superseded", why)])?.id).toBe("new");
    expect(planOfDay([row("gone", "canceled", null)])).toBeNull();
  });

  it("U28: never opens a repair plan; an unapplied repair is the open proposal", async () => {
    const { planOfDay, openProposal } = await import("./plan-state.ts");
    const base = (id: string, state: PlanSummary["state"]): PlanSummary => ({
      id,
      version: 1,
      state,
      window: { from: null, to: null },
      author: null,
      counts: { passes: 40, minutes: 320, conflicts: 0, unsatisfied: 0 },
      ready_to_approve: false,
      updated_at: "2026-11-10T10:00:00Z",
      created_at: null,
      superseded: null,
      repair_of: null,
    });
    const repairOf = { plan: { id: "booked", version: 1 }, run_id: "run_1" };
    const proposal = { ...base("repair", "draft"), repair_of: repairOf };
    const plans = [proposal, base("booked", "reserved")];
    expect(planOfDay(plans)?.id).toBe("booked");
    expect(openProposal([proposal])?.id).toBe("repair");
    expect(openProposal([{ ...proposal, state: "reserved" }])).toBeNull();
    expect(planOfDay([proposal])).toBeNull();
  });
});

describe("plan state decoding (#52)", () => {
  it("reads unconfirmed, and an unknown state as unrecognized instead of failing", () => {
    const row = (state: string) => ({
      id: "p",
      version: 1,
      state,
      window: { from: null, to: null },
      author: null,
      counts: { passes: 1, minutes: 8, conflicts: 0, unsatisfied: 0 },
      ready_to_approve: false,
      updated_at: "2026-11-10T10:00:00Z",
    });
    const read = plansReader({ plans: [row("unconfirmed"), row("something_new")] });
    expect(read.plans.map((p) => p.state)).toEqual(["unconfirmed", "unrecognized"]);
  });
});

describe("plan detail chain_head (qa #30)", () => {
  it("reads the server's bare id, an {id, version} object, or nothing", () => {
    const detail = (chain_head: unknown) => ({
      id: "p",
      version: 1,
      state: "reserved",
      window: { from: null, to: null },
      author: null,
      counts: { passes: 0, minutes: 0, conflicts: 0, unsatisfied: 0 },
      ready_to_approve: false,
      updated_at: "2026-11-10T10:00:00Z",
      passes: [],
      demand: { rule_met: 0, rule_total: 0, spacecraft: [], rules: [] },
      unmet: [],
      conflicts: [],
      chain: [{ id: "root", version: 1 }],
      ...(chain_head === undefined ? {} : { chain_head }),
    });
    expect(planDetailReader(detail("contact_plan_head")).chain_head).toBe("contact_plan_head");
    expect(planDetailReader(detail({ id: "head", version: 2 })).chain_head).toBe("head");
    expect(planDetailReader(detail(undefined)).chain_head).toBeNull();
    expect(planDetailReader(detail(null)).chain_head).toBeNull();
  });
});

describe("interrupted draft stop time (api 413c8e18)", () => {
  it("carries the run's stopped_at into the view", async () => {
    const { planView } = await import("./plan-state.ts");
    expect(
      planView({
        notSetUp: null,
        runId: "run_1",
        draft: ready(run("interrupted")),
        plans: noPlans,
        plan: null,
      }),
    ).toEqual({ kind: "interrupted", phase: "searching", stoppedAt: "2026-11-09T10:01:00Z" });
  });
});
