import type { Snapshot } from "@cadence/plugin-sdk/admission";
import type { ReservationLifecycle } from "./OpsContactSchedule.contracts";
import type { PageSnapshotProtocol, RemoteQueryProtocol } from "../../shared/workflow-protocol";
import type { InjectionKey } from "vue";
export type ReservationAction =
  | "approve-provider-change"
  | "reject-provider-change"
  | "acknowledge-provider-change";
export type ChangeSummary = Snapshot<{
  id: string;
  provider_revision: number;
  proposal_hash: string;
  lifecycle_state:
    | "observed"
    | "pending_approval"
    | "policy_accepted"
    | "approved"
    | "rejected"
    | "acknowledgment_required"
    | "acknowledged"
    | "configuration_failure"
    | "superseded"
    | "apply_failed";
  classification:
    | "observation"
    | "policy_accept"
    | "approval_required"
    | "acknowledgment_required"
    | "configuration_failure";
  recorded_at: string;
}>;
export type ReviewedChange = Snapshot<
  ChangeSummary & {
    from_provider_revision: number;
    policy_version: number;
    actionable: boolean;
    already_effective: boolean;
    deadline_at: string | null;
    decided_at: string | null;
    review_complete: boolean;
    fields: { field: string; before: string; after: string; visible: boolean }[];
  }
>;
export type ReservationDetail = Snapshot<{
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  reservation: {
    id: string;
    provider_revision: number;
    lifecycle_state: ReservationLifecycle;
    provider_id: string;
    provider_version: number;
    spacecraft_id: string;
    transport_id: string | null;
    transport_version: number | null;
    plan_id: string | null;
    plan_version: number | null;
    requirement_id: string | null;
    requirement_version: number | null;
    starts_at: string;
    ends_at: string;
    scheduled_contact_id: string;
    last_reconciled_at: string | null;
  };
  permissions: { decide: boolean };
  query: {
    provider_reservation_id: string;
    change_id: string | null;
    before_revision: number | null;
    before_audit: string | null;
  };
  selected: ReviewedChange | null;
  values: { field: string; requested: string; confirmed: string; accepted: string }[];
  changes: { entries: ChangeSummary[]; next: number | null };
  audit: {
    entries: {
      id: string;
      action: string;
      outcome: string;
      recorded_at: string;
      change_id: string | null;
    }[];
    next: string | null;
  };
}>;
export type ReservationDecision = Snapshot<{
  provider_reservation_id: string;
  reason: string;
  change_evidence: {
    contract_version: 1;
    organization_id: string;
    mission_id: string;
    reservation_id: string;
    change_id: string;
    provider_revision: number;
    proposal_hash: string;
  };
}>;
export type ReservationStates = {
  "approve-provider-change": "approved";
  "reject-provider-change": "rejected";
  "acknowledge-provider-change": "acknowledged";
};
export type ReservationResult<A extends ReservationAction = ReservationAction> = Snapshot<{
  providerReservationId: string;
  providerReservationChangeId: string;
  providerRevision: number;
  proposalHash: string;
  lifecycleState: ReservationStates[A];
}>;
export type ReservationReceipt<A extends ReservationAction = ReservationAction> = Snapshot<{
  receiptId: string;
  completedAt: string;
  result: ReservationResult<A>;
}>;
export type ReservationRequest = [action: ReservationAction, input: ReservationDecision];
export type ReservationPageRequest = [
  action: ReservationAction,
  input: { sequence: number; payload: ReservationDecision },
];
export type ReservationPort = {
  context: { organization_id: string; mission_id: string; reservation_id?: string };
  refresh: () => Promise<unknown>;
} & (
  | (RemoteQueryProtocol & { execute: (...request: ReservationRequest) => Promise<unknown> })
  | (PageSnapshotProtocol & { execute: (...request: ReservationPageRequest) => Promise<unknown> })
);
export const RESERVATION_PORT: InjectionKey<ReservationPort> = Symbol("cadence.reservation-port");
export type OpsContactDetailProps = { detail: unknown; port?: ReservationPort };
