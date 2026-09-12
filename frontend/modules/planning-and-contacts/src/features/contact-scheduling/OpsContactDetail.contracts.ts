import type { CapturedContact } from "./contact-workflow";
import type { InjectionKey } from "vue";
export type ReservationAction =
  | "approve-provider-change"
  | "reject-provider-change"
  | "acknowledge-provider-change";
export type ChangeSummary = {
  id: string;
  provider_revision: number;
  proposal_hash: string;
  lifecycle_state: string;
  classification: string;
  recorded_at: string;
};
export type ReviewedChange = ChangeSummary & {
  from_provider_revision: number;
  policy_version: number;
  actionable: boolean;
  already_effective: boolean;
  deadline_at: string | null;
  decided_at: string | null;
  review_complete: boolean;
  fields: { field: string; before: string; after: string; visible: boolean }[];
};
export type ReservationDetail = {
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  reservation: {
    id: string;
    provider_revision: number;
    lifecycle_state: string;
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
};
export interface ReservationPort {
  captured?: CapturedContact;
  context: { organization_id: string; mission_id: string; reservation_id?: string };
  execute: (action: ReservationAction, input: Record<string, unknown>) => Promise<unknown>;
  refresh: () => Promise<unknown>;
}
export const RESERVATION_PORT: InjectionKey<ReservationPort> = Symbol("cadence.reservation-port");
export type OpsContactDetailProps = { detail: unknown; port?: ReservationPort };
