import {
  schedulePageKeys,
  type ContactSchedule,
  type ScheduleContext,
  type ScheduleRoute,
  type ScheduleSearch,
  type ScheduleSearchResult,
  type ScheduleReceipt,
  type ScheduleReservation,
} from "./OpsContactSchedule.contracts";
const object = (v: unknown): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: unknown, max = 512): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string => {
  if (!text(v, 240) || !v || /\s/u.test(v)) return false;
  for (let i = 0; i < v.length; i++)
    if (v.charCodeAt(i) < 32 || v.charCodeAt(i) === 127) return false;
  return true;
};
const version = (v: unknown): v is number =>
  Number.isSafeInteger(v) && (v as number) > 0 && (v as number) <= 2147483647;
const optional = (v: unknown, check: (v: any) => boolean) => v === null || check(v);
const time = (v: unknown): v is string =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const window = (v: any) =>
  time(v.starts_at) && time(v.ends_at) && Date.parse(v.starts_at) < Date.parse(v.ends_at);
const profile = (v: any) =>
  object(v) && id(v.id) && version(v.version) && Object.keys(v).length === 2;
const context = (v: any, c?: ScheduleContext) =>
  object(v) &&
  id(v.organization_id) &&
  id(v.mission_id) &&
  (!c || (v.organization_id === c.organization_id && v.mission_id === c.mission_id));
const unique = (rows: any[], key: (v: any) => string) =>
  new Set(rows.map(key)).size === rows.length;
const page = (p: any, n: number, check: (v: any) => boolean, key = (v: any) => v.id) =>
  object(p) &&
  p.page === n &&
  typeof p.more === "boolean" &&
  Array.isArray(p.entries) &&
  p.entries.length <= 25 &&
  (!p.more || p.entries.length === 25) &&
  p.entries.every(check) &&
  unique(p.entries, key);
