import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { commandStates, type CommandMonitorModel } from "./monitor.contracts";
import { readMonitorQuery } from "./monitor-query";
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid command object");
  const obj = value as Record<string, unknown>;
  if (Object.keys(obj).length !== keys.length || keys.some((key) => !Object.hasOwn(obj, key)))
    throw Error("Invalid command fields");
  return obj;
}
function text(v: unknown, max = 256): v is string {
  return typeof v === "string" && v.length > 0 && new TextEncoder().encode(v).length <= max;
}
function optional(v: unknown, max = 256) {
  return v === null || text(v, max);
}
function time(v: unknown) {
  return (
    v === null ||
    (text(v, 40) &&
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(v) &&
      Number.isFinite(Date.parse(v)))
  );
}
function count(v: unknown): v is number {
  return Number.isSafeInteger(v) && Number(v) >= 0;
}
const oneOf = (v: unknown, values: readonly string[]) =>
  typeof v === "string" && values.includes(v);
const verification = (v: unknown) =>
  v === null || oneOf(v, ["not_required", "pending", "satisfied", "failed", "timed_out"]);
const canonical = (v: unknown) =>
  JSON.stringify(v, (_, value: unknown) =>
    value && typeof value === "object" && !Array.isArray(value)
      ? Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)))
      : value,
  );
