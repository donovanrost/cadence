export type VerificationState =
  | "not_required"
  | "pending"
  | "satisfied"
  | "failed"
  | "timed_out"
  | null;
export type HistoryQuery = {
  release: string;
  release_after: string;
  verifier_after: string;
  verifier: string;
};
export type RequestHeader = {
  id: string;
  command_id: string;
  name: string;
  target: string;
  target_name: string | null;
  model_revision_id: string;
  state:
    | "draft"
    | "validated"
    | "approval_pending"
    | "approved"
    | "rejected"
    | "queued"
    | "released"
    | "canceled";
  verification_state: VerificationState;
};
export type Release = {
  id: string;
  request_id: string;
  queue_entry_id: string;
  contact_id: string;
  path_id: string | null;
  binding_id: string | null;
  state: "release_pending" | "released" | "release_failed" | "release_uncertain" | "canceled";
  verification_state: VerificationState;
  attempted_at: string | null;
  released_at: string | null;
  encoded_size_bytes: number | null;
};
export type Verifier = {
  id: string;
  request_id: string;
  release_attempt_id: string;
  name: string;
  phase: "acceptance" | "start" | "completion" | "custom";
  severity: "info" | "warning" | "error" | "critical" | null;
  state: "pending" | "satisfied" | "failed" | "timed_out" | "canceled";
  failure_code: "timed_out" | "failure_criteria_matched" | null;
  matched_at: string | null;
  timeout_at: string | null;
  matched_record_kind:
    | "telemetry_sample"
    | "transport_action_request"
    | "transport_capability_record"
    | null;
  matched_record_id: string | null;
};
type ScopedRecord = { id: string; organization_id: string; mission_id: string };
export type TelemetryEvidence = ScopedRecord & {
  kind: "telemetry_sample";
  point_id: string;
  point_name: string;
  packet_id: string;
  evidence_id: string;
  spacecraft_id: string | null;
  quality_state: "good" | "suspect" | "bad";
  raw_value_json: string;
  engineering_value_json: string;
  generation_time: string | null;
  receipt_time: string;
};
type CorrelatedRecord = ScopedRecord & {
  request_id: string;
  release_attempt_id: string;
  contact_id: string;
  path_id: string;
  family_key: string;
};
export type TransportActionEvidence = CorrelatedRecord & {
  kind: "transport_action_request";
  signal_phase: "acceptance" | "start" | "completion" | "custom" | null;
  action_kind: string;
  requested_at: string;
};
export type TransportCapabilityEvidence = CorrelatedRecord & {
  kind: "transport_capability_record";
  event_kind: string;
  recorded_at: string;
};
export type MatchedRecord =
  | TelemetryEvidence
  | TransportActionEvidence
  | TransportCapabilityEvidence;
export type Ledger<T> = { entries: T[]; limit: 25; next_after: string | null };
export type HistoryModel = {
  version: 1;
  organization_id: string;
  mission_id: string;
  observed_at: string;
  request: RequestHeader;
  query: HistoryQuery;
  releases: Ledger<Release>;
  verifiers: Ledger<Verifier>;
  selection: { release: Release | null; verifier: Verifier | null };
  evidence:
    | { status: "not_selected" | "unmatched" | "unavailable"; record: null }
    | { status: "ready"; record: MatchedRecord };
};