const craft = (v: any) => object(v) && id(v.id) && text(v.name, 480);
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
];
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
function route(v: any) {
  return (
    object(v) &&
    id(v.key) &&
    id(v.spacecraft_id) &&
    ["provider", "transport", "service", "delivery", "delivery_summary"].every((k) =>
      text(v[k], 480),
    ) &&
    object(v.evidence) &&
    Object.keys(v.evidence).length === 13 &&
    evidenceIds.every((k) => id(v.evidence[k])) &&
    evidenceVersions.every((k) => version(v.evidence[k])) &&
    profile(v.evidence.service_profile_ref) &&
    profile(v.evidence.delivery_profile_ref)
  );
}
export function validScheduleSearch(form: any, evidence: unknown): boolean {
  return (
    object(form) &&
    Object.keys(form).length === 4 &&
    id(form.spacecraft_id) &&
    id(form.route_key) &&
    window(form) &&
    Date.parse(form.ends_at) - Date.parse(form.starts_at) <= 604800000 &&
    route({
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
export function reservation(v: any): v is ScheduleReservation {
  return (
    object(v) &&
    id(v.id) &&
    states.includes(v.lifecycle_state) &&
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
export function admitContactSchedule(
  value: unknown,
  captured?: ScheduleContext,
): ContactSchedule | null {
  try {
    if (
      !object(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 262144 ||
      value.contract_version !== 1 ||
      !context(value.context, captured)
    )
      return null;
    if (
      !object(value.permissions) ||
      typeof value.permissions.operate !== "boolean" ||
      typeof value.permissions.cancel !== "boolean"
    )
      return null;
    const q = value.query;
    if (
      !object(q) ||
      !schedulePageKeys.every((k) => version(q[k]) && q[k] <= 1000000) ||
      !optional(q.spacecraft_id, id) ||
      !text(q.spacecraft_q, 120) ||
      !object(value.initial_window) ||
      !window(value.initial_window)
    )
      return null;
    if (
      !page(value.spacecraft, q.spacecraft_page, craft) ||
      !optional(value.selected_spacecraft, craft) ||
      (value.selected_spacecraft?.id ?? null) !== q.spacecraft_id
    )
      return null;
    if (
      !page(
        value.routes,
        q.routes_page,
        (v) => route(v) && v.spacecraft_id === q.spacecraft_id,
        (v) => v.key,
      ) ||
      !page(
        value.findings,
        q.findings_page,
        (v) => object(v) && id(v.code) && text(v.message, 480) && optional(v.resource_id, id),
        (v) => JSON.stringify([v.code, v.resource_id]),
      )
    )
      return null;
    if (
      !q.spacecraft_id &&
      (value.routes.entries.length ||
        value.routes.more ||
        value.findings.entries.length ||
        value.findings.more)
    )
      return null;
    if (!page(value.reservations, q.reservations_page, reservation)) return null;
    if (
      !page(
        value.scheduled,
        q.scheduled_page,
        (v) =>
          object(v) &&
          id(v.id) &&
          ["scheduled", "realized", "completed", "expired", "canceled"].includes(
            v.lifecycle_state,
          ) &&
          version(v.revision) &&
          optional(v.starts_at, time) &&
          optional(v.ends_at, time) &&
          (!v.ends_at || (v.starts_at && Date.parse(v.starts_at) < Date.parse(v.ends_at))) &&
          optional(v.realized_id, id),
      )
    )
      return null;
    if (
      !page(
        value.realized,
        q.realized_page,
        (v) =>
          object(v) &&
          id(v.id) &&
          ["defined", "active", "stopped", "completed"].includes(v.lifecycle_state) &&
          ["live", "replay"].includes(v.clock_mode) &&
          optional(v.realized_at, time) &&
          optional(v.scheduled_id, id),
      )
    )
      return null;
    return JSON.parse(JSON.stringify(value)) as ContactSchedule;
  } catch {
    return null;
  }
}
export function sameEvidence(a: Record<string, any>, b: Record<string, any>): boolean {
  return (
    Object.keys(a).length === Object.keys(b).length &&
    Object.keys(a).every((k) =>
      object(a[k]) && object(b[k]) ? sameEvidence(a[k], b[k]) : a[k] === b[k],
    )
  );
}
export function admitSearch(
  value: unknown,
  c: ScheduleContext,
  search: ScheduleSearch,
  reviewed: ScheduleRoute,
): ScheduleSearchResult | null {
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
      !route(value.route) ||
      !sameEvidence(value.route, reviewed)
    )
      return null;
    const rows = value.opportunities;
    if (
      !Array.isArray(rows) ||
      rows.length > 100 ||
      !unique(rows, (v) => v.id) ||
      !rows.every(
        (v) =>
          object(v) &&
          id(v.id) &&
          window(v) &&
          Date.parse(v.starts_at) >= Date.parse(search.starts_at) &&
          Date.parse(v.ends_at) <= Date.parse(search.ends_at) &&
          time(v.expires_at) &&
          ["available", "limited", "unavailable"].includes(v.availability) &&
          typeof v.synthetic === "boolean" &&
          text(v.station) &&
          optional(v.antenna, text) &&
          (v.cost === null || (typeof v.cost === "number" && Number.isFinite(v.cost))) &&
          text(v.token, 8192) &&
          !!v.token,
      )
    )
      return null;
    return JSON.parse(JSON.stringify(value)) as ScheduleSearchResult;
  } catch {
    return null;
  }
}
export function admitReceipt(v: unknown, reservationId?: string): ScheduleReceipt | null {
  return object(v) &&
    id(v.providerReservationId) &&
    (!reservationId || v.providerReservationId === reservationId) &&
    version(v.providerRevision) &&
    states.includes(v.lifecycleState) &&
    optional(v.scheduledContactId, id)
    ? (v as ScheduleReceipt)
    : null;
}
export const cancellable = (v: ScheduleReservation) =>
  ["pending", "confirmed", "active"].includes(v.lifecycle_state) && !!v.provider_contact_ref;
export const cancelEvidence = (c: ScheduleContext, v: ScheduleReservation) => ({
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
