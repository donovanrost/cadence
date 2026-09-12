import type {
  ContactSchedule,
  ScheduleAction,
  ScheduleSearchResult,
} from "./OpsContactSchedule.contracts";
import type { ContactRecord } from "./OpsContactRecord.contracts";
import type { ReservationDetail, ReservationAction } from "./OpsContactDetail.contracts";
import {
  validScheduleSearch,
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
export type CapturedContact = {
  actorId: string;
  guardNavigation?: (guard: () => boolean) => () => void;
};
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
export type ContactOperation = {
  sequence: number;
  action: ContactAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  feedback?: (keyof typeof contactFeedback)[];
  receipt: null | {
    receiptId: string;
    completedAt: string;
    result: {
      contract_version: 1;
      actor_id: string;
      organization_id: string;
      mission_id: string;
      action: ContactAction;
      source: "returned" | "recorded" | "observed";
      value: Record<string, any>;
    };
  };
};
export type ContactPage = {
  kind: ContactKind;
  model: ContactSchedule | ContactRecord | ReservationDetail;
  actor_id: string;
  sequence: number;
  operation: ContactOperation | null;
  search: ScheduleSearchResult | null;
  consumed: string[];
  operation_reservation?: ReservationDetail | null;
};
const object = (v: any): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: unknown, max: number): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string =>
  text(v, 240) && !!v && v.split("").every((c) => c.charCodeAt(0) > 32 && c.charCodeAt(0) !== 127);
const seq = (v: unknown): v is number =>
  Number.isSafeInteger(v) && Number(v) >= 0 && Number(v) <= 1000000;
export const equalContact = (a: any, b: any): boolean =>
  a === b ||
  (!!a &&
    !!b &&
    typeof a === "object" &&
    typeof b === "object" &&
    Array.isArray(a) === Array.isArray(b) &&
    Object.keys(a).length === Object.keys(b).length &&
    Object.keys(a).every((k) => Object.hasOwn(b, k) && equalContact(a[k], b[k])));

function validInput(v: any, action: ContactAction, page: ContactPage) {
  if (!object(v)) return false;
  if (page.kind === "reservation") {
    const d = page.model as ReservationDetail;
    return (
      !!d.selected &&
      text(v.reason, 4096) &&
      !!v.reason.trim() &&
      equalContact(v, reservationDecision(d, v.reason))
    );
  }
  if (action === "reserve")
    return (
      Object.keys(v).length === 1 &&
      text(v.token, 8192) &&
      !!v.token &&
      !!page.search?.opportunities.some((o) => o.token === v.token)
    );
  if (action === "search") {
    return Object.keys(v).length === 2 && validScheduleSearch(v.contact_search, v.route_evidence);
  }
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
    Number.isSafeInteger(e.provider_revision) &&
    e.provider_revision > 0 &&
    ["pending", "confirmed", "active"].includes(e.lifecycle_state) &&
    text(e.provider_contact_ref, 240) &&
    !!e.provider_contact_ref
  );
}

