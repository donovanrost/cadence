import { record as isRecord } from "@cadence/plugin-sdk/admission";
import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import type { HistoryModel, Release, Verifier, MatchedRecord } from "./types";
import { identity, readHistoryQuery } from "./query";
type Check = (v: unknown) => boolean;
const text = (v: unknown, max = 512): v is string =>
  typeof v === "string" &&
  v.length > 0 &&
  new TextEncoder().encode(v).length <= max &&
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v);
const oneOf =
  (...values: unknown[]): Check =>
  (v) =>
    values.includes(v);
const optional =
  (check: Check): Check =>
  (v) =>
    v === null || check(v);
const time: Check = (v) =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 19) === v.slice(0, 19);
const count: Check = (v) => Number.isSafeInteger(v) && Number(v) >= 0;
const verification = oneOf(null, "not_required", "pending", "satisfied", "failed", "timed_out");
const phase = oneOf("acceptance", "start", "completion", "custom");
const fail = (): never => {
  throw Error("Unavailable command history");
};
function shape(value: unknown, fields: Record<string, Check>): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail();
  const v = value as Record<string, unknown>,
    keys = Object.keys(fields);
  if (
    Object.keys(v).length !== keys.length ||
    Object.entries(fields).some(([key, check]) => !Object.hasOwn(v, key) || !check(v[key]))
  )
    fail();
  return v;
}
const object: Check = (v) => !!v && typeof v === "object" && !Array.isArray(v);
const json: Check = (v) => {
  if (!text(v, 65536)) return false;
  try {
    JSON.parse(v);
    return true;
  } catch {
    return false;
  }
};
const canonical = (v: unknown) =>
  JSON.stringify(v, (_, item: unknown) =>
    isRecord(item)
      ? Object.fromEntries(Object.entries(item).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)))
      : item,
  );
