import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
export type Actor = { actor_kind?: string; user_id?: string; service_identity_id?: string };
export type Request = {
  command_request_id: string;
  source_endpoint_ref: string;
  mission_model_revision_id: string;
  command_id: string;
  command_name: string;
  command_display_name: string | null;
  lifecycle_state: string;
  verification_state: string | null;
  priority: number;
  source_command_stage_id: string | null;
  source_staged_command_item_id: string | null;
  argument_values_json: string;
  resolved_argument_values_json: string;
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
  opcode_json: string;
  requested_by: Actor;
  requested_at: string;
  not_before: string | null;
  expires_at: string | null;
};
export type Decision = "approved" | "rejected";
export type Receipt = {
  approval_id: string;
  request_id: string;
  decision: Decision;
  decided_at: string;
  actor_id: string;
};
export type Operation =
  | { status: "unconfirmed" }
  | { status: "rejected"; feedback: string }
  | { status: "completed"; receipt: Receipt };
export type CommandReviewPage = {
  review: {
    version: 1;
    context: OpsPageContext;
    mission_name: string;
    actor_id: string;
    observed_at: string;
    expected_review: string;
    request: Request;
    can_decide: boolean;
    query: { after: string };
    history: {
      limit: 25;
      entries: {
        id: string;
        decision: Decision;
        actor: Actor;
        decided_at: string;
        reason: string | null;
      }[];
      next_after: string | null;
    };
  };
  operation: Operation | null;
};
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const id = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 120 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
const text = (v: unknown, max = 2000): v is string =>
  typeof v === "string" &&
  new TextEncoder().encode(v).length <= max &&
  !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v);
const integer = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const decision = (v: unknown): v is Decision => v === "approved" || v === "rejected";
function jsonText(value: unknown, object = false): value is string {
  if (!text(value, 131072)) return false;
  try {
    const parsed: unknown = JSON.parse(value);
    return !object || record(parsed);
  } catch {
    return false;
  }
}
const actor = (v: unknown): v is Actor =>
  record(v) &&
  Object.entries(v).every(
    ([k, x]) => ["actor_kind", "user_id", "service_identity_id"].includes(k) && id(x),
  );
const fail = (): never => {
  throw Error("Unavailable command review");
};
export function commandReviewHref(mission: string, request: string, after = ""): string {
  if (!id(mission) || !id(request) || (after !== "" && !id(after))) fail();
  return `/missions/${encodeURIComponent(mission)}/ops/commands/requests/${encodeURIComponent(request)}${after ? `?after=${encodeURIComponent(after)}` : ""}`;
}
export function readOperation(value: unknown, request: string, reviewer: string): Operation {
  if (!record(value)) return fail();
  if (value.status === "unconfirmed") return { status: "unconfirmed" };
  if (value.status === "rejected" && text(value.feedback))
    return { status: "rejected", feedback: value.feedback };
  const r = value.receipt;
  if (
    value.status === "completed" &&
    record(r) &&
    id(r.approval_id) &&
    r.request_id === request &&
    r.actor_id === reviewer &&
    decision(r.decision) &&
    time(r.decided_at)
  )
    return { status: "completed", receipt: r as Receipt };
  return fail();
}
export function readCommandReviewPage(value: unknown, context: OpsPageContext): CommandReviewPage {
  if (!record(value) || new TextEncoder().encode(JSON.stringify(value)).length > 140000)
    return fail();
  const v = value.review;
  if (!record(v) || v.version !== 1 || !record(v.context)) return fail();
  for (const k of ["organizationId", "missionId", "resourceId"] as const)
    if (!id(context[k]) || v.context[k] !== context[k]) return fail();
  if (
    !text(v.mission_name) ||
    !id(v.actor_id) ||
    !time(v.observed_at) ||
    typeof v.expected_review !== "string" ||
    !/^[0-9a-f]{64}$/.test(v.expected_review) ||
    typeof v.can_decide !== "boolean"
  )
    return fail();
  const r = v.request;
  if (!record(r) || r.command_request_id !== context.resourceId) return fail();
  for (const k of ["source_endpoint_ref", "mission_model_revision_id", "command_id"])
    if (!id(r[k])) return fail();
  for (const k of ["source_command_stage_id", "source_staged_command_item_id"])
    if (!(r[k] === null || id(r[k]))) return fail();
  if (
    !text(r.command_name) ||
    !r.command_name ||
    ![
      "draft",
      "validated",
      "approval_pending",
      "approved",
      "rejected",
      "queued",
      "released",
      "canceled",
    ].includes(String(r.lifecycle_state))
  )
    return fail();
  if (
    !(
      r.verification_state === null ||
      ["not_required", "pending", "satisfied", "failed", "timed_out"].includes(
        String(r.verification_state),
      )
    ) ||
    !(
      r.significance === null ||
      ["routine", "warning", "critical", "hazardous"].includes(String(r.significance))
    )
  )
    return fail();
  for (const k of [
    "command_display_name",
    "subsystem",
    "group_name",
    "preferred_uplink_service",
    "release_policy_hint",
  ])
    if (!(r[k] === null || text(r[k]))) return fail();
  for (const k of ["apid", "service_type", "service_subtype"])
    if (!(r[k] === null || integer(r[k]))) return fail();
  if (
    !integer(r.priority) ||
    typeof r.critical !== "boolean" ||
    typeof r.hazardous !== "boolean" ||
    !actor(r.requested_by) ||
    !time(r.requested_at)
  )
    return fail();
  if (
    ![r.not_before, r.expires_at].every((x) => x === null || time(x)) ||
    !jsonText(r.argument_values_json, true) ||
    !jsonText(r.resolved_argument_values_json, true) ||
    !jsonText(r.opcode_json)
  )
    return fail();
  if (
    v.can_decide !==
    (r.lifecycle_state === "approval_pending" && r.requested_by.user_id !== v.actor_id)
  )
    return fail();
  if (!record(v.query) || !(v.query.after === "" || id(v.query.after))) return fail();
  const h = v.history;
  if (
    !record(h) ||
    h.limit !== 25 ||
    !Array.isArray(h.entries) ||
    h.entries.length > 25 ||
    !(h.next_after === null || id(h.next_after))
  )
    return fail();
  let previous = v.query.after;
  for (const e of h.entries) {
    if (
      !record(e) ||
      !id(e.id) ||
      e.id <= previous ||
      !decision(e.decision) ||
      !actor(e.actor) ||
      !time(e.decided_at) ||
      !(e.reason === null || text(e.reason))
    )
      return fail();
    previous = e.id;
  }
  if (h.next_after !== null && (h.entries.length !== 25 || h.next_after !== previous))
    return fail();
  if (value.operation !== null) readOperation(value.operation, context.resourceId!, v.actor_id);
  return value as unknown as CommandReviewPage;
}
export function decisionInput(decisionValue: unknown, reason: unknown, review: string) {
  if (!decision(decisionValue) || !text(reason)) return fail();
  return { decision: decisionValue, reason: reason.trim(), expected_review: review };
}
