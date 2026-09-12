import type { Snapshot } from "@cadence/plugin-sdk/admission";
import type { PageSnapshotProtocol, RemoteQueryProtocol } from "../../shared/workflow-protocol";
import type { InjectionKey } from "vue";
export type PlanAction = "submit-plan" | "approve-plan" | "reject-plan" | "execute-plan";
export type ResultPage<T> = Snapshot<{ page: number; more: boolean; entries: T[] }>;
export type Version = Snapshot<{
  id: string;
  version: number;
  content_sha256: string;
  created_at: string;
}>;
export type Approval = Snapshot<{
  id: string;
  version: number;
  content_sha256: string;
  decision: "approved" | "rejected";
  reason: string;
  actor_id: string;
  actor_kind: "user" | "service";
  decided_at: string;
}>;
export type Opportunity = Snapshot<{
  id: string;
  disposition: "selected" | "locked" | "rejected";
  content_sha256: string;
  requirement_id: string;
  requirement_version: number;
  provider: string;
  station: string;
  starts_at: string;
  ends_at: string;
  expires_at: string;
  eligible: boolean;
  synthetic: boolean;
  availability: "available" | "limited" | "unavailable";
  route_key: string;
  provider_id: string | null;
  provider_version: number | null;
  transport_id: string | null;
  transport_version: number | null;
}>;
export type Execution = Snapshot<{
  id: string;
  version: number;
  snapshot_id: string;
  state: "pending" | "requesting" | "reserved" | "uncertain" | "rejected" | "failed";
  attempts: number;
  reservation_id: string | null;
}>;
export type Requirement = Snapshot<{
  id: string;
  version: number;
  satisfied: boolean;
  selected_count: number;
  eligible_count: number;
  hard_failure_count: number;
  search_failure_count: number;
  approval_mode: string;
}>;
export type Issue = Snapshot<{
  id: string;
  code: string;
  requirement_id: string | null;
  requirement_version: number | null;
  message: string;
  snapshot_ids: string[];
}>;
export const pageKeys = [
  "versions_page",
  "approvals_page",
  "opportunities_page",
  "execution_page",
  "requirements_page",
  "issues_page",
] as const;
export type PageKey = (typeof pageKeys)[number];
export type PlanDetail = Snapshot<{
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  plan: {
    id: string;
    version: number;
    current_version: number;
    content_sha256: string;
    lifecycle_state:
      | "draft"
      | "pending_approval"
      | "approved"
      | "executing"
      | "partially_reserved"
      | "reserved"
      | "failed"
      | "canceled"
      | "superseded";
    approved_version: number | null;
    reviewed_decision: Approval | null;
    rationale: string;
    created_at: string;
    selected_count: number;
    locked_count: number;
    rejected_count: number;
    coverage_satisfied: boolean;
    conflicts_clear: boolean;
    unsatisfied_clear: boolean;
    manual_review: boolean;
  };
  permissions: { operate: boolean; decide: boolean };
  query: Record<PageKey, number> & { contact_plan_id: string; version: number };
  versions: ResultPage<Version>;
  approvals: ResultPage<Approval>;
  opportunities: ResultPage<Opportunity>;
  execution: ResultPage<Execution>;
  requirements: ResultPage<Requirement>;
  issues: ResultPage<Issue>;
}>;
export type PlanEvidence = Snapshot<{
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  plan_id: string;
  plan_version: number;
  content_sha256: string;
}>;
export type PlanReference = {
  readonly contact_plan_id: string;
  readonly plan_evidence: PlanEvidence;
};
export type PlanInputs = {
  "submit-plan": PlanReference & {
    readonly submission: { readonly reason: string };
    readonly decision?: never;
  };
  "approve-plan": PlanReference & {
    readonly decision: { readonly reason: string };
    readonly submission?: never;
  };
  "reject-plan": PlanReference & {
    readonly decision: { readonly reason: string };
    readonly submission?: never;
  };
  "execute-plan": PlanReference & { readonly submission?: never; readonly decision?: never };
};
export type PlanRequest = { [A in PlanAction]: [action: A, input: PlanInputs[A]] }[PlanAction];
export type PlanPageRequest = {
  [A in PlanAction]: [action: A, input: { sequence: number; payload: PlanInputs[A] }];
}[PlanAction];
export type PlanResults = {
  "submit-plan": { contactPlanId: string; version: number; contentSha256: string };
  "approve-plan": { contactPlanId: string; version: number; contentSha256: string };
  "reject-plan": { contactPlanId: string; version: number; contentSha256: string };
  "execute-plan": {
    contactPlanId: string;
    executionItemCount: number;
    lifecycleState: "approved" | "executing" | "partially_reserved" | "reserved" | "failed";
  };
};
export type PlanReceipt<A extends PlanAction = PlanAction> = Snapshot<{
  receiptId: string;
  completedAt: string;
  result: PlanResults[A];
}>;
export type PlanDetailPort = {
  context: { organization_id: string; mission_id: string; plan_id?: string };
  refresh: () => Promise<unknown>;
} & (
  | (RemoteQueryProtocol & { execute: (...request: PlanRequest) => Promise<unknown> })
  | (PageSnapshotProtocol & { execute: (...request: PlanPageRequest) => Promise<unknown> })
);
export const PLAN_DETAIL_PORT: InjectionKey<PlanDetailPort> = Symbol("cadence.plan-detail-port");
export type OpsContactPlanShowProps = { detail: unknown; port?: PlanDetailPort };
