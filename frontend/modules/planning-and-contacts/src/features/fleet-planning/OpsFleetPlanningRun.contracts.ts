import type { Snapshot } from "@cadence/plugin-sdk/admission";
import type { InjectionKey } from "vue";
import type { FleetStartPolicy } from "./OpsFleetPlanningNew.contracts";
export type RunContext = Snapshot<{ organization_id: string; mission_id: string }>;
export type RunQuery = Snapshot<{
  requirements_page: number;
  decisions_page: number;
  resources_page: number;
  automation_page: number;
  commitments_page: number;
}>;
export type RunEvidence = Snapshot<
  RunContext & {
    contract_version: 1;
    run_id: string;
    lifecycle_state: string;
    phase: string;
    sha256: string;
  }
>;
export type RepairEvidence = Snapshot<
  RunContext & {
    contract_version: 1;
    run_id: string;
    run_sha256: string;
    plan_id: string;
    plan_version: number;
    plan_sha256: string;
    policy_id: string;
    policy_version: number;
    policy_sha256: string;
    sha256: string;
  }
>;
export type RunPage<T> = Snapshot<{ page: number; more: boolean; total?: number; entries: T[] }>;
export type CountedRunPage<T> = RunPage<T> & { readonly total: number };
export type RunRequirement = Snapshot<{
  id: string;
  requirement_id: string;
  version: number;
  content_sha256: string;
  spacecraft_id: string;
  earliest_start: string;
  latest_end: string;
  input_state: string;
  result_state: string;
  planning_run_id: string | null;
  priority: string;
}>;
export type RunDecision = Snapshot<{
  id: string;
  snapshot_id: string;
  spacecraft_id: string;
  starts_at: string;
  ends_at: string;
  disposition: string;
  score: number;
  rank: number | null;
  code: string | null;
  rationale: string | null;
  constraints_satisfied: boolean;
  failures: Array<string | null>;
}>;
export type RunResource = Snapshot<{
  key: string;
  peak_parallel: number;
  capacity: number;
  selected_count: number;
  over_capacity: boolean;
}>;
export type RunAutomation = Snapshot<{
  id: string;
  action: string;
  lifecycle_state: string;
  attempt_count: number;
  grant_id: string;
  service_identity_id: string;
  plan_id: string | null;
  plan_version: number | null;
  started_at: string;
  completed_at: string | null;
}>;
export type RunCommitment = Snapshot<{
  id: string;
  content_sha256: string;
  spacecraft_id: string;
  starts_at: string;
  ends_at: string;
}>;
export type RepairReview = Snapshot<{
  available: boolean;
  reason: string | null;
  evidence: RepairEvidence;
  policy: FleetStartPolicy & { max_repair_horizon_seconds: number; max_attempts: number };
  attempt: number;
  plan: { id: string; version: number; lifecycle_state: string };
  defaults: { horizon_start: string; horizon_end: string };
  commitments: CountedRunPage<RunCommitment>;
}>;
export type RunRepair = Snapshot<
  { available: false; reason: string; evidence?: null } | RepairReview
>;
export type FleetRunModel = Snapshot<{
  contract_version: 1;
  context: RunContext;
  query: RunQuery;
  id: string;
  lifecycle_state: string;
  phase: string;
  trigger_kind: string;
  algorithm: { key: string; version: number };
  horizon_start: string;
  horizon_end: string;
  inserted_at: string;
  started_at: string | null;
  completed_at: string | null;
  policy: FleetStartPolicy;
  evidence: RunEvidence;
  can_continue: boolean;
  candidate: {
    id: string;
    version: number;
    content_sha256: string;
    lifecycle_state: string;
    current_version: number;
  } | null;
  source: { run_id: string; plan_id: string; plan_version: number } | null;
  requirements: CountedRunPage<RunRequirement>;
  decisions: RunPage<RunDecision>;
  resources: CountedRunPage<RunResource>;
  automation: RunPage<RunAutomation>;
  repair: RunRepair;
  failure: { code: string | null } | null;
}>;
type ReceiptContext = {
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  fleetPlanningRunId: string;
};
export type FleetRunReceipt = Snapshot<
  ReceiptContext &
    (
      | {
          outcome: "continued";
          lifecycleState: "completed" | "partial" | "failed" | "canceled";
          phase: "finished";
          evidence: RunEvidence;
        }
      | {
          outcome: "repair_created";
          lifecycleState: "queued";
          phase: "queued";
          evidence: RepairEvidence;
        }
    )
>;
export type FleetRunInputs = {
  continue: { fleet_planning_run_id: string; evidence: RunEvidence };
  repair: {
    fleet_planning_run_id: string;
    evidence: RepairEvidence;
    repair: { horizon_start: string; horizon_end: string };
  };
};
export type FleetRunCommand = {
  [A in keyof FleetRunInputs]: [action: A, input: FleetRunInputs[A]];
}[keyof FleetRunInputs];
export type FleetRunPort = {
  context: RunContext;
  refresh(): Promise<unknown>;
  execute(...command: FleetRunCommand): Promise<unknown>;
};
export const FLEET_RUN_PORT: InjectionKey<FleetRunPort> = Symbol("cadence.fleet-run");
export type OpsFleetPlanningRunProps = { run: unknown; port?: FleetRunPort };
export type OpsFleetPlanningRunEmits = Record<string, never>;
