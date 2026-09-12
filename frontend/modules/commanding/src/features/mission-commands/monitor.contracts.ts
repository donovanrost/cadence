export const commandStates = [
  "draft",
  "validated",
  "approval_pending",
  "approved",
  "rejected",
  "queued",
  "released",
  "canceled",
  "failed",
  "indeterminate",
  "release_pending",
  "in_flight",
] as const;
export type CommandState = (typeof commandStates)[number];
export type VerificationState =
  | "not_required"
  | "pending"
  | "satisfied"
  | "failed"
  | "timed_out"
  | null;
export type MonitorQuery = {
  status: string;
  target: string;
  query: string;
  page: string;
  focus_command_id?: string;
};
export type CommandObservation = {
  id: string;
  command_id: string | null;
  name: string;
  status: CommandState;
  target: string | null;
  requested_by: string;
  requested_at: string | null;
  occurred_at: string | null;
  request_state: CommandState;
  verification_state: VerificationState;
  queue: {
    id: string;
    state: "pending" | "release_pending" | "released" | "canceled";
    lane: string;
    enqueued_at: string | null;
  } | null;
  release: {
    id: string;
    queue_entry_id: string;
    state: "release_pending" | "released" | "release_failed" | "release_uncertain" | "canceled";
    verification_state: VerificationState;
    contact_id: string;
    attempted_at: string | null;
    released_at: string | null;
  } | null;
  verifiers: {
    id: string;
    release_attempt_id: string;
    name: string;
    state: "pending" | "satisfied" | "failed" | "timed_out" | "canceled";
    matched_at: string | null;
    timeout_at: string | null;
    matched_record_kind:
      | "telemetry_sample"
      | "transport_action_request"
      | "transport_capability_record"
      | null;
    matched_record_id: string | null;
  }[];
  verifier_total: number;
};
export type CommandMonitorModel = {
  version: 1;
  can_review: boolean;
  organization_id: string;
  mission_id: string;
  observed_at: string;
  query: MonitorQuery;
  status: "ready" | "empty";
  summary: {
    total_count: number;
    active_count: number;
    queued_count: number;
    release_pending_count: number;
    in_flight_count: number;
    released_count: number;
    failed_count: number;
    indeterminate_count: number;
  };
  total: number;
  pages: number;
  page_size: 25;
  targets: string[];
  targets_limited: boolean;
  rows: CommandObservation[];
  focus:
    | { status: "ready"; row: CommandObservation }
    | { status: "not_selected" | "not_found"; row: null };
};
