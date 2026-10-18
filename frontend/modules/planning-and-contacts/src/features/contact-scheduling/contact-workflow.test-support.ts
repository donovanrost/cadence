import { mutableFixture, type MutableFixture } from "../../../../../test-support/mutable-fixture";
import { required } from "../../../../../test-support/required";
import { fixtureRecord } from "../../../../../test-support/json-fixture";
import {
  admitContactOperation,
  isContactCommand,
  type ContactKind,
  type ContactPage,
  type ContactCompletion,
  type ContactAction,
} from "./contact-workflow";
import {
  scheduleFixture,
  searchFixture,
  receiptFixture,
  completion,
} from "./contact-schedule.test-support";
import { reservationFixture } from "./reservation.test-support";
import { contactRecordFixture } from "./contact-record.test-support";
import { decisionState } from "./reservation-detail";
export function contactPage(): MutableFixture<Extract<ContactPage, { kind: "schedule" }>>;
export function contactPage<K extends ContactKind>(
  kind: K,
): MutableFixture<Extract<ContactPage, { kind: K }>>;
export function contactPage(kind: ContactKind = "schedule"): MutableFixture<ContactPage> {
  const common = {
    actor_id: "operator-one",
    sequence: 0,
    operation: null,
    search: null,
    consumed: [],
  };
  if (kind === "schedule") return { ...common, kind, model: scheduleFixture() };
  if (kind === "reservation") return { ...common, kind, model: reservationFixture() };
  return { ...common, kind, model: contactRecordFixture() };
}
export function contactOperation<A extends ContactAction>(
  page: ContactPage,
  action: A,
  input: unknown,
): MutableFixture<Extract<ContactCompletion, { action: A }>>;
export function contactOperation(
  page: ContactPage,
  action: ContactAction,
  input: unknown,
): MutableFixture<ContactCompletion> {
  const envelope = fixtureRecord(input);
  const command = { sequence: envelope.sequence, action, input: envelope.payload };
  if (!isContactCommand(command, page)) throw Error("Invalid fixture command");
  let value: unknown;
  if (command.action === "search") {
    if (page.kind !== "schedule") throw Error("Missing fixture schedule");
    value = searchFixture(page.model, command.input.contact_search);
  } else if (command.action === "reserve" || command.action === "cancel") {
    value = receiptFixture(command.action === "cancel" ? "canceled" : "confirmed");
  } else {
    if (page.kind !== "reservation") throw Error("Missing fixture reservation");
    const selected = required(page.model.selected);
    value = {
      providerReservationId: page.model.reservation.id,
      providerReservationChangeId: selected.id,
      providerRevision: selected.provider_revision,
      proposalHash: selected.proposal_hash,
      lifecycleState: decisionState(command.action),
    };
  }
  const operation = required(
    admitContactOperation(
      {
        ...command,
        status: "completed",
        receipt: completion({
          contract_version: 1,
          actor_id: page.actor_id,
          ...page.model.context,
          action,
          source: "returned",
          value,
        }),
      },
      page,
    ),
  );
  if (operation.status !== "completed" || operation.action !== action)
    throw Error("Invalid fixture completion");
  return mutableFixture(operation);
}
export function completedContact(
  page: ContactPage,
  op: ContactCompletion,
): MutableFixture<ContactPage> {
  const next = mutableFixture(page);
  next.sequence = op.sequence;
  next.operation = mutableFixture(op);
  if (op.action === "search") {
    next.search = mutableFixture(op.receipt.result.value);
    next.consumed = [];
  } else if (op.action === "reserve" || op.action === "cancel") {
    if (next.kind !== "schedule") throw Error("Missing fixture schedule");
    const r = required(next.model.reservations.entries[0]);
    r.provider_revision = op.receipt.result.value.providerRevision;
    r.lifecycle_state = op.receipt.result.value.lifecycleState;
    if (op.action === "reserve") next.consumed.push(op.input.token);
  } else {
    if (next.kind !== "reservation") throw Error("Missing fixture reservation");
    required(next.model.selected).lifecycle_state = op.receipt.result.value.lifecycleState;
  }
  return next;
}
