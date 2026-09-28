import type { CommandMonitorModel, CommandObservation } from "./monitor.contracts";
export const monitorContext = { organizationId: "org-1", missionId: "mission-1" };
export function commandObservation(id = "request-a"): CommandObservation {
  return {
    id,
    command_id: "CMD-NOOP",
    name: "NOOP",
    status: "in_flight",
    target: "endpoint-a",
    target_name: "Aurora",
    requested_by: "Operator",
    requested_at: "2026-09-08T12:00:00.123456Z",
    occurred_at: "2026-09-08T12:03:00.654321Z",
    request_state: "released",
    verification_state: "pending",
    queue: {
      id: `queue-${id}`,
      state: "released",
      lane: "endpoint-a",
      enqueued_at: "2026-09-08T12:01:00Z",
    },
    release: {
      id: `release-${id}`,
      queue_entry_id: `queue-${id}`,
      state: "released",
      verification_state: "pending",
      contact_id: "contact-a",
      attempted_at: "2026-09-08T12:02:00Z",
      released_at: "2026-09-08T12:03:00Z",
    },
    verifiers: [
      {
        id: `verifier-${id}`,
        release_attempt_id: `release-${id}`,
        name: "Completion",
        state: "pending",
        matched_at: null,
        timeout_at: "2026-09-08T12:04:00Z",
        matched_record_kind: null,
        matched_record_id: null,
      },
    ],
    verifier_total: 1,
  };
}
export function monitorFixture(): CommandMonitorModel {
  return {
    version: 1,
    can_review: true,
    organization_id: "org-1",
    mission_id: "mission-1",
    observed_at: "2026-09-08T12:03:30.123456Z",
    query: { status: "all", target: "all", query: "", page: "1" },
    status: "ready",
    summary: {
      total_count: 1,
      active_count: 1,
      queued_count: 0,
      release_pending_count: 0,
      in_flight_count: 1,
      released_count: 0,
      failed_count: 0,
      indeterminate_count: 0,
    },
    total: 1,
    pages: 1,
    page_size: 25,
    targets: [{ id: "endpoint-a", name: "Aurora" }],
    targets_limited: false,
    rows: [commandObservation()],
    focus: { status: "not_selected", row: null },
  };
}
