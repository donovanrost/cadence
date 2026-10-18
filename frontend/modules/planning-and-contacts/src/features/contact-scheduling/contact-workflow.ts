import { record as object, oneOf, arrayOf, type Snapshot } from "@cadence/plugin-sdk/admission";
import type {
  ContactSchedule,
  ScheduleAction,
  ScheduleSearchResult,
  ScheduleInputs,
  ScheduleRequest,
  SchedulePageRequest,
  ScheduleReceipt,
} from "./OpsContactSchedule.contracts";
import type { ContactRecord } from "./OpsContactRecord.contracts";
import type {
  ReservationDetail,
  ReservationAction,
  ReservationDecision,
  ReservationResult,
  ReservationRequest,
  ReservationPageRequest,
} from "./OpsContactDetail.contracts";
import {
  validScheduleSearch,
  validScheduleRoute,
  validRouteEvidence,
  admitContactSchedule,
  admitSearch,
  admitReceipt,
  completedResult,
} from "./contact-schedule";
import { admitContactRecord } from "./contact-record";
import { admitReservation, completedReceipt, reservationDecision } from "./reservation-detail";

export type ContactKind = "schedule" | "record" | "reservation";
export type ContactAction = ScheduleAction | ReservationAction;
export type ContactContext = { organization_id: string; mission_id: string; resource_id?: string };
export const scheduleActions = ["search", "reserve", "cancel"] as const;
export const reservationActions = [
  "approve-provider-change",
  "reject-provider-change",
  "acknowledge-provider-change",
] as const;
export const contactFeedback = {
  forbidden: "Your current authority does not permit this operation.",
  review_changed:
    "This operation could not be applied to the reviewed evidence. Refresh before continuing.",
  search_unavailable:
    "Provider opportunities could not be read. Refresh the route and search again.",
};
export type ContactInputs = ScheduleInputs & { [A in ReservationAction]: ReservationDecision };
export type ContactRequest = ScheduleRequest | ReservationRequest;
export type ContactPageRequest = SchedulePageRequest | ReservationPageRequest;
export type ContactCommand = {
  [A in ContactAction]: Snapshot<{ sequence: number; action: A; input: ContactInputs[A] }>;
}[ContactAction];
export type ContactResults = {
  search: ScheduleSearchResult;
  reserve: ScheduleReceipt & {
    lifecycleState: "pending" | "confirmed" | "active" | "completed" | "rejected" | "canceled";
  };
  cancel: ScheduleReceipt & { lifecycleState: "canceled" };
} & { [A in ReservationAction]: ReservationResult<A> };
type Source = "returned" | "recorded" | "observed";
type ContactReceipt<A extends ContactAction, V, S extends Source> = Snapshot<{
  receiptId: string;
  completedAt: string;
  result: {
    contract_version: 1;
    actor_id: string;
    organization_id: string;
    mission_id: string;
    action: A;
    source: S;
    value: V;
  };
}>;
type RecordedBooking = ScheduleReceipt & {
  lifecycleState: "requesting" | "canceling" | "unknown" | "failed" | "rejected";
};
export type ContactOperation = {
  [A in ContactAction]: Snapshot<{ sequence: number; action: A; input: ContactInputs[A] }> &
    (
      | {
          readonly status: "completed";
          readonly receipt: ContactReceipt<
            A,
            ContactResults[A],
            A extends "reserve" | "cancel" ? Source : "returned"
          >;
        }
      | {
          readonly status: "rejected";
          readonly receipt: null;
          readonly feedback: readonly (keyof typeof contactFeedback)[];
        }
      | {
          readonly status: "unconfirmed";
          readonly receipt: A extends "reserve" | "cancel"
            ? ContactReceipt<A, RecordedBooking, "recorded"> | null
            : null;
        }
    );
}[ContactAction];
export type ContactCompletion = Extract<ContactOperation, { status: "completed" }>;
type ContactModel =
  | { readonly kind: "schedule"; readonly model: ContactSchedule }
  | { readonly kind: "record"; readonly model: ContactRecord }
  | { readonly kind: "reservation"; readonly model: ReservationDetail };
type ContactReview = ContactModel & {
  readonly actor_id: string;
  readonly search: ScheduleSearchResult | null;
};
export type ContactPage = ContactReview &
  Snapshot<{
    sequence: number;
    operation: ContactOperation | null;
    consumed: string[];
    operation_reservation?: ReservationDetail | null;
  }>;
