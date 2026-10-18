import { record as object, oneOf, arrayOf, type Guard } from "@cadence/plugin-sdk/admission";
import {
  recordPageKeys,
  type ContactRecord,
  type ContactRecordPort,
  type RecordPageKey,
  type ContactRevision,
  type ContactPath,
  type RecordPage,
} from "./OpsContactRecord.contracts";
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
const count = (v: unknown): v is number =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
const version = (v: unknown): v is number => count(v) && v > 0 && v <= 2147483647;
const time = (v: unknown): v is string =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const optional = <T>(v: unknown, check: Guard<T>): v is T | null => v === null || check(v);
const rows = <T>(v: unknown, check: Guard<T>): v is T[] => arrayOf(v, check) && v.length <= 25;
const unique = <T extends { readonly id: string }>(
  v: readonly T[],
  key: (r: T) => string = (r) => r.id,
) => new Set(v.map(key)).size === v.length;
const scheduledState = (v: unknown) =>
  oneOf(["scheduled", "realized", "completed", "expired", "canceled"], v);
const window = (
  v: unknown,
): v is { starts_at: string; ends_at: string | null } & Record<string, unknown> =>
  object(v) &&
  time(v.starts_at) &&
  optional(v.ends_at, time) &&
  (v.ends_at === null || Date.parse(v.starts_at) < Date.parse(v.ends_at));
const revision = (r: unknown): r is ContactRevision & Record<string, unknown> =>
  object(r) &&
  id(r.id) &&
  version(r.revision) &&
  time(r.created_at) &&
  id(r.created_by) &&
  optional(r.provider_change_id, id);
const path = (p: unknown): p is ContactPath =>
  object(p) &&
  id(p.id) &&
  oneOf(["uplink", "downlink"], p.direction) &&
  oneOf(["selected", "candidate", "contributing"], p.selection) &&
  optional(p.source_endpoint_ref, id) &&
  count(p.provider_binding_count) &&
  count(p.transport_binding_count);
const page = <T extends { readonly id: string }>(
  p: unknown,
  number: number,
  check: Guard<T>,
  key?: (r: T) => string,
): p is RecordPage<T> =>
  object(p) &&
  p.page === number &&
  typeof p.more === "boolean" &&
  rows(p.entries, check) &&
  (!p.more || p.entries.length === 25) &&
  unique(p.entries, key);
function scheduled(s: unknown): s is NonNullable<ContactRecord["scheduled"]> {
  return (
    object(s) &&
    id(s.id) &&
    version(s.current_revision) &&
    scheduledState(s.lifecycle_state) &&
    window(s) &&
    optional(s.realized_id, id) &&
    optional(s.provider_contact_ref, text)
  );
}
function query(v: unknown, contactId: string): v is ContactRecord["query"] {
  return (
    object(v) &&
    v.contact_id === contactId &&
    optional(v.revision, version) &&
    optional(v.before_revision, version) &&
    recordPageKeys.every((k) => version(v[k]) && v[k] <= 1000000)
  );
}
export function admitContactRecord(
  value: unknown,
  context?: ContactRecordPort["context"],
): ContactRecord | null {
  return validContactRecord(value, context) ? value : null;
}
function validContactRecord(
  value: unknown,
  context?: ContactRecordPort["context"],
): value is ContactRecord {
  try {
    if (
      !object(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 262144 ||
      value.contract_version !== 1
    )
      return false;
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
      !oneOf(["scheduled", "realized"], subject.kind)
    )
      return false;
    if (
      context &&
      (context.organization_id !== c.organization_id ||
        context.mission_id !== c.mission_id ||
        (context.contact_id !== undefined && context.contact_id !== subject.id))
    )
      return false;
    if (!query(q, subject.id)) return false;
    if (s !== null && !scheduled(s)) return false;
    if (
      r !== null &&
      (!object(r) ||
        !id(r.id) ||
        !optional(r.scheduled_id, id) ||
        !oneOf(["defined", "active", "stopped", "completed"], r.lifecycle_state) ||
        !oneOf(["live", "replay"], r.clock_mode) ||
        !optional(r.realized_at, time) ||
        !optional(r.initial_time, time))
    )
      return false;
    if (subject.kind === "scheduled" ? s?.id !== subject.id : r?.id !== subject.id) return false;
    if (r && r.scheduled_id !== (s?.id ?? null)) return false;
    if (subject.kind === "scheduled" && (!s || s.realized_id !== (r?.id ?? null))) return false;
    if ((s === null) !== (review === null)) return false;
    if (
      review !== null &&
      (!revision(review) ||
        review.revision !== q.revision ||
        !s ||
        review.revision > s.current_revision ||
        !window(review) ||
        !scheduledState(review.lifecycle_state) ||
        !optional(review.provider_contact_ref, text))
    )
      return false;
    if (!review && (q.revision !== null || q.before_revision !== null)) return false;
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
      return false;
    if ((review?.provider_change_id ?? null) !== (origin?.change_id ?? null)) return false;
    if (
      !object(revisions) ||
      !rows(revisions.entries, revision) ||
      !unique(revisions.entries) ||
      !optional(revisions.next, version)
    )
      return false;
    const beforeRevision = q.before_revision,
      revisionEntries = revisions.entries;
    if (
      revisionEntries.some((row, index) => {
        const previous = revisionEntries[index - 1];
        return (
          !review ||
          row.revision > review.revision ||
          (beforeRevision !== null && row.revision >= beforeRevision) ||
          (index > 0 && (!previous || previous.revision <= row.revision))
        );
      })
    )
      return false;
    if (
      revisions.next !== null &&
      (revisions.entries.length !== 25 || revisions.next !== revisions.entries.at(-1)?.revision)
    )
      return false;
    if (
      !page(value.scheduled_paths, q.scheduled_paths_page, path) ||
      !page(value.realized_paths, q.realized_paths_page, path)
    )
      return false;
    if (
      (!s && (value.scheduled_paths.entries.length || value.scheduled_paths.more)) ||
      (!r && (value.realized_paths.entries.length || value.realized_paths.more))
    )
      return false;
    const tagged =
      <const K extends string>(kinds: readonly K[]) =>
      (v: unknown): v is { id: string; kind: K } =>
        object(v) && id(v.id) && oneOf(kinds, v.kind) && (v.kind === "realized" ? !!r : !!s);
    if (
      !page(value.sources, q.sources_page, tagged(["reviewed_schedule", "realized"]), (v) =>
        JSON.stringify([v.kind, v.id]),
      ) ||
      !page(value.intents, q.intents_page, tagged(["current_schedule", "realized"]), (v) =>
        JSON.stringify([v.kind, v.id]),
      )
    )
      return false;
    return true;
  } catch {
    return false;
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