function release(value: unknown, request: string): Release {
  const v = shape(value, {
    id: identity,
    request_id: oneOf(request),
    queue_entry_id: identity,
    contact_id: identity,
    path_id: optional(identity),
    binding_id: optional(identity),
    state: oneOf("release_pending", "released", "release_failed", "release_uncertain", "canceled"),
    verification_state: verification,
    attempted_at: optional(time),
    released_at: optional(time),
    encoded_size_bytes: optional(count),
  });
  return v as Release;
}
function verifier(value: unknown, request: string, selectedRelease: string): Verifier {
  const v = shape(value, {
    id: identity,
    request_id: oneOf(request),
    release_attempt_id: selectedRelease ? oneOf(selectedRelease) : identity,
    name: text,
    phase,
    severity: oneOf(null, "info", "warning", "error", "critical"),
    state: oneOf("pending", "satisfied", "failed", "timed_out", "canceled"),
    failure_code: oneOf(null, "timed_out", "failure_criteria_matched"),
    matched_at: optional(time),
    timeout_at: optional(time),
    matched_record_kind: oneOf(
      null,
      "telemetry_sample",
      "transport_action_request",
      "transport_capability_record",
    ),
    matched_record_id: optional(identity),
  });
  return v as Verifier;
}
function ledger<T extends { id: string }>(value: unknown, read: (v: unknown) => T) {
  const l = shape(value, {
    entries: Array.isArray,
    limit: oneOf(25),
    next_after: optional(identity),
  });
  const entries = (l.entries as unknown[]).map(read);
  if (
    entries.length > 25 ||
    new Set(entries.map((v) => v.id)).size !== entries.length ||
    (l.next_after !== null && (entries.length !== 25 || entries.at(-1)?.id !== l.next_after))
  )
    fail();
  return entries;
}
function record(value: unknown, model: HistoryModel, selected: Verifier): MatchedRecord {
  const scoped = {
    id: oneOf(selected.matched_record_id),
    organization_id: oneOf(model.organization_id),
    mission_id: oneOf(model.mission_id),
  };
  if (!object(value)) fail();
  const kind = (value as Record<string, unknown>).kind;
  if (kind !== selected.matched_record_kind) fail();
  if (kind === "telemetry_sample") {
    shape(value, {
      ...scoped,
      kind: oneOf(kind),
      point_id: identity,
      point_name: text,
      packet_id: identity,
      evidence_id: identity,
      spacecraft_id: optional(identity),
      quality_state: oneOf("good", "suspect", "bad"),
      raw_value_json: json,
      engineering_value_json: json,
      generation_time: optional(time),
      receipt_time: time,
    });
  } else {
    const correlated = {
      ...scoped,
      kind: oneOf(kind),
      request_id: oneOf(model.request.id),
      release_attempt_id: oneOf(selected.release_attempt_id),
      contact_id: identity,
      path_id: identity,
      family_key: identity,
    };
    if (kind === "transport_action_request")
      shape(value, {
        ...correlated,
        signal_phase: optional(phase),
        action_kind: identity,
        requested_at: time,
      });
    else if (kind === "transport_capability_record")
      shape(value, { ...correlated, event_kind: identity, recorded_at: time });
    else fail();
  }
  return value as MatchedRecord;
}
export function readCommandHistory(value: unknown, context: OpsPageContext): HistoryModel {
  const m = shape(value, {
    version: oneOf(1),
    organization_id: identity,
    mission_id: identity,
    observed_at: time,
    request: object,
    query: object,
    releases: object,
    verifiers: object,
    selection: object,
    evidence: object,
  });
  if (
    m.organization_id !== context.organizationId ||
    m.mission_id !== context.missionId ||
    !identity(context.resourceId)
  )
    fail();
  const r = shape(m.request, {
    id: oneOf(context.resourceId),
    command_id: identity,
    name: text,
    target: identity,
    target_name: optional(text),
    model_revision_id: identity,
    state: oneOf(
      "draft",
      "validated",
      "approval_pending",
      "approved",
      "rejected",
      "queued",
      "released",
      "canceled",
    ),
    verification_state: verification,
  });
  const query = readHistoryQuery(m.query);
  if (canonical(query) !== canonical(m.query)) fail();
  const releases = ledger(m.releases, (v) => release(v, r.id as string));
  const verifiers = ledger(m.verifiers, (v) => verifier(v, r.id as string, query.release));
  const selection = shape(m.selection, { release: optional(object), verifier: optional(object) });
  if (!!selection.release !== !!query.release || !!selection.verifier !== !!query.verifier) fail();
  if (selection.release) {
    const selected = release(selection.release, r.id as string),
      visible = releases.find((v) => v.id === query.release);
    if (selected.id !== query.release || (visible && canonical(visible) !== canonical(selected)))
      fail();
  }
  if (selection.verifier) {
    const selected = verifier(selection.verifier, r.id as string, query.release),
      visible = verifiers.find((v) => v.id === query.verifier);
    if (selected.id !== query.verifier || (visible && canonical(visible) !== canonical(selected)))
      fail();
  }
  const evidence = shape(m.evidence, {
    status: oneOf("not_selected", "unmatched", "unavailable", "ready"),
    record: optional(object),
  });
  const selected = selection.verifier as Verifier | null;
  if (!selected) {
    if (evidence.status !== "not_selected" || evidence.record !== null) fail();
  } else if (evidence.status === "ready") {
    if (!selected.matched_record_kind || !selected.matched_record_id) fail();
    record(evidence.record, value as HistoryModel, selected);
  } else if (
    evidence.record !== null ||
    !(
      evidence.status === "unavailable" ||
      (evidence.status === "unmatched" &&
        selected.matched_record_kind === null &&
        selected.matched_record_id === null)
    )
  )
    fail();
  if (new TextEncoder().encode(JSON.stringify(value)).length > 524288) fail();
  return value as HistoryModel;
}