const text = (v: unknown, max: number): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string =>
  text(v, 240) && !!v && v.split("").every((c) => c.charCodeAt(0) > 32 && c.charCodeAt(0) !== 127);
const seq = (v: unknown): v is number =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= 1000000;
export function equalContact(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (
    !a ||
    !b ||
    typeof a !== "object" ||
    typeof b !== "object" ||
    Array.isArray(a) !== Array.isArray(b)
  )
    return false;
  const left: Record<string, unknown> = Object.fromEntries(Object.entries(a));
  const right: Record<string, unknown> = Object.fromEntries(Object.entries(b));
  return (
    Object.keys(left).length === Object.keys(right).length &&
    Object.keys(left).every((k) => Object.hasOwn(right, k) && equalContact(left[k], right[k]))
  );
}

export function isContactCommand(
  value: unknown,
  page: ContactReview,
): value is ContactCommand & Record<string, unknown> {
  if (!object(value) || !seq(value.sequence) || value.sequence === 0 || !object(value.input))
    return false;
  const v = value.input;
  if (page.kind === "reservation") {
    return (
      oneOf(reservationActions, value.action) &&
      !!page.model.selected &&
      text(v.reason, 4096) &&
      !!v.reason.trim() &&
      equalContact(v, reservationDecision(page.model, v.reason))
    );
  }
  if (page.kind !== "schedule" || !oneOf(scheduleActions, value.action)) return false;
  if (value.action === "reserve")
    return (
      Object.keys(v).length === 1 &&
      text(v.token, 8192) &&
      !!v.token &&
      !!page.search?.opportunities.some((o) => o.token === v.token)
    );
  if (value.action === "search")
    return (
      Object.keys(v).length === 2 &&
      validRouteEvidence(v.route_evidence) &&
      validScheduleSearch(v.contact_search, v.route_evidence)
    );
  const e = v.reservation_evidence,
    c = page.model.context;
  return (
    Object.keys(v).length === 1 &&
    object(e) &&
    Object.keys(e).length === 7 &&
    e.contract_version === 1 &&
    e.organization_id === c.organization_id &&
    e.mission_id === c.mission_id &&
    id(e.reservation_id) &&
    typeof e.provider_revision === "number" &&
    Number.isSafeInteger(e.provider_revision) &&
    e.provider_revision > 0 &&
    oneOf(["pending", "confirmed", "active"], e.lifecycle_state) &&
    text(e.provider_contact_ref, 240) &&
    !!e.provider_contact_ref
  );
}
const feedbackCode = (v: unknown): v is keyof typeof contactFeedback =>
  typeof v === "string" && Object.hasOwn(contactFeedback, v);