export function admitContactOperation(value: unknown, page: ContactPage): ContactOperation | null {
  try {
    if (
      !object(value) ||
      !seq(value.sequence) ||
      value.sequence === 0 ||
      !(
        page.kind === "schedule"
          ? scheduleActions
          : page.kind === "reservation"
            ? reservationActions
            : []
      ).includes(value.action as never) ||
      !validInput(value.input, value.action, page)
    )
      return null;
    if (value.status === "rejected") {
      if (
        value.receipt !== null ||
        !Array.isArray(value.feedback) ||
        value.feedback.length < 1 ||
        value.feedback.length > 3 ||
        !value.feedback.every(
          (k: unknown) => typeof k === "string" && Object.hasOwn(contactFeedback, k),
        )
      )
        return null;
    } else if (!["completed", "unconfirmed"].includes(value.status)) return null;
    else if (value.receipt !== null) {
      const r = completedResult(value.receipt) as any;
      if (
        !object(r) ||
        r.contract_version !== 1 ||
        r.actor_id !== page.actor_id ||
        r.organization_id !== page.model.context.organization_id ||
        r.mission_id !== page.model.context.mission_id ||
        r.action !== value.action ||
        !["returned", "recorded", "observed"].includes(r.source)
      )
        return null;
      if (value.action === "search") {
        const route = r.value?.route;
        if (
          r.source !== "returned" ||
          value.status !== "completed" ||
          !route ||
          !equalContact(route.evidence, value.input.route_evidence) ||
          !admitSearch(r.value, page.model.context, value.input.contact_search, route)
        )
          return null;
      } else if (page.kind === "reservation") {
        if (
          r.source !== "returned" ||
          value.status !== "completed" ||
          !completedReceipt(
            { ...value.receipt, result: r.value },
            page.model as ReservationDetail,
            value.action,
          )
        )
          return null;
      } else {
        const booking = admitReceipt(
          r.value,
          value.action === "cancel" ? value.input.reservation_evidence.reservation_id : undefined,
        );
        if (!booking) return null;
        if (
          value.status === "completed" &&
          (value.action === "cancel"
            ? booking.lifecycleState !== "canceled"
            : !["pending", "confirmed", "active", "completed", "rejected", "canceled"].includes(
                booking.lifecycleState,
              ))
        )
          return null;
        if (
          value.status === "unconfirmed" &&
          (r.source !== "recorded" ||
            !["requesting", "canceling", "unknown", "failed", "rejected"].includes(
              booking.lifecycleState,
            ))
        )
          return null;
      }
    } else if (value.status === "completed") return null;
    return value as ContactOperation;
  } catch {
    return null;
  }
}

export function admitContactPage(
  kind: ContactKind,
  value: unknown,
  context?: ContactContext,
  actor?: string,
): ContactPage | null {
  try {
    const encoded = JSON.stringify(value);
    if (new TextEncoder().encode(encoded).length > 1048576) return null;
    const v = JSON.parse(encoded);
    if (
      !object(v) ||
      v.kind !== kind ||
      !id(v.actor_id) ||
      (actor !== undefined && actor !== v.actor_id) ||
      !seq(v.sequence)
    )
      return null;
    const model =
      kind === "schedule"
        ? admitContactSchedule(v.model, context)
        : kind === "record"
          ? admitContactRecord(v.model, context && { ...context, contact_id: context.resource_id })
          : admitReservation(
              v.model,
              context && { ...context, reservation_id: context.resource_id },
            );
    if (!model) return null;
    let search: ScheduleSearchResult | null = null;
    if (v.search !== null) {
      if (
        kind !== "schedule" ||
        !object(v.search) ||
        !object(v.search.search) ||
        !object(v.search.route)
      )
        return null;
      search = admitSearch(v.search, model.context, v.search.search as any, v.search.route as any);
      if (!search) return null;
    }
    if (
      !Array.isArray(v.consumed) ||
      v.consumed.length > 100 ||
      new Set(v.consumed).size !== v.consumed.length ||
      !v.consumed.every(
        (token: unknown) =>
          text(token, 8192) && !!search?.opportunities.some((o) => o.token === token),
      )
    )
      return null;
    let operation_reservation: ReservationDetail | null = null;
    if (v.operation_reservation != null) {
      const id = v.operation?.receipt?.result?.value?.providerReservationId;
      if (kind !== "schedule" || !["reserve", "cancel"].includes(v.operation?.action) || !id)
        return null;
      operation_reservation = admitReservation(v.operation_reservation, {
        ...model.context,
        reservation_id: id,
      });
      if (!operation_reservation) return null;
    }
    const page: ContactPage = { ...v, model, search, operation_reservation } as ContactPage;
    if (v.operation === null) return v.sequence === 0 ? page : null;
    const operation = admitContactOperation(v.operation, page);
    if (!operation || operation.sequence !== v.sequence) return null;
    if (
      operation.action === "search" &&
      operation.status === "completed" &&
      (!equalContact(search, operation.receipt?.result.value) || v.consumed.length !== 0)
    )
      return null;
    if (operation.action === "reserve" && !v.consumed.includes(operation.input.token)) return null;
    return { ...page, operation };
  } catch {
    return null;
  }
}
