import {
  recordPageKeys,
  type ContactRecord,
  type ContactRecordPort,
  type RecordPageKey,
} from "./OpsContactRecord.contracts";
const object = (v: unknown): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: unknown, max = 512): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string => {
  if (!text(v, 240) || !v) return false;
  for (let index = 0; index < v.length; index++) {
    const code = v.charCodeAt(index);
    if (code <= 32 || code === 127) return false;
  }
  return true;
};
const count = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
const version = (v: unknown): v is number => count(v) && v > 0 && v <= 2147483647;
const time = (v: unknown) =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const optional = (v: unknown, check: (v: any) => boolean) => v === null || check(v);
const rows = (v: unknown, check: (v: any) => boolean): v is any[] =>
  Array.isArray(v) && v.length <= 25 && v.every(check);
const unique = (v: any[], key = (r: any) => r.id) => new Set(v.map(key)).size === v.length;
const scheduledState = (v: unknown) =>
  ["scheduled", "realized", "completed", "expired", "canceled"].includes(v as string);
const window = (v: any) =>
  time(v.starts_at) &&
  optional(v.ends_at, time) &&
  (v.ends_at === null || Date.parse(v.starts_at) < Date.parse(v.ends_at));
const revision = (r: any) =>
  object(r) &&
  id(r.id) &&
  version(r.revision) &&
  time(r.created_at) &&
  id(r.created_by) &&
  optional(r.provider_change_id, id);
const path = (p: any) =>
  object(p) &&
  id(p.id) &&
  ["uplink", "downlink"].includes(p.direction) &&
  ["selected", "candidate", "contributing"].includes(p.selection) &&
  optional(p.source_endpoint_ref, id) &&
  count(p.provider_binding_count) &&
  count(p.transport_binding_count);
const page = (p: any, number: number, check: (r: any) => boolean, key?: (r: any) => string) =>
  object(p) &&
  p.page === number &&
  typeof p.more === "boolean" &&
  rows(p.entries, check) &&
  (!p.more || p.entries.length === 25) &&
  unique(p.entries, key);
export function admitContactRecord(
  value: unknown,
  context?: ContactRecordPort["context"],
): ContactRecord | null {
  try {
    if (
      !object(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 262144 ||
      value.contract_version !== 1
    )
      return null;
    const {
      context: c,
      subject,
      query: q,
      scheduled: s,
      realized: r,
      review,
      origin,
      revisions,
    } = value;
    if (
      !object(c) ||
      !id(c.organization_id) ||
      !id(c.mission_id) ||
      !object(subject) ||
      !id(subject.id) ||
      !["scheduled", "realized"].includes(subject.kind)
    )
      return null;
    if (
      context &&
      (context.organization_id !== c.organization_id ||
        context.mission_id !== c.mission_id ||
        (context.contact_id !== undefined && context.contact_id !== subject.id))
    )
      return null;
    if (
      !object(q) ||
      q.contact_id !== subject.id ||
      !optional(q.revision, version) ||
      !optional(q.before_revision, version) ||
      !recordPageKeys.every((k) => version(q[k]) && q[k] <= 1000000)
    )
      return null;
    if (
      s !== null &&
      (!object(s) ||
        !id(s.id) ||
        !version(s.current_revision) ||
        !scheduledState(s.lifecycle_state) ||
        !window(s) ||
        !optional(s.realized_id, id) ||
        !optional(s.provider_contact_ref, text))
    )
      return null;
    if (
      r !== null &&
      (!object(r) ||
        !id(r.id) ||
        !optional(r.scheduled_id, id) ||
        !["defined", "active", "stopped", "completed"].includes(r.lifecycle_state) ||
        !["live", "replay"].includes(r.clock_mode) ||
        !optional(r.realized_at, time) ||
        !optional(r.initial_time, time))
    )
      return null;
    if (subject.kind === "scheduled" ? s?.id !== subject.id : r?.id !== subject.id) return null;
    if (r && r.scheduled_id !== (s?.id ?? null)) return null;
    if (subject.kind === "scheduled" && s.realized_id !== (r?.id ?? null)) return null;
    if ((s === null) !== (review === null)) return null;
    if (
      review !== null &&
      (!revision(review) ||
        review.revision !== q.revision ||
        review.revision > s.current_revision ||
        !window(review) ||
        !scheduledState(review.lifecycle_state) ||
        !optional(review.provider_contact_ref, text))
    )
      return null;
    if (!review && (q.revision !== null || q.before_revision !== null)) return null;
    if (
      origin !== null &&
      (!object(origin) ||
        !id(origin.change_id) ||
        origin.change_id !== review?.provider_change_id ||
        !id(origin.reservation_id) ||
        !version(origin.provider_revision) ||
        !text(origin.proposal_hash, 64) ||
        !/^[0-9a-f]{64}$/.test(origin.proposal_hash))
    )
      return null;
    if ((review?.provider_change_id ?? null) !== (origin?.change_id ?? null)) return null;
    if (
      !object(revisions) ||
      !rows(revisions.entries, revision) ||
      !unique(revisions.entries) ||
      !optional(revisions.next, version)
    )
      return null;
    if (
      revisions.entries.some(
        (row: any, i: number) =>
          !review ||
          row.revision > review.revision ||
          (q.before_revision !== null && row.revision >= q.before_revision) ||
          (i > 0 && revisions.entries[i - 1].revision <= row.revision),
      )
    )
      return null;
    if (
      revisions.next !== null &&
      (revisions.entries.length !== 25 || revisions.next !== revisions.entries.at(-1).revision)
    )
      return null;
    if (
      !page(value.scheduled_paths, q.scheduled_paths_page, path) ||
      !page(value.realized_paths, q.realized_paths_page, path)
    )
      return null;
    if (
      (!s && (value.scheduled_paths.entries.length || value.scheduled_paths.more)) ||
      (!r && (value.realized_paths.entries.length || value.realized_paths.more))
    )
      return null;
    const tagged = (kinds: string[]) => (v: any) =>
      object(v) && id(v.id) && kinds.includes(v.kind) && (v.kind === "realized" ? !!r : !!s);
    if (
      !page(value.sources, q.sources_page, tagged(["reviewed_schedule", "realized"]), (v) =>
        JSON.stringify([v.kind, v.id]),
      ) ||
      !page(value.intents, q.intents_page, tagged(["current_schedule", "realized"]), (v) =>
        JSON.stringify([v.kind, v.id]),
      )
    )
      return null;
    return value as ContactRecord;
  } catch {
    return null;
  }
}
export function recordHref(record: ContactRecord, patch: Partial<ContactRecord["query"]> = {}) {
  const q = { ...record.query, ...patch },
    params = new URLSearchParams();
  if (q.revision !== null) params.set("revision", String(q.revision));
  if (q.before_revision !== null) params.set("before_revision", String(q.before_revision));
  for (const k of recordPageKeys) if (q[k] !== 1) params.set(k, String(q[k]));
  return contactPath(record, record.subject.id) + (params.size ? `?${params}` : "");
}
export const contactPath = (record: ContactRecord, id: string) =>
  `/missions/${encodeURIComponent(record.context.mission_id)}/ops/contacts/records/${encodeURIComponent(id)}`;
export const sectionPage = (
  key: "scheduled_paths" | "realized_paths" | "sources" | "intents",
): RecordPageKey => `${key}_page`;
