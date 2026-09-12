import type { RequirementDetail } from "./OpsContactRequirementShow.contracts";
export function requirementDetailFixture(): RequirementDetail {
  return {
    contract_version: 1,
    context: { organization_id: "org-1", mission_id: "mission-1", actor_id: "actor-1" },
    requirement: {
      id: "requirement-1",
      version: 1,
      current_version: 1,
      content_sha256: "a".repeat(64),
      lifecycle_state: "active",
      direction: "downlink",
      priority: "high",
      intent: "payload_downlink",
      outcome: "At least 60 seconds",
      rationale: "Downlink the payload collection.",
      earliest_start: "2027-01-01T00:00:00Z",
      latest_end: "2027-01-01T02:00:00Z",
    },
    query: {
      contact_requirement_id: "requirement-1",
      version: 1,
      planning_run_id: "run-1",
      versions_page: 1,
      runs_page: 1,
      searches_page: 1,
      opportunities_page: 1,
    },
    selected_run: {
      id: "run-1",
      version: 1,
      state: "completed",
      started_at: "2027-01-01T00:00:00Z",
    },
    versions: {
      page: 1,
      more: false,
      entries: [
        {
          id: "version-1",
          version: 1,
          content_sha256: "a".repeat(64),
          created_at: "2027-01-01T00:00:00Z",
        },
      ],
    },
    runs: {
      page: 1,
      more: false,
      entries: [
        { id: "run-1", version: 1, state: "completed", started_at: "2027-01-01T00:00:00Z" },
      ],
    },
    searches: {
      page: 1,
      more: false,
      entries: [
        {
          id: "search-1",
          provider: "North ground network",
          route_key: "route-1",
          outcome: "succeeded_with_results",
          opportunity_count: 1,
          content_sha256: "b".repeat(64),
        },
      ],
    },
    opportunities: {
      page: 1,
      more: false,
      entries: [
        {
          id: "op-1",
          run_id: "run-1",
          requirement_id: "requirement-1",
          version: 1,
          provider: "North ground network",
          station: "Polar station",
          starts_at: "2027-01-01T00:30:00Z",
          ends_at: "2027-01-01T00:40:00Z",
          expires_at: "2027-01-01T01:00:00Z",
          availability: "available",
          eligible: true,
          synthetic: true,
          content_sha256: "c".repeat(64),
        },
      ],
    },
  };
}
