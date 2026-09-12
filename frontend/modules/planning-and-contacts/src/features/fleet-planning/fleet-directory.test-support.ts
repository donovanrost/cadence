import type { MutableFixture } from "../../../../../test-support/mutable-fixture";
import type { FleetDirectory } from "./OpsFleetPlanning.contracts";
export function directoryFixture(count = 1): MutableFixture<FleetDirectory> {
  return {
    contract_version: 1,
    context: { organization_id: "org-one", mission_id: "mission-one" },
    query: { page: 1, state: null },
    active_policy: {
      id: "policy-one",
      version: 1,
      content_sha256: "a".repeat(64),
      max_horizon_seconds: 86400,
    },
    runs: {
      page: 1,
      more: count === 25,
      entries: Array.from({ length: count }, (_, i) => ({
        id: `run-${i + 1}`,
        lifecycle_state: "queued",
        phase: "queued",
        trigger_kind: "manual",
        horizon_start: "2026-09-09T00:00:00Z",
        horizon_end: "2026-09-10T00:00:00Z",
        inserted_at: "2026-09-08T23:00:00Z",
        policy_id: "policy-one",
        policy_version: 1,
        requirement_count: 2,
        candidate_plan: null,
      })),
    },
  };
}
