import type { MutableFixture } from "../../../../../test-support/mutable-fixture";
import { required } from "../../../../../test-support/required";
import type { FleetRunModel, FleetRunReceipt, RepairReview } from "./OpsFleetPlanningRun.contracts";
import { startFixture } from "./fleet-start.test-support";
export function runFixture(): MutableFixture<FleetRunModel> {
  const start = startFixture();
  return {
    contract_version: 1,
    context: start.context,
    query: {
      requirements_page: 1,
      decisions_page: 1,
      resources_page: 1,
      automation_page: 1,
      commitments_page: 1,
    },
    id: "run-one",
    lifecycle_state: "queued",
    phase: "queued",
    trigger_kind: "manual",
    algorithm: { key: "deterministic_bounded_greedy", version: 1 },
    horizon_start: start.defaults.horizon_start,
    horizon_end: start.defaults.horizon_end,
    inserted_at: start.defaults.horizon_start,
    started_at: null,
    completed_at: null,
    policy: required(start.policy),
    evidence: {
      contract_version: 1,
      ...start.context,
      run_id: "run-one",
      lifecycle_state: "queued",
      phase: "queued",
      sha256: "b".repeat(64),
    },
    can_continue: true,
    candidate: null,
    source: null,
    requirements: {
      page: 1,
      more: false,
      total: 1,
      entries: [
        {
          id: "ref-one",
          requirement_id: "requirement-one",
          version: 3,
          content_sha256: "c".repeat(64),
          spacecraft_id: "craft-one",
          earliest_start: start.defaults.horizon_start,
          latest_end: start.defaults.horizon_end,
          input_state: "pending",
          result_state: "pending",
          planning_run_id: null,
          priority: "high",
        },
      ],
    },
    decisions: { page: 1, more: false, entries: [] },
    resources: { page: 1, more: false, total: 0, entries: [] },
    automation: { page: 1, more: false, entries: [] },
    repair: { available: false, reason: "fleet_repair_source_unavailable" },
    failure: null,
  };
}
export function repairFixture(): MutableFixture<FleetRunModel> & {
  repair: MutableFixture<RepairReview>;
} {
  const m = runFixture();
  m.lifecycle_state = "completed";
  m.phase = "finished";
  m.can_continue = false;
  m.evidence.lifecycle_state = "completed";
  m.evidence.phase = "finished";
  m.completed_at = m.horizon_end;
  m.candidate = {
    id: "plan-one",
    version: 2,
    current_version: 2,
    content_sha256: "c".repeat(64),
    lifecycle_state: "partially_reserved",
  };
  m.repair = {
    available: true,
    reason: null,
    evidence: {
      contract_version: 1,
      ...m.context,
      run_id: m.id,
      run_sha256: m.evidence.sha256,
      plan_id: m.candidate.id,
      plan_version: m.candidate.version,
      plan_sha256: m.candidate.content_sha256,
      policy_id: m.policy.id,
      policy_version: m.policy.version,
      policy_sha256: m.policy.content_sha256,
      sha256: "d".repeat(64),
    },
    policy: { ...m.policy, max_repair_horizon_seconds: 14400, max_attempts: 2 },
    attempt: 1,
    plan: { id: "plan-one", version: 2, lifecycle_state: "partially_reserved" },
    defaults: { horizon_start: m.horizon_start, horizon_end: m.horizon_end },
    commitments: {
      page: 1,
      more: false,
      total: 1,
      entries: [
        {
          id: "snapshot-one",
          content_sha256: "e".repeat(64),
          spacecraft_id: "craft-one",
          starts_at: m.horizon_start,
          ends_at: m.horizon_end,
        },
      ],
    },
  };
  m.decisions.entries = [
    {
      id: "decision-one",
      snapshot_id: "snapshot-one",
      spacecraft_id: "craft-one",
      starts_at: m.horizon_start,
      ends_at: m.horizon_end,
      disposition: "selected",
      score: 1200,
      rank: 1,
      code: "selected",
      rationale: "Selected for the reviewed requirement.",
      constraints_satisfied: true,
      failures: [],
    },
  ];
  m.resources = {
    page: 1,
    more: false,
    total: 1,
    entries: [
      {
        key: "provider:station",
        capacity: 1,
        peak_parallel: 1,
        selected_count: 1,
        over_capacity: false,
      },
    ],
  };
  return { ...m, repair: m.repair };
}
export function runReceipt(m: FleetRunModel, action: "continue" | "repair"): FleetRunReceipt {
  const common = {
    contract_version: 1 as const,
    organization_id: m.context.organization_id,
    mission_id: m.context.mission_id,
    fleetPlanningRunId: action === "continue" ? m.id : "repair-one",
  };
  return action === "continue"
    ? {
        ...common,
        lifecycleState: "completed",
        phase: "finished",
        outcome: "continued",
        evidence: m.evidence,
      }
    : {
        ...common,
        lifecycleState: "queued",
        phase: "queued",
        outcome: "repair_created",
        evidence: required(m.repair.evidence),
      };
}
