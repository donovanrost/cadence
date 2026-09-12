import type { InjectionKey } from "vue";
export type PlanAction = "submit-plan" | "approve-plan" | "reject-plan" | "execute-plan";
export type ResultPage<T> = { page: number; more: boolean; entries: T[] };
export type Version = { id: string; version: number; content_sha256: string; created_at: string };
export type Approval = {
  id: string;
  version: number;
  content_sha256: string;
  decision: "approved" | "rejected";
  reason: string;
  actor_id: string;
  actor_kind: "user" | "service";
  decided_at: string;
};
export type Opportunity = {
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
};
export type Execution = {
  id: string;
  version: number;
  snapshot_id: string;
  state: "pending" | "requesting" | "reserved" | "uncertain" | "rejected" | "failed";
  attempts: number;
  reservation_id: string | null;
};
export type Requirement = {
  id: string;
  version: number;
  satisfied: boolean;
  selected_count: number;
  eligible_count: number;
  hard_failure_count: number;
  search_failure_count: number;
  approval_mode: string;
};
export type Issue = {
  id: string;
  code: string;
  requirement_id: string | null;
  requirement_version: number | null;
  message: string;
  snapshot_ids: string[];
};
export const pageKeys = [
  "versions_page",
  "approvals_page",
  "opportunities_page",
  "execution_page",
  "requirements_page",
  "issues_page",
] as const;
export type PageKey = (typeof pageKeys)[number];
export type PlanDetail = {
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  plan: {
    id: string;
    version: number;
    current_version: number;
    content_sha256: string;
    lifecycle_state: string;
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
};
export interface PlanDetailPort {
  captured?: { actorId: string; guardNavigation?: (canLeave: () => boolean) => () => void };
  context: { organization_id: string; mission_id: string; plan_id?: string };
  execute: (action: PlanAction, input: Record<string, unknown>) => Promise<unknown>;
  refresh: () => Promise<unknown>;
}
export const PLAN_DETAIL_PORT: InjectionKey<PlanDetailPort> = Symbol("cadence.plan-detail-port");
export type OpsContactPlanShowProps = { detail: unknown; port?: PlanDetailPort };
