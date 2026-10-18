import { record as object, oneOf, arrayOf, type Guard } from "@cadence/plugin-sdk/admission";
import {
  schedulePageKeys,
  type ContactSchedule,
  type ScheduleContext,
  type ScheduleRoute,
  type ScheduleSearch,
  type ScheduleSearchResult,
  type ScheduleReceipt,
  type ScheduleReservation,
  type SchedulePage,
  type ProfileRef,
  type RouteEvidence,
  type ScheduleOpportunity,
  type CancellableReservation,
  type CancelEvidence,
} from "./OpsContactSchedule.contracts";
const text = (v: unknown, max = 512): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string => {
  if (!text(v, 240) || !v || /\s/u.test(v)) return false;
  for (let i = 0; i < v.length; i++)
    if (v.charCodeAt(i) < 32 || v.charCodeAt(i) === 127) return false;
  return true;
};
const version = (v: unknown): v is number =>
  typeof v === "number" && Number.isSafeInteger(v) && v > 0 && v <= 2147483647;
const optional = <T>(v: unknown, check: Guard<T>): v is T | null => v === null || check(v);
const time = (v: unknown): v is string =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const window = (
  v: unknown,
): v is { starts_at: string; ends_at: string } & Record<string, unknown> =>
  object(v) &&
  time(v.starts_at) &&
  time(v.ends_at) &&
  Date.parse(v.starts_at) < Date.parse(v.ends_at);
const profile = (v: unknown): v is ProfileRef =>
  object(v) && id(v.id) && version(v.version) && Object.keys(v).length === 2;
const context = (v: unknown, c?: ScheduleContext): v is ScheduleContext =>
  object(v) &&
  id(v.organization_id) &&
  id(v.mission_id) &&
  (!c || (v.organization_id === c.organization_id && v.mission_id === c.mission_id));
const unique = <T>(rows: readonly T[], key: (v: T) => string) =>
  new Set(rows.map(key)).size === rows.length;
const page = <T>(
  p: unknown,
  n: number,
  check: Guard<T>,
  key: (v: T) => string,
): p is SchedulePage<T> =>
  object(p) &&
  p.page === n &&
  typeof p.more === "boolean" &&
  arrayOf(p.entries, check) &&
  p.entries.length <= 25 &&
  (!p.more || p.entries.length === 25) &&
  unique(p.entries, key);
const craft = (v: unknown): v is { id: string; name: string } =>
  object(v) && id(v.id) && text(v.name, 480);