function validOperation(value: unknown, page: ContactReview): value is ContactOperation {
  if (!isContactCommand(value, page)) return false;
  if (value.status === "rejected")
    return (
      value.receipt === null &&
      arrayOf(value.feedback, feedbackCode) &&
      value.feedback.length >= 1 &&
      value.feedback.length <= 3
    );
  if (!oneOf(["completed", "unconfirmed"], value.status)) return false;
  if (value.receipt === null) return value.status === "unconfirmed";
  if (!object(value.receipt)) return false;
  const r = completedResult(value.receipt);
  if (
    !object(r) ||
    r.contract_version !== 1 ||
    r.actor_id !== page.actor_id ||
    r.organization_id !== page.model.context.organization_id ||
    r.mission_id !== page.model.context.mission_id ||
    r.action !== value.action ||
    !oneOf(["returned", "recorded", "observed"], r.source)
  )
    return false;
  if (value.action === "search") {
    return (
      r.source === "returned" &&
      value.status === "completed" &&
      object(r.value) &&
      validScheduleRoute(r.value.route) &&
      equalContact(r.value.route.evidence, value.input.route_evidence) &&
      !!admitSearch(r.value, page.model.context, value.input.contact_search, r.value.route)
    );
  }
  if (value.action === "reserve" || value.action === "cancel") {
    const booking = admitReceipt(
      r.value,
      value.action === "cancel" ? value.input.reservation_evidence.reservation_id : undefined,
    );
    if (!booking) return false;
    return value.status === "completed"
      ? value.action === "cancel"
        ? booking.lifecycleState === "canceled"
        : oneOf(
            ["pending", "confirmed", "active", "completed", "rejected", "canceled"],
            booking.lifecycleState,
          )
      : r.source === "recorded" &&
          oneOf(
            ["requesting", "canceling", "unknown", "failed", "rejected"],
            booking.lifecycleState,
          );
  }
  return (
    page.kind === "reservation" &&
    r.source === "returned" &&
    value.status === "completed" &&
    completedReceipt({ ...value.receipt, result: r.value }, page.model, value.action)
  );
}
export function admitContactOperation(
  value: unknown,
  page: ContactReview,
): ContactOperation | null {
  try {
    const encoded = JSON.stringify(value);
    if (new TextEncoder().encode(encoded).length > 1048576) return null;
    const snapshot: unknown = JSON.parse(encoded);
    return validOperation(snapshot, page) ? snapshot : null;
  } catch {
    return null;
  }
}
function admitModel(
  kind: ContactKind,
  value: unknown,
  context?: ContactContext,
): ContactModel | null {
  if (kind === "schedule") {
    const model = admitContactSchedule(value, context);
    return model && { kind, model };
  }
  if (kind === "record") {
    const model = admitContactRecord(
      value,
      context && {
        ...context,
        ...(context.resource_id === undefined ? {} : { contact_id: context.resource_id }),
      },
    );
    return model && { kind, model };
  }
  const model = admitReservation(
    value,
    context && {
      ...context,
      ...(context.resource_id === undefined ? {} : { reservation_id: context.resource_id }),
    },
  );
  return model && { kind, model };
}
export function admitContactPage<K extends ContactKind>(
  kind: K,
  value: unknown,
  context?: ContactContext,
  actor?: string,
): Extract<ContactPage, { kind: K }> | null;
export function admitContactPage(
  kind: ContactKind,
  value: unknown,
  context?: ContactContext,
  actor?: string,
): ContactPage | null {
  try {
    const encoded = JSON.stringify(value);
    if (new TextEncoder().encode(encoded).length > 1048576) return null;
    const v: unknown = JSON.parse(encoded);
    if (
      !object(v) ||
      v.kind !== kind ||
      !id(v.actor_id) ||
      (actor !== undefined && actor !== v.actor_id) ||
      !seq(v.sequence)
    )
      return null;
    const reviewed = admitModel(kind, v.model, context);
    if (!reviewed) return null;
    let search: ScheduleSearchResult | null = null;
    if (v.search !== null) {
      if (
        kind !== "schedule" ||
        !object(v.search) ||
        !validScheduleRoute(v.search.route) ||
        !validScheduleSearch(v.search.search, v.search.route.evidence)
      )
        return null;
      search = admitSearch(v.search, reviewed.model.context, v.search.search, v.search.route);
      if (!search) return null;
    }
    if (
      !arrayOf(
        v.consumed,
        (token): token is string =>
          text(token, 8192) && !!search?.opportunities.some((o) => o.token === token),
      ) ||
      v.consumed.length > 100 ||
      new Set(v.consumed).size !== v.consumed.length
    )
      return null;
    const review: ContactReview = { ...reviewed, actor_id: v.actor_id, search };
    const operation = v.operation === null ? null : admitContactOperation(v.operation, review);
    if (v.operation !== null && (!operation || operation.sequence !== v.sequence)) return null;
    if (!operation && v.sequence !== 0) return null;
    let operation_reservation: ReservationDetail | null = null;
    if (v.operation_reservation != null) {
      if (
        kind !== "schedule" ||
        !operation ||
        (operation.action !== "reserve" && operation.action !== "cancel") ||
        !operation.receipt
      )
        return null;
      operation_reservation = admitReservation(v.operation_reservation, {
        ...reviewed.model.context,
        reservation_id: operation.receipt.result.value.providerReservationId,
      });
      if (!operation_reservation) return null;
    }
    if (
      operation?.action === "search" &&
      operation.status === "completed" &&
      (!equalContact(search, operation.receipt.result.value) || v.consumed.length !== 0)
    )
      return null;
    if (operation?.action === "reserve" && !v.consumed.includes(operation.input.token)) return null;
    return {
      ...review,
      sequence: v.sequence,
      operation,
      consumed: v.consumed,
      operation_reservation,
    };
  } catch {
    return null;
  }
}
export function contactPageRequest(request: ContactRequest, sequence: number): ContactPageRequest {
  switch (request[0]) {
    case "search":
      return [request[0], { sequence, payload: request[1] }];
    case "reserve":
      return [request[0], { sequence, payload: request[1] }];
    case "cancel":
      return [request[0], { sequence, payload: request[1] }];
    case "acknowledge-provider-change":
    case "approve-provider-change":
    case "reject-provider-change":
      return [request[0], { sequence, payload: request[1] }];
  }
}
