import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
export type Actor = Partial<
  Record<"actor_kind" | "user_id" | "service_identity_id" | "kind" | "id" | "display_name", string>
>;
export type Request = {
  command_request_id: string;
  source_endpoint_ref: string;
  mission_model_revision_id: string;
  command_id: string;
  command_name: string | null;
  command_display_name: string | null;
  lifecycle_state: string;
  verification_state: string | null;
  priority: number;
  source_command_stage_id: string | null;
  source_staged_command_item_id: string | null;
  significance: string | null;
  critical: boolean;
  hazardous: boolean;
  subsystem: string | null;
  group_name: string | null;
  preferred_uplink_service: string | null;
  release_policy_hint: string | null;
  apid: number | null;
  service_type: number | null;
  service_subtype: number | null;
  requested_by: Actor;
  requested_at: string;
  not_before: string | null;
  expires_at: string | null;
  argument_values_json: string;
  resolved_argument_values_json: string;
  opcode_json: string;
};
export type Queue = {
  id: string;
  request_id: string;
  target_id: string;
  lane: string;
  sequence: string;
  priority: number;
  state: "pending" | "release_pending" | "released" | "canceled";
  enqueued_at: string;
  actor: Actor;
  not_before: string | null;
  expires_at: string | null;
};
export type Preview = {
  token: string;
  operation_id: string;
  actor_id: string;
  request: Request;
  approval: { id: string; basis_sha256: string; actor: Actor; decided_at: string };
};
export type Receipt = {
  operation_id: string;
  queue_id: string;
  request_id: string;
  actor_id: string;
  enqueued_at: string;
  approved_content_sha256: string;
};
export type Operation =
  | { status: "unconfirmed" }
  | { status: "rejected"; feedback: string }
  | { status: "completed"; receipt: Receipt };
export type QueuePage = {
  model: {
    version: 1;
    context: OpsPageContext;
    mission_name: string;
    actor_id: string;
    observed_at: string;
    request: Request;
    queue: Queue | null;
    availability: "available" | "queued" | "approval_required" | "expired" | "closed";
  };
  preview: Preview | null;
  operation: Operation | null;
};
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const keys = (v: Record<string, unknown>, names: readonly string[]) =>
  Object.keys(v).length === names.length && names.every((k) => Object.hasOwn(v, k));
const text = (v: unknown, max = 2000): v is string =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v);
const id = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 120 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
const hash = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
const token = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v);
const integer = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const actor = (v: unknown): v is Actor =>
  record(v) &&
  Object.entries(v).every(
    ([k, x]) =>
      ["actor_kind", "user_id", "service_identity_id", "kind", "id", "display_name"].includes(k) &&
      text(x),
  );
const nullable = (v: unknown, check: (x: unknown) => boolean) => v === null || check(v);
const jsonText = (v: unknown, object = false): v is string => {
  if (!text(v, 131072)) return false;
  try {
    const parsed: unknown = JSON.parse(v);
    return !object || record(parsed);
  } catch {
    return false;
  }
};
const requestFields = [
  "command_request_id",
  "source_endpoint_ref",
  "mission_model_revision_id",
  "command_id",
  "command_name",
  "command_display_name",
  "lifecycle_state",
  "verification_state",
  "priority",
  "source_command_stage_id",
  "source_staged_command_item_id",
  "significance",
  "critical",
  "hazardous",
  "subsystem",
  "group_name",
  "preferred_uplink_service",
  "release_policy_hint",
  "apid",
  "service_type",
  "service_subtype",
  "requested_by",
  "requested_at",
  "not_before",
  "expires_at",
  "argument_values_json",
  "resolved_argument_values_json",
  "opcode_json",
] as const;
const request = (v: unknown): v is Request =>
  record(v) &&
  keys(v, requestFields) &&
  ["command_request_id", "source_endpoint_ref", "mission_model_revision_id", "command_id"].every(
    (k) => id(v[k]),
  ) &&
  [
    "command_name",
    "command_display_name",
    "verification_state",
    "significance",
    "subsystem",
    "group_name",
    "preferred_uplink_service",
    "release_policy_hint",
  ].every((k) => nullable(v[k], text)) &&
  ["source_command_stage_id", "source_staged_command_item_id"].every((k) => nullable(v[k], id)) &&
  ["apid", "service_type", "service_subtype"].every((k) => nullable(v[k], integer)) &&
  text(v.lifecycle_state, 80) &&
  integer(v.priority) &&
  typeof v.critical === "boolean" &&
  typeof v.hazardous === "boolean" &&
  actor(v.requested_by) &&
  time(v.requested_at) &&
  nullable(v.not_before, time) &&
  nullable(v.expires_at, time) &&
  jsonText(v.argument_values_json, true) &&
  jsonText(v.resolved_argument_values_json, true) &&
  jsonText(v.opcode_json);
const sequence = (v: unknown): v is string =>
  typeof v === "string" && /^[1-9][0-9]{0,18}$/.test(v) && BigInt(v) <= 9223372036854775807n;
const queue = (v: unknown): v is Queue =>
  record(v) &&
  keys(v, [
    "id",
    "request_id",
    "target_id",
    "lane",
    "sequence",
    "priority",
    "state",
    "enqueued_at",
    "actor",
    "not_before",
    "expires_at",
  ]) &&
  [v.id, v.request_id, v.target_id, v.lane].every(id) &&
  sequence(v.sequence) &&
  integer(v.priority) &&
  ["pending", "release_pending", "released", "canceled"].includes(String(v.state)) &&
  time(v.enqueued_at) &&
  actor(v.actor) &&
  nullable(v.not_before, time) &&
  nullable(v.expires_at, time);
