import { collectionIds, type ExecutionDiagnostics, type DiagnosticRow } from "./contracts";
import { initialSelection } from "./selection";
import type { DiagnosticsPageState } from "./page-state";
export function diagnosticsPageFixture(): DiagnosticsPageState {
  return {
    model: diagnosticFixture(),
    selection: initialSelection(),
    runtime_query: {},
    publication_changed: false,
    sequence: 0,
  };
}
export const diagnosticContext = {
  organizationId: "org",
  missionId: "mission",
  resourceId: "dashboard",
};
export function diagnosticWarningFixture(): DiagnosticRow {
  return {
    kind: "plan_warning",
    id: "c".repeat(64),
    identity: "d".repeat(64),
    title: "stale_data",
    status: "warning",
    details: [
      { key: "warning_code", value: "stale_data" },
      { key: "scope", value: "placement" },
      { key: "placement_id", value: "placement/1" },
      { key: "frame_id", value: null },
      { key: "field_name", value: null },
      { key: "source_request_id", value: "request#1" },
      { key: "logical_source", value: "telemetry" },
    ],
  };
}
export function diagnosticFixture(): ExecutionDiagnostics {
  return {
    version: 2,
    organization_id: "org",
    mission_id: "mission",
    dashboard_id: "dashboard",
    name: "Power",
    document_version: 1,
    loaded_at: "2026-09-07T00:00:00Z",
    collections: collectionIds.map((id, i) => ({
      id,
      state: "ready",
      source: i < 5 ? "inspection" : "durable",
      limited: false,
      rows:
        id === "plan"
          ? [
              {
                kind: "plan",
                id: "a".repeat(64),
                identity: "dashboard",
                title: "Resolve plan",
                status: "ready",
                details: [
                  { key: "resolve_mode", value: "initial" },
                  { key: "requests", value: 1 },
                  { key: "executed_requests", value: 1 },
                  { key: "skipped_requests", value: 0 },
                  { key: "returned_frames", value: 1 },
                  { key: "warnings", value: 0 },
                  { key: "live_append_eligible", value: true },
                  { key: "snapshot", value: false },
                ],
              },
            ]
          : [],
    })),
  };
}
