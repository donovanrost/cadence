import type { MutableFixture } from "../../../../../test-support/mutable-fixture";
import { required } from "../../../../../test-support/required";
import type {
  FleetStartModel,
  FleetStartReview,
  FleetStartWindow,
} from "./OpsFleetPlanningNew.contracts";
export function startFixture(): MutableFixture<FleetStartModel> {
  return {
    contract_version: 1,
    context: { organization_id: "org-one", mission_id: "mission-one" },
    policy: {
      id: "policy-one",
      version: 2,
      content_sha256: "a".repeat(64),
      max_horizon_seconds: 86400,
      requirement_concurrency: 4,
      provider_search_concurrency: 2,
      max_contacts: 100,
      max_estimated_cost_micros: null,
      currency: null,
    },
    defaults: {
      horizon_start: "2026-09-09T04:00:00.000Z",
      horizon_end: "2026-09-09T08:00:00.000Z",
      include_recurring: false,
    },
  };
}
export function startReviewFixture(
  model = startFixture(),
  window = model.defaults,
  requirements_page = 1,
  templates_page = 1,
  count = 1,
): MutableFixture<FleetStartReview> {
  return {
    contract_version: 1,
    context: model.context,
    window: { ...window },
    policy: { ...required(model.policy) },
    evidence: {
      contract_version: 1,
      ...model.context,
      policy_id: required(model.policy).id,
      policy_version: required(model.policy).version,
      policy_sha256: required(model.policy).content_sha256,
      input_sha256: "b".repeat(64),
    },
    requirements: {
      page: requirements_page,
      total: count,
      more: count > requirements_page * 25,
      entries: Array.from({ length: count }, (_, i) => ({
        id: `requirement-${i + 1}`,
        version: 3,
        content_sha256: "c".repeat(64),
        spacecraft_id: "craft-one",
        earliest_start: window.horizon_start,
        latest_end: window.horizon_end,
        priority: "high" as const,
        success_measure: "minimum_duration" as const,
      })).slice((requirements_page - 1) * 25, requirements_page * 25),
    },
    templates: { page: templates_page, total: 0, more: false, entries: [] },
    occurrence_count: 0,
    eligible_occurrence_count: 0,
  };
}
export function startReceiptFixture(review: FleetStartReview) {
  return {
    contract_version: 1,
    organization_id: review.context.organization_id,
    mission_id: review.context.mission_id,
    fleetPlanningRunId: "run-one",
    lifecycleState: "queued",
    phase: "queued",
    requirementCount: review.requirements.total || 1,
    evidence: { ...review.evidence },
  };
}
export function startCompletion(result: unknown) {
  return { receiptId: "receipt-one", completedAt: "2026-09-09T04:00:00.000Z", result };
}
export type StartInput = {
  fleet_run: FleetStartWindow;
  requirements_page?: number;
  templates_page?: number;
};
