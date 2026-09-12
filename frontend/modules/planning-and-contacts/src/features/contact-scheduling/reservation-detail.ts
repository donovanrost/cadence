import type {
  ReservationAction,
  ReservationDetail,
  ReservationPort,
} from "./OpsContactDetail.contracts";
const record = (v: unknown): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: unknown, max = 512): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string => text(v, 240) && !!v && !/[\x00-\x20\x7f]/.test(v);
const version = (v: unknown): v is number =>
  Number.isSafeInteger(v) && (v as number) > 0 && (v as number) <= 2147483647;
const hash = (v: unknown) => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
const time = (v: unknown) =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const optional = (v: unknown, check: (v: any) => boolean) => v === null || check(v);
const states = [
  "observed",
  "pending_approval",
  "policy_accepted",
  "approved",
  "rejected",
  "acknowledgment_required",
  "acknowledged",
  "configuration_failure",
  "superseded",
  "apply_failed",
];
const summary = (v: any) =>
  record(v) &&
  id(v.id) &&
  version(v.provider_revision) &&
  hash(v.proposal_hash) &&
  states.includes(v.lifecycle_state) &&
  [
    "observation",
    "policy_accept",
    "approval_required",
    "acknowledgment_required",
    "configuration_failure",
  ].includes(v.classification) &&
  time(v.recorded_at);
const rows = (v: unknown, check: (v: any) => boolean, max = 25): v is any[] =>
  Array.isArray(v) && v.length <= max && v.every(check);
