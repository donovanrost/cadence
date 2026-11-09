import { describe, expect, it } from "vite-plus/test";
import type { Draft, PlanSummary } from "./api.ts";
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
      superseded,
      repair_of: null,
    });
    const why = { at: "2026-11-10T11:00:00Z", by: null, reason: "template_changed", changes: [] };
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
