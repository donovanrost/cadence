import type { Snapshot } from "@cadence/plugin-sdk/admission";
export type PageKey = "versions_page" | "runs_page" | "searches_page" | "opportunities_page";
export type Evidence = Snapshot<{
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  requirement_id: string;
  requirement_version: number;
  content_sha256: string;
}>;
export type PlanInput = Snapshot<{
  contact_requirement_id: string;
  requirement_evidence: Evidence;
}>;
export type CreatePlanInput = Snapshot<
  PlanInput & {
    planning_run_id: string;
    selected_snapshot_ids: string[];
  }
>;
export type ResultPage<T> = Snapshot<{ page: number; more: boolean; entries: T[] }>;
export type Run = Snapshot<{
  id: string;
  version: number;
  state: "running" | "completed" | "partial" | "failed";
  started_at: string;
}>;
export type Version = Snapshot<{
  id: string;
  version: number;
  content_sha256: string;
  created_at: string;
}>;
export type Search = Snapshot<{
  id: string;
  route_key: string;
  provider: string;
  outcome:
    | "succeeded_with_results"
    | "succeeded_without_results"
    | "not_ready"
    | "excluded_by_requirement"
    | "failed";
  opportunity_count: number;
  content_sha256: string;
}>;
export type Opportunity = Snapshot<{
  id: string;
  run_id: string;
  requirement_id: string;
  version: number;
  provider: string;
  station: string;
  starts_at: string;
  ends_at: string;
  expires_at: string;
  availability: "available" | "limited" | "unavailable";
  eligible: boolean;
  synthetic: boolean;
  content_sha256: string;
}>;
export type RequirementDetail = Snapshot<{
  contract_version: 1;
  context: { organization_id: string; mission_id: string; actor_id: string | null };
  requirement: {
    id: string;
    version: number;
    content_sha256: string;
    current_version: number;
    lifecycle_state: "active" | "closed" | "canceled";
    direction: "downlink" | "uplink" | "bidirectional" | "tracking";
    priority: "routine" | "high" | "critical";
    intent: string;
    outcome: string;
    rationale: string;
    earliest_start: string;
    latest_end: string;
  };
  query: Record<PageKey, number> & {
    contact_requirement_id: string;
    version: number;
    planning_run_id: string | null;
  };
  selected_run: Run | null;
  versions: ResultPage<Version>;
  runs: ResultPage<Run>;
  searches: ResultPage<Search>;
  opportunities: ResultPage<Opportunity>;
}>;
export type OpsContactRequirementShowProps = {
  detail: unknown;
  workflow?: {
    pending: boolean;
    busy?: boolean;
    result?: unknown;
    guardNavigation?: (guard: () => boolean) => () => void;
  };
};
export type OpsContactRequirementShowEmits = {
  plan: [payload: PlanInput];
  "create-plan": [payload: CreatePlanInput];
};