function observation(value: unknown) {
  const r = object(value, [
    "id",
    "command_id",
    "name",
    "status",
    "target",
    "target_name",
    "requested_by",
    "requested_at",
    "occurred_at",
    "request_state",
    "verification_state",
    "queue",
    "release",
    "verifiers",
    "verifier_total",
  ]);
  if (
    !text(r.id) ||
    !text(r.name, 512) ||
    !text(r.requested_by, 512) ||
    !optional(r.command_id) ||
    !optional(r.target) ||
    !optional(r.target_name, 512) ||
    !oneOf(r.status, commandStates) ||
    !oneOf(r.request_state, commandStates.slice(0, 8)) ||
    !verification(r.verification_state) ||
    !time(r.requested_at) ||
    !time(r.occurred_at)
  )
    throw Error("Invalid command row");
  if (r.queue !== null) {
    const q = object(r.queue, ["id", "state", "lane", "enqueued_at"]);
    if (
      !text(q.id) ||
      !text(q.lane) ||
      !oneOf(q.state, ["pending", "release_pending", "released", "canceled"]) ||
      !time(q.enqueued_at)
    )
      throw Error("Invalid command queue");
  }
  if (r.release !== null) {
    const a = object(r.release, [
      "id",
      "queue_entry_id",
      "state",
      "verification_state",
      "contact_id",
      "attempted_at",
      "released_at",
    ]);
    if (
      ![a.id, a.queue_entry_id, a.contact_id].every((v) => text(v)) ||
      !oneOf(a.state, [
        "release_pending",
        "released",
        "release_failed",
        "release_uncertain",
        "canceled",
      ]) ||
      !verification(a.verification_state) ||
      !time(a.attempted_at) ||
      !time(a.released_at)
    )
      throw Error("Invalid command release");
  }
  if (
    !count(r.verifier_total) ||
    !Array.isArray(r.verifiers) ||
    r.verifiers.length !== Math.min(20, r.verifier_total)
  )
    throw Error("Invalid verifier count");
  const ids = new Set<string>();
  for (const value of r.verifiers) {
    const v = object(value, [
      "id",
      "release_attempt_id",
      "name",
      "state",
      "matched_at",
      "timeout_at",
      "matched_record_kind",
      "matched_record_id",
    ]);
    if (
      !text(v.id) ||
      ids.has(v.id) ||
      !text(v.release_attempt_id) ||
      !text(v.name, 512) ||
      !oneOf(v.state, ["pending", "satisfied", "failed", "timed_out", "canceled"]) ||
      !time(v.matched_at) ||
      !time(v.timeout_at) ||
      !optional(v.matched_record_id) ||
      !(
        v.matched_record_kind === null ||
        oneOf(v.matched_record_kind, [
          "telemetry_sample",
          "transport_action_request",
          "transport_capability_record",
        ])
      )
    )
      throw Error("Invalid command verifier");
    ids.add(v.id);
  }
  return r;
}
export function readCommandMonitor(value: unknown, context: OpsPageContext): CommandMonitorModel {
  const m = object(value, [
    "version",
    "can_review",
    "organization_id",
    "mission_id",
    "observed_at",
    "query",
    "status",
    "summary",
    "total",
    "pages",
    "page_size",
    "targets",
    "targets_limited",
    "rows",
    "focus",
  ]);
  if (
    m.version !== 1 ||
    typeof m.can_review !== "boolean" ||
    !text(m.organization_id) ||
    !text(m.mission_id) ||
    m.organization_id !== context.organizationId ||
    m.mission_id !== context.missionId ||
    context.resourceId !== undefined ||
    m.observed_at === null ||
    !time(m.observed_at) ||
    !count(m.total) ||
    !count(m.pages) ||
    m.pages !== Math.max(1, Math.ceil(m.total / 25)) ||
    m.page_size !== 25 ||
    !oneOf(m.status, ["ready", "empty"]) ||
    (m.status === "empty") !== (m.total === 0)
  )
    throw Error("Invalid command monitor");
  const query = readMonitorQuery(m.query);
  if (Number(query.page) > m.pages || canonical(query) !== canonical(m.query))
    throw Error("Invalid canonical command query");
  const summaryKeys = [
    "total_count",
    "active_count",
    "queued_count",
    "release_pending_count",
    "in_flight_count",
    "released_count",
    "failed_count",
    "indeterminate_count",
  ];
  const s = object(m.summary, summaryKeys);
  if (
    !Object.values(s).every(count) ||
    m.total > Number(s.total_count) ||
    Object.values(s).some((n) => Number(n) > Number(s.total_count)) ||
    s.active_count !==
      Number(s.queued_count) +
        Number(s.release_pending_count) +
        Number(s.in_flight_count) +
        Number(s.failed_count) +
        Number(s.indeterminate_count)
  )
    throw Error("Invalid command summary");
  if (
    !Array.isArray(m.targets) ||
    m.targets.length > 200 ||
    !m.targets.every((v) => {
      const target = object(v, ["id", "name"]);
      return text(target.id) && optional(target.name, 512);
    }) ||
    new Set(m.targets.map((v: unknown) => object(v, ["id", "name"]).id)).size !==
      m.targets.length ||
    typeof m.targets_limited !== "boolean"
  )
    throw Error("Invalid command targets");
  if (
    !Array.isArray(m.rows) ||
    m.rows.length !== Math.min(25, m.total - (Number(query.page) - 1) * 25)
  )
    throw Error("Invalid command page");
  const rows = m.rows.map(observation);
  if (new Set(rows.map((r) => r.id)).size !== rows.length) throw Error("Duplicate command rows");
  if (
    rows.some(
      (r) =>
        (query.status !== "all" && r.status !== query.status) ||
        (query.target !== "all" && r.target !== query.target),
    )
  )
    throw Error("Command rows contradict filters");
  if (m.targets_limited && m.targets.length !== 200) throw Error("Invalid limited targets");
  const f = object(m.focus, ["status", "row"]);
  if (f.status === "ready") {
    if (!query.focus_command_id || observation(f.row).id !== query.focus_command_id)
      throw Error("Invalid command focus");
    const visible = rows.find((row) => row.id === query.focus_command_id);
    if (visible && canonical(visible) !== canonical(f.row))
      throw Error("Conflicting command focus");
  } else if (f.row !== null || f.status !== (query.focus_command_id ? "not_found" : "not_selected"))
    throw Error("Invalid command focus state");
  if (f.status === "not_found" && rows.some((r) => r.id === query.focus_command_id))
    throw Error("Visible command cannot have missing focus");
  if (new TextEncoder().encode(JSON.stringify(value)).length > 524288)
    throw Error("Command model too large");
  return value as CommandMonitorModel;
}