const approvalId = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 132 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
const preview = (v: unknown): v is Preview =>
  record(v) &&
  keys(v, ["token", "operation_id", "actor_id", "request", "approval"]) &&
  token(v.token) &&
  id(v.operation_id) &&
  id(v.actor_id) &&
  request(v.request) &&
  record(v.approval) &&
  keys(v.approval, ["id", "basis_sha256", "actor", "decided_at"]) &&
  approvalId(v.approval.id) &&
  hash(v.approval.basis_sha256) &&
  actor(v.approval.actor) &&
  time(v.approval.decided_at);
const sameRequest = (a: Request, b: Request) =>
  requestFields.every((k) =>
    k === "requested_by"
      ? JSON.stringify(Object.entries(a.requested_by).sort(([a], [b]) => a.localeCompare(b))) ===
        JSON.stringify(Object.entries(b.requested_by).sort(([a], [b]) => a.localeCompare(b)))
      : a[k] === b[k],
  );
const fail = (): never => {
  throw Error("Unavailable command queue data");
};
export function readOperation(value: unknown, expected: Preview): Operation {
  if (!record(value)) return fail();
  if (value.status === "unconfirmed" && keys(value, ["status"])) return { status: "unconfirmed" };
  if (value.status === "rejected" && keys(value, ["status", "feedback"]) && text(value.feedback))
    return { status: "rejected", feedback: value.feedback };
  const r = value.receipt;
  if (
    value.status !== "completed" ||
    !keys(value, ["status", "receipt"]) ||
    !record(r) ||
    !keys(r, [
      "operation_id",
      "queue_id",
      "request_id",
      "actor_id",
      "enqueued_at",
      "approved_content_sha256",
    ]) ||
    r.operation_id !== expected.operation_id ||
    r.actor_id !== expected.actor_id ||
    r.request_id !== expected.request.command_request_id ||
    r.approved_content_sha256 !== expected.approval.basis_sha256 ||
    !id(r.queue_id) ||
    !time(r.enqueued_at)
  )
    return fail();
  return { status: "completed", receipt: r as Receipt };
}
export function readQueuePage(value: unknown, context: OpsPageContext): QueuePage {
  if (
    !record(value) ||
    !keys(value, ["model", "preview", "operation"]) ||
    new TextEncoder().encode(JSON.stringify(value)).length > 262144
  )
    return fail();
  const m = value.model,
    p = value.preview;
  if (
    !record(m) ||
    !keys(m, [
      "version",
      "context",
      "mission_name",
      "actor_id",
      "observed_at",
      "request",
      "queue",
      "availability",
    ]) ||
    m.version !== 1 ||
    !record(m.context) ||
    !keys(m.context, ["organizationId", "missionId", "resourceId"]) ||
    !id(context.resourceId) ||
    m.context.organizationId !== context.organizationId ||
    m.context.missionId !== context.missionId ||
    m.context.resourceId !== context.resourceId ||
    !text(m.mission_name) ||
    !id(m.actor_id) ||
    !time(m.observed_at) ||
    !request(m.request) ||
    m.request.command_request_id !== context.resourceId ||
    !nullable(m.queue, queue) ||
    !["available", "queued", "approval_required", "expired", "closed"].includes(
      String(m.availability),
    )
  )
    return fail();
  if (
    m.queue &&
    (!queue(m.queue) ||
      m.queue.request_id !== context.resourceId ||
      m.queue.target_id !== m.request.source_endpoint_ref ||
      m.queue.lane !== m.request.source_endpoint_ref)
  )
    return fail();
  if (
    !nullable(p, preview) ||
    (p &&
      (!preview(p) ||
        p.actor_id !== m.actor_id ||
        p.request.command_request_id !== context.resourceId))
  )
    return fail();
  if (
    m.availability === "available" &&
    (!p || m.queue || !["validated", "approved"].includes(m.request.lifecycle_state))
  )
    return fail();
  if (
    m.availability === "available" &&
    value.operation === null &&
    preview(p) &&
    !sameRequest(m.request, p.request)
  )
    return fail();
  if ((m.availability === "queued") !== !!m.queue) return fail();
  if (value.operation !== null && (!p || !preview(p))) return fail();
  if (value.operation !== null && p && preview(p)) {
    const operation = readOperation(value.operation, p);
    if (
      operation.status === "completed" &&
      queue(m.queue) &&
      (operation.receipt.queue_id !== m.queue.id ||
        operation.receipt.enqueued_at !== m.queue.enqueued_at ||
        operation.receipt.actor_id !== m.queue.actor.user_id)
    )
      return fail();
  }
  return JSON.parse(JSON.stringify(value)) as QueuePage;
}
export function queueInput(p: Preview): Record<string, unknown> {
  return { expected_queue: p.token };
}
export function monitorHref(context: OpsPageContext) {
  if (!context.resourceId) return fail();
  return `/missions/${encodeURIComponent(context.missionId)}/ops/commands?focus_command_id=${encodeURIComponent(context.resourceId)}`;
}
export function reviewHref(context: OpsPageContext) {
  if (!context.resourceId) return fail();
  return `/missions/${encodeURIComponent(context.missionId)}/ops/commands/requests/${encodeURIComponent(context.resourceId)}`;
}

export const queueSubmissionHref = (mission: string, request: string) =>
  `/missions/${encodeURIComponent(mission)}/ops/commands/requests/${encodeURIComponent(request)}/queue`;