const unique = (v: any[]) => new Set(v.map((r) => r.id)).size === v.length;
export function admitReservation(
  value: unknown,
  context?: ReservationPort["context"],
): ReservationDetail | null {
  try {
    if (
      !record(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 262144 ||
      value.contract_version !== 1
    )
      return null;
    const { context: c, reservation: r, selected: s, query: q, changes, audit } = value;
    if (!record(c) || !id(c.organization_id) || !id(c.mission_id) || !record(r) || !id(r.id))
      return null;
    if (
      context &&
      (c.organization_id !== context.organization_id ||
        c.mission_id !== context.mission_id ||
        (context.reservation_id !== undefined && r.id !== context.reservation_id))
    )
      return null;
    if (
      !version(r.provider_revision) ||
      !id(r.provider_id) ||
      !version(r.provider_version) ||
      !id(r.spacecraft_id) ||
      !id(r.scheduled_contact_id) ||
      !time(r.starts_at) ||
      !time(r.ends_at) ||
      Date.parse(r.starts_at) >= Date.parse(r.ends_at) ||
      !optional(r.last_reconciled_at, time)
    )
      return null;
    if (
      ![
        "requesting",
        "pending",
        "confirmed",
        "active",
        "completed",
        "unknown",
        "rejected",
        "canceling",
        "canceled",
        "failed",
      ].includes(r.lifecycle_state)
    )
      return null;
    for (const key of ["transport", "plan", "requirement"])
      if (
        !optional(r[`${key}_id`], id) ||
        !optional(r[`${key}_version`], version) ||
        (r[`${key}_id`] === null) !== (r[`${key}_version`] === null)
      )
        return null;
    if (
      !record(value.permissions) ||
      typeof value.permissions.decide !== "boolean" ||
      !record(q) ||
      q.provider_reservation_id !== r.id ||
      !optional(q.change_id, id) ||
      !optional(q.before_revision, version) ||
      !optional(q.before_audit, id)
    )
      return null;
    if (
      !rows(
        value.values,
        (v) =>
          record(v) && id(v.field) && text(v.requested) && text(v.confirmed) && text(v.accepted),
        32,
      ) ||
      new Set(value.values.map((v) => v.field)).size !== value.values.length
    )
      return null;
    if (
      s !== null &&
      (!summary(s) ||
        s.id !== q.change_id ||
        s.provider_revision > r.provider_revision ||
        !Number.isSafeInteger(s.from_provider_revision) ||
        s.from_provider_revision < 0 ||
        s.from_provider_revision >= s.provider_revision ||
        !version(s.policy_version) ||
        ![s.actionable, s.already_effective, s.review_complete].every(
          (v) => typeof v === "boolean",
        ) ||
        !optional(s.deadline_at, time) ||
        !optional(s.decided_at, time) ||
        !rows(
          s.fields,
          (f) =>
            record(f) &&
            id(f.field) &&
            text(f.before) &&
            text(f.after) &&
            typeof f.visible === "boolean",
          32,
        ) ||
        s.review_complete !== s.fields.every((f: any) => f.visible))
    )
      return null;
    if (s === null && q.change_id !== null) return null;
    if (
      !record(changes) ||
      !rows(changes.entries, summary) ||
      !unique(changes.entries) ||
      !optional(changes.next, version)
    )
      return null;
    if (
      changes.entries.some(
        (v: any, i: number) =>
          v.provider_revision > r.provider_revision ||
          (q.before_revision !== null && v.provider_revision >= q.before_revision) ||
          (i > 0 && changes.entries[i - 1].provider_revision <= v.provider_revision),
      )
    )
      return null;
    if (
      changes.next !== null &&
      (changes.entries.length !== 25 || changes.next !== changes.entries.at(-1).provider_revision)
    )
      return null;
    if (
      !record(audit) ||
      !rows(
        audit.entries,
        (v) =>
          record(v) &&
          id(v.id) &&
          text(v.action, 120) &&
          text(v.outcome, 120) &&
          time(v.recorded_at) &&
          optional(v.change_id, id),
      ) ||
      !unique(audit.entries) ||
      !optional(audit.next, id)
    )
      return null;
    if (
      audit.next !== null &&
      (audit.entries.length !== 25 || audit.next !== audit.entries.at(-1).id)
    )
      return null;
    return value as ReservationDetail;
  } catch {
    return null;
  }
}
export const reviewIdentity = (d: ReservationDetail) =>
  JSON.stringify([d.context, d.reservation.id, d.selected?.id, d.selected?.proposal_hash]);
export function canDecide(d: ReservationDetail, action: ReservationAction, now = Date.now()) {
  const s = d.selected;
  if (!s || !d.permissions.decide || s.provider_revision !== d.reservation.provider_revision)
    return false;
  if (action === "acknowledge-provider-change")
    return s.lifecycle_state === "acknowledgment_required" && s.already_effective;
  if (
    !s.review_complete ||
    s.lifecycle_state !== "pending_approval" ||
    !s.actionable ||
    s.already_effective
  )
    return false;
  return (
    action === "reject-provider-change" || s.deadline_at === null || Date.parse(s.deadline_at) > now
  );
}
export function reservationDecision(d: ReservationDetail, reason: string) {
  const s = d.selected!;
  return {
    provider_reservation_id: d.reservation.id,
    reason: reason.trim(),
    change_evidence: {
      contract_version: 1,
      ...d.context,
      reservation_id: d.reservation.id,
      change_id: s.id,
      provider_revision: s.provider_revision,
      proposal_hash: s.proposal_hash,
    },
  };
}
export const decisionState = (action: ReservationAction) =>
  action === "approve-provider-change"
    ? "approved"
    : action === "reject-provider-change"
      ? "rejected"
      : "acknowledged";
export function completedReceipt(receipt: any, d: ReservationDetail, action: ReservationAction) {
  const v = receipt?.result;
  return (
    id(receipt?.receiptId) &&
    time(receipt?.completedAt) &&
    v?.providerReservationId === d.reservation.id &&
    v?.providerReservationChangeId === d.selected?.id &&
    v?.providerRevision === d.selected?.provider_revision &&
    v?.proposalHash === d.selected?.proposal_hash &&
    v?.lifecycleState === decisionState(action)
  );
}
export function reservationHref(
  d: ReservationDetail,
  patch: Partial<ReservationDetail["query"]> = {},
) {
  const q = { ...d.query, ...patch },
    query = new URLSearchParams();
  for (const k of ["change_id", "before_revision", "before_audit"] as const)
    if (q[k] !== null) query.set(k, String(q[k]));
  return `/missions/${encodeURIComponent(d.context.mission_id)}/ops/contacts/${encodeURIComponent(d.reservation.id)}${query.size ? `?${query}` : ""}`;
}
