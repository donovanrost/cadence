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
