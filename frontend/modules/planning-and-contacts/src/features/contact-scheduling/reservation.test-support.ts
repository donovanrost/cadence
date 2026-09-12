import type { ReservationDetail } from "./OpsContactDetail.contracts";
export function reservationFixture(): ReservationDetail {
  const selected = {
    id: "change-2",
    provider_revision: 2,
    proposal_hash: "a".repeat(64),
    lifecycle_state: "pending_approval",
    classification: "approval_required",
    recorded_at: "2026-09-08T12:00:00Z",
    from_provider_revision: 1,
    policy_version: 1,
    actionable: true,
    already_effective: false,
    deadline_at: null,
    decided_at: null,
    review_complete: true,
    fields: [
      {
        field: "starts_at",
        before: "2027-01-01T12:00:00Z",
        after: "2027-01-01T12:01:00Z",
        visible: true,
      },
    ],
  };
  return {
    contract_version: 1,
    context: { organization_id: "org-one", mission_id: "mission-one" },
    reservation: {
      id: "reservation-one",
      provider_revision: 2,
      lifecycle_state: "confirmed",
      provider_id: "provider-one",
      provider_version: 1,
      spacecraft_id: "craft-one",
      transport_id: "transport-one",
      transport_version: 1,
      plan_id: null,
      plan_version: null,
      requirement_id: null,
      requirement_version: null,
      starts_at: "2027-01-01T12:00:00Z",
      ends_at: "2027-01-01T12:10:00Z",
      scheduled_contact_id: "scheduled-one",
      last_reconciled_at: null,
    },
    permissions: { decide: true },
    query: {
      provider_reservation_id: "reservation-one",
      change_id: "change-2",
      before_revision: null,
      before_audit: null,
    },
    selected,
    values: [
      {
        field: "starts_at",
        requested: "2027-01-01T12:00:00Z",
        confirmed: "2027-01-01T12:01:00Z",
        accepted: "2027-01-01T12:00:00Z",
      },
    ],
    changes: { entries: [selected], next: null },
    audit: { entries: [], next: null },
  };
}