const states = [
  "requesting",
  "pending",
  "confirmed",
  "active",
  "completed",
  "rejected",
  "canceled",
  "canceling",
  "failed",
  "unknown",
] as const;
const evidenceIds = [
  "provider_id",
  "transport_id",
  "provider_profile_id",
  "routing_rule_id",
  "path_template_id",
  "source_endpoint_id",
  "provider_spacecraft_ref",
];
const evidenceVersions = [
  "provider_version",
  "transport_version",
  "provider_profile_version",
  "path_template_version",
];
export function validRouteEvidence(v: unknown): v is RouteEvidence {
  return (
    object(v) &&
    Object.keys(v).length === 13 &&
    evidenceIds.every((k) => id(v[k])) &&
    evidenceVersions.every((k) => version(v[k])) &&
    profile(v.service_profile_ref) &&
    profile(v.delivery_profile_ref)
  );
}
export function validScheduleRoute(v: unknown): v is ScheduleRoute {
  return (
    object(v) &&
    id(v.key) &&
    id(v.spacecraft_id) &&
    ["provider", "transport", "service", "delivery", "delivery_summary"].every((k) =>
      text(v[k], 480),
    ) &&
    validRouteEvidence(v.evidence)
  );
}
export function validScheduleSearch(form: unknown, evidence: unknown): form is ScheduleSearch {
  return (
    object(form) &&
    Object.keys(form).length === 4 &&
    id(form.spacecraft_id) &&
    id(form.route_key) &&
    window(form) &&
    Date.parse(form.ends_at) - Date.parse(form.starts_at) <= 604800000 &&
    validScheduleRoute({
      key: form.route_key,
      spacecraft_id: form.spacecraft_id,
      provider: "",
      transport: "",
      service: "",
      delivery: "",
      delivery_summary: "",
      evidence,
    })
  );
}
export function reservation(v: unknown): v is ScheduleReservation {
  return (
    object(v) &&
    id(v.id) &&
    oneOf(states, v.lifecycle_state) &&
    version(v.provider_revision) &&
    optional(v.provider_contact_ref, text) &&
    id(v.provider_id) &&
    version(v.provider_version) &&
    optional(v.transport_id, id) &&
    optional(v.transport_version, version) &&
    (v.transport_id === null) === (v.transport_version === null) &&
    optional(v.service_profile, profile) &&
    optional(v.delivery_profile, profile) &&
    window(v) &&
    optional(v.scheduled_id, id) &&
    optional(v.last_reconciled_at, time)
  );
}
function snapshot(value: unknown, limit: number): unknown {
  const encoded = JSON.stringify(value);
  if (new TextEncoder().encode(encoded).length > limit) throw Error("Oversized schedule input");
  return JSON.parse(encoded);
}
function validQuery(v: unknown): v is ContactSchedule["query"] {
  return (
    object(v) &&
    schedulePageKeys.every((k) => version(v[k]) && v[k] <= 1000000) &&
    optional(v.spacecraft_id, id) &&
    text(v.spacecraft_q, 120)
  );
}
export function admitContactSchedule(
  input: unknown,
  captured?: ScheduleContext,
): ContactSchedule | null {
  try {
    const value = snapshot(input, 262144);
    return validContactSchedule(value, captured) ? value : null;
  } catch {
    return null;
  }
}
function validContactSchedule(
  value: unknown,
  captured?: ScheduleContext,
): value is ContactSchedule {
  try {
    if (
      !object(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 262144 ||
      value.contract_version !== 1 ||
      !context(value.context, captured)
    )
      return false;
    if (
      !object(value.permissions) ||
      typeof value.permissions.operate !== "boolean" ||
      typeof value.permissions.cancel !== "boolean"
    )
      return false;
    const q = value.query;
    if (!validQuery(q) || !object(value.initial_window) || !window(value.initial_window))
      return false;
    if (
      !page(value.spacecraft, q.spacecraft_page, craft, (v) => v.id) ||
      !optional(value.selected_spacecraft, craft) ||
      (value.selected_spacecraft?.id ?? null) !== q.spacecraft_id
    )
      return false;
    if (
      !page(
        value.routes,
        q.routes_page,
        (v): v is ScheduleRoute => validScheduleRoute(v) && v.spacecraft_id === q.spacecraft_id,
        (v) => v.key,
      ) ||
      !page(
        value.findings,
        q.findings_page,
        (v): v is ContactSchedule["findings"]["entries"][number] =>
          object(v) && id(v.code) && text(v.message, 480) && optional(v.resource_id, id),
        (v) => JSON.stringify([v.code, v.resource_id]),
      )
    )
      return false;
    if (
      !q.spacecraft_id &&
      (value.routes.entries.length ||
        value.routes.more ||
        value.findings.entries.length ||
        value.findings.more)
    )
      return false;
    if (!page(value.reservations, q.reservations_page, reservation, (v) => v.id)) return false;
    if (
      !page(
        value.scheduled,
        q.scheduled_page,
        (v): v is ContactSchedule["scheduled"]["entries"][number] =>
          object(v) &&
          id(v.id) &&
          oneOf(["scheduled", "realized", "completed", "expired", "canceled"], v.lifecycle_state) &&
          version(v.revision) &&
          optional(v.starts_at, time) &&
          optional(v.ends_at, time) &&
          (!v.ends_at ||
            (v.starts_at !== null && Date.parse(v.starts_at) < Date.parse(v.ends_at))) &&
          optional(v.realized_id, id),
        (v) => v.id,
      )
    )
      return false;
    if (
      !page(
        value.realized,
        q.realized_page,
        (v): v is ContactSchedule["realized"]["entries"][number] =>
          object(v) &&
          id(v.id) &&
          oneOf(["defined", "active", "stopped", "completed"], v.lifecycle_state) &&
          oneOf(["live", "replay"], v.clock_mode) &&
          optional(v.realized_at, time) &&
          optional(v.scheduled_id, id),
        (v) => v.id,
      )
    )
      return false;
    return true;
  } catch {
    return false;
  }
}
export function sameEvidence(a: Record<string, unknown>, b: Record<string, unknown>): boolean {
  return (
    Object.keys(a).length === Object.keys(b).length &&
    Object.keys(a).every((k) =>
      object(a[k]) && object(b[k]) ? sameEvidence(a[k], b[k]) : a[k] === b[k],
    )
  );
}
export function admitSearch(
  input: unknown,
  c: ScheduleContext,
  search: ScheduleSearch,
  reviewed: ScheduleRoute,
): ScheduleSearchResult | null {
  try {
    const value = snapshot(input, 1048576);
    return validSearchResult(value, c, search, reviewed) ? value : null;
  } catch {
    return null;
  }
}
function validSearchResult(
  value: unknown,
  c: ScheduleContext,
  search: ScheduleSearch,
  reviewed: ScheduleRoute,
): value is ScheduleSearchResult {
  try {
    if (
      !object(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 1048576 ||
      value.contract_version !== 1 ||
      typeof value.truncated !== "boolean" ||
      !context(value.context, c) ||
      !object(value.search) ||
      !validScheduleSearch(search, reviewed.evidence) ||
      reviewed.key !== search.route_key ||
      reviewed.spacecraft_id !== search.spacecraft_id ||
      !sameEvidence(value.search, search) ||
      !validScheduleRoute(value.route) ||
      !sameEvidence(value.route, reviewed)
    )
      return false;
    const rows = value.opportunities;
    if (
      !arrayOf(rows, object) ||
      rows.length > 100 ||
      !rows.every(
        (v): v is ScheduleOpportunity =>
          object(v) &&
          id(v.id) &&
          window(v) &&
          Date.parse(v.starts_at) >= Date.parse(search.starts_at) &&
          Date.parse(v.ends_at) <= Date.parse(search.ends_at) &&
          time(v.expires_at) &&
          oneOf(["available", "limited", "unavailable"], v.availability) &&
          typeof v.synthetic === "boolean" &&
          text(v.station) &&
          optional(v.antenna, text) &&
          (v.cost === null || (typeof v.cost === "number" && Number.isFinite(v.cost))) &&
          text(v.token, 8192) &&
          !!v.token,
      ) ||
      !unique(rows, (v) => v.id)
    )
      return false;
    return true;
  } catch {
    return false;
  }
}
export function admitReceipt(v: unknown, reservationId?: string): ScheduleReceipt | null {
  return validReceipt(v, reservationId) ? v : null;
}
function validReceipt(v: unknown, reservationId?: string): v is ScheduleReceipt {
  return (
    object(v) &&
    id(v.providerReservationId) &&
    (!reservationId || v.providerReservationId === reservationId) &&
    version(v.providerRevision) &&
    oneOf(states, v.lifecycleState) &&
    optional(v.scheduledContactId, id)
  );
}
export const cancellable = (v: ScheduleReservation): v is CancellableReservation =>
  oneOf(["pending", "confirmed", "active"], v.lifecycle_state) && !!v.provider_contact_ref;
export const cancelEvidence = (c: ScheduleContext, v: CancellableReservation): CancelEvidence => ({
  contract_version: 1,
  ...c,
  reservation_id: v.id,
  provider_revision: v.provider_revision,
  lifecycle_state: v.lifecycle_state,
  provider_contact_ref: v.provider_contact_ref,
});
export const schedulePath = (c: ScheduleContext) =>
  `/missions/${encodeURIComponent(c.mission_id)}/ops/contacts`;
export function scheduleHref(
  model: ContactSchedule,
  patch: Partial<ContactSchedule["query"]> = {},
) {
  const q = { ...model.query, ...patch },
    params = new URLSearchParams();
  if (q.spacecraft_id) params.set("spacecraft_id", q.spacecraft_id);
  if (q.spacecraft_q) params.set("spacecraft_q", q.spacecraft_q);
  for (const k of schedulePageKeys) if (q[k] !== 1) params.set(k, String(q[k]));
  return schedulePath(model.context) + (params.size ? `?${params}` : "");
}

export function completedResult(v: unknown): unknown {
  if (!object(v) || !id(v.receiptId) || !time(v.completedAt))
    throw new Error("Invalid completion receipt");
  return v.result;
}

export function parseScheduleUTC(value: string) {
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d)?$/.test(value)) return NaN;
  const full = value.length === 16 ? value + ":00" : value;
  const stamp = Date.parse(full + "Z");
  return Number.isFinite(stamp) && new Date(stamp).toISOString().slice(0, 19) === full
    ? stamp
    : NaN;
}
