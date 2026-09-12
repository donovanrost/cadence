import type { ContactKind, ContactPage, ContactOperation, ContactAction } from "./contact-workflow";
import {
  scheduleFixture,
  searchFixture,
  receiptFixture,
  completion,
} from "./contact-schedule.test-support";
import { reservationFixture } from "./reservation.test-support";
import { contactRecordFixture } from "./contact-record.test-support";
import type { ContactSchedule } from "./OpsContactSchedule.contracts";
import type { ReservationDetail } from "./OpsContactDetail.contracts";
import { decisionState } from "./reservation-detail";
export function contactPage(kind: ContactKind = "schedule"): ContactPage {
  return {
    kind,
    actor_id: "operator-one",
    sequence: 0,
    operation: null,
    search: null,
    consumed: [],
    model:
      kind === "schedule"
        ? scheduleFixture()
        : kind === "reservation"
          ? reservationFixture()
          : contactRecordFixture(),
  };
}
export function contactOperation(
  page: ContactPage,
  action: ContactAction,
  input: any,
): ContactOperation {
  const selected = (page.model as ReservationDetail).selected;
  const value =
    action === "search"
      ? searchFixture(page.model as ContactSchedule, input.payload.contact_search)
      : action === "reserve" || action === "cancel"
        ? receiptFixture(action === "cancel" ? "canceled" : "confirmed")
        : {
            providerReservationId: (page.model as ReservationDetail).reservation.id,
            providerReservationChangeId: selected!.id,
            providerRevision: selected!.provider_revision,
            proposalHash: selected!.proposal_hash,
            lifecycleState: decisionState(action),
          };
  return {
    sequence: input.sequence,
    action,
    input: structuredClone(input.payload),
    status: "completed",
    receipt: completion({
      contract_version: 1,
      actor_id: page.actor_id,
      ...page.model.context,
      action,
      source: "returned",
      value,
    }) as ContactOperation["receipt"],
  };
}
export function completedContact(page: ContactPage, op: ContactOperation): ContactPage {
  const next = structuredClone(page);
  next.sequence = op.sequence;
  next.operation = structuredClone(op);
  if (op.action === "search") {
    next.search = op.receipt!.result.value as any;
    next.consumed = [];
  } else if (op.action === "reserve" || op.action === "cancel") {
    const r = (next.model as ContactSchedule).reservations.entries[0]!;
    r.provider_revision = op.receipt!.result.value.providerRevision;
    r.lifecycle_state = op.receipt!.result.value.lifecycleState;
    if (op.action === "reserve") next.consumed.push(op.input.token);
  } else
    (next.model as ReservationDetail).selected!.lifecycle_state =
      op.receipt!.result.value.lifecycleState;
  return next;
}
