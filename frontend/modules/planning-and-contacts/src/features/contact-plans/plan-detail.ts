import { record, oneOf, arrayOf, type Guard } from "@cadence/plugin-sdk/admission";
import {
  pageKeys,
  type PlanAction,
  type PlanDetail,
  type PlanDetailPort,
  type PageKey,
  type Approval,
  type Version,
  type Opportunity,
  type Execution,
  type Requirement,
  type Issue,
  type ResultPage,
  type PlanInputs,
  type PlanRequest,
  type PlanPageRequest,
  type PlanReceipt,
} from "./OpsContactPlanShow.contracts";
const text = (v: unknown, max = 512): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
// oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
const id = (v: unknown): v is string => text(v, 240) && v.length > 0 && !/[\x00-\x20\x7f]/.test(v);
const number = (v: unknown, max = Number.MAX_SAFE_INTEGER): v is number =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= max;
const version = (v: unknown): v is number => number(v, 2147483647) && v > 0;
const hash = (v: unknown) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const time = (v: unknown): v is string =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const optionalId = (v: unknown): v is string | null => v === null || id(v);
const optionalVersion = (v: unknown): v is number | null => v === null || version(v);
const approval = (v: unknown): v is Approval =>
  record(v) &&
  id(v.id) &&
  version(v.version) &&
  hash(v.content_sha256) &&
  oneOf(["approved", "rejected"], v.decision) &&
  text(v.reason, 8192) &&
  id(v.actor_id) &&
  oneOf(["user", "service"], v.actor_kind) &&
  time(v.decided_at);
const page = <T extends { readonly id: string }>(
  v: unknown,
  check: Guard<T>,
  identity: (v: T) => string = (v) => v.id,
): v is ResultPage<T> =>
  record(v) &&
  number(v.page, 1000000) &&
  v.page > 0 &&
  typeof v.more === "boolean" &&
  arrayOf(v.entries, check) &&
  v.entries.length <= 25 &&
  (!v.more || v.entries.length === 25) &&
  new Set(v.entries.map(identity)).size === v.entries.length;
export function admitPlanDetail(
  value: unknown,
  context?: PlanDetailPort["context"],
): PlanDetail | null {
  return validPlanDetail(value, context) ? value : null;
}
function validPlanDetail(value: unknown, context?: PlanDetailPort["context"]): value is PlanDetail {
  try {
    if (
      !record(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 262144 ||
      value.contract_version !== 1
    )
      return false;
    const { plan: p, context: c, permissions, query: q } = value;
    if (!record(c) || !id(c.organization_id) || !id(c.mission_id) || !record(p) || !id(p.id))
      return false;
    if (
      context &&
      (c.organization_id !== context.organization_id ||
        c.mission_id !== context.mission_id ||
        (context.plan_id !== undefined && p.id !== context.plan_id))
    )
      return false;
    if (
      !version(p.version) ||
      !version(p.current_version) ||
      p.version > p.current_version ||
      !hash(p.content_sha256) ||
      !time(p.created_at) ||
      !text(p.rationale, 8192)
    )
      return false;
    if (
      !oneOf(
        [
          "draft",
          "pending_approval",
          "approved",
          "executing",
          "partially_reserved",
          "reserved",
          "failed",
          "canceled",
          "superseded",
        ],
        p.lifecycle_state,
      )
    )
      return false;
    if (
      !optionalVersion(p.approved_version) ||
      (p.approved_version !== null && p.approved_version > p.current_version)
    )
      return false;
    if (
      p.reviewed_decision !== null &&
      (!approval(p.reviewed_decision) ||
        p.reviewed_decision.version !== p.version ||
        p.reviewed_decision.content_sha256 !== p.content_sha256)
    )
      return false;
    if (![p.selected_count, p.locked_count, p.rejected_count].every((v) => number(v))) return false;
    if (
      ![p.coverage_satisfied, p.conflicts_clear, p.unsatisfied_clear, p.manual_review].every(
        (v) => typeof v === "boolean",
      )
    )
      return false;
    if (
      !record(permissions) ||
      typeof permissions.operate !== "boolean" ||
      typeof permissions.decide !== "boolean"
    )
      return false;
    if (!record(q) || q.contact_plan_id !== p.id || q.version !== p.version) return false;
    const reviewedVersion = p.version;
    if (
      !page(
        value.versions,
        (v): v is Version =>
          record(v) &&
          id(v.id) &&
          version(v.version) &&
          v.version <= reviewedVersion &&
          hash(v.content_sha256) &&
          time(v.created_at),
      )
    )
      return false;
    if (!page(value.approvals, (v): v is Approval => approval(v) && v.version <= reviewedVersion))
      return false;
    if (
      !page(
        value.opportunities,
        (o): o is Opportunity =>
          record(o) &&
          id(o.id) &&
          oneOf(["selected", "locked", "rejected"], o.disposition) &&
          hash(o.content_sha256) &&
          id(o.requirement_id) &&
          version(o.requirement_version) &&
          text(o.provider) &&
          text(o.station) &&
          text(o.route_key) &&
          time(o.starts_at) &&
          time(o.ends_at) &&
          time(o.expires_at) &&
          Date.parse(o.starts_at) < Date.parse(o.ends_at) &&
          typeof o.eligible === "boolean" &&
          typeof o.synthetic === "boolean" &&
          oneOf(["available", "limited", "unavailable"], o.availability) &&
          optionalId(o.provider_id) &&
          optionalVersion(o.provider_version) &&
          optionalId(o.transport_id) &&
          optionalVersion(o.transport_version),
      )
    )
      return false;
    if (
      !page(
        value.execution,
        (e): e is Execution =>
          record(e) &&
          id(e.id) &&
          e.version === p.version &&
          id(e.snapshot_id) &&
          oneOf(
            ["pending", "requesting", "reserved", "uncertain", "rejected", "failed"],
            e.state,
          ) &&
          number(e.attempts) &&
          optionalId(e.reservation_id),
      )
    )
      return false;
    if (
      !page(
        value.requirements,
        (r): r is Requirement =>
          record(r) &&
          id(r.id) &&
          version(r.version) &&
          typeof r.satisfied === "boolean" &&
          [r.selected_count, r.eligible_count, r.hard_failure_count, r.search_failure_count].every(
            (v) => number(v),
          ) &&
          text(r.approval_mode, 120),
        (r) => JSON.stringify([r.id, r.version]),
      )
    )
      return false;
    if (
      !page(
        value.issues,
        (r): r is Issue =>
          record(r) &&
          id(r.id) &&
          text(r.code, 120) &&
          optionalId(r.requirement_id) &&
          optionalVersion(r.requirement_version) &&
          text(r.message) &&
          arrayOf(r.snapshot_ids, id) &&
          r.snapshot_ids.length <= 2,
      )
    )
      return false;
    for (const [key, collection] of Object.entries({
      versions_page: value.versions,
      approvals_page: value.approvals,
      opportunities_page: value.opportunities,
      execution_page: value.execution,
      requirements_page: value.requirements,
      issues_page: value.issues,
    })) {
      if (q[key] !== collection.page) return false;
    }
    return true;
  } catch {
    return false;
  }
}
export function canAct(d: PlanDetail, action: PlanAction): boolean {
  const p = d.plan;
  if (p.version !== p.current_version || !d.permissions.operate) return false;
  switch (action) {
    case "submit-plan":
      return p.lifecycle_state === "draft" && p.reviewed_decision === null;
    case "approve-plan":
      return (
        d.permissions.decide &&
        p.lifecycle_state === "pending_approval" &&
        p.reviewed_decision === null &&
        p.manual_review &&
        p.conflicts_clear &&
        p.unsatisfied_clear &&
        p.selected_count + p.locked_count > 0
      );
    case "reject-plan":
      return (
        d.permissions.decide &&
        p.lifecycle_state === "pending_approval" &&
        p.reviewed_decision === null
      );
    case "execute-plan":
      return (
        oneOf(["approved", "executing", "partially_reserved", "failed"], p.lifecycle_state) &&
        p.approved_version === p.version &&
        p.reviewed_decision?.decision === "approved"
      );
  }
}
export function planDecision<A extends PlanAction>(
  d: PlanDetail,
  action: A,
  reason: string,
): PlanInputs[A];
export function planDecision(
  d: PlanDetail,
  action: PlanAction,
  reason: string,
): PlanInputs[PlanAction] {
  const reference = {
    contact_plan_id: d.plan.id,
    plan_evidence: {
      contract_version: 1 as const,
      organization_id: d.context.organization_id,
      mission_id: d.context.mission_id,
      plan_id: d.plan.id,
      plan_version: d.plan.version,
      content_sha256: d.plan.content_sha256,
    },
  };
  if (action === "submit-plan") return { ...reference, submission: { reason: reason.trim() } };
  if (action === "approve-plan" || action === "reject-plan")
    return { ...reference, decision: { reason: reason.trim() } };
  return reference;
}
export function planRequest(d: PlanDetail, action: PlanAction, reason: string): PlanRequest {
  switch (action) {
    case "submit-plan":
      return [action, planDecision(d, action, reason)];
    case "approve-plan":
      return [action, planDecision(d, action, reason)];
    case "reject-plan":
      return [action, planDecision(d, action, reason)];
    case "execute-plan":
      return [action, planDecision(d, action, reason)];
  }
}
export function planPageRequest(
  sequence: number,
  ...[action, payload]: PlanRequest
): PlanPageRequest {
  switch (action) {
    case "submit-plan":
      return [action, { sequence, payload }];
    case "approve-plan":
      return [action, { sequence, payload }];
    case "reject-plan":
      return [action, { sequence, payload }];
    case "execute-plan":
      return [action, { sequence, payload }];
  }
}
export const reviewIdentity = (d: PlanDetail) =>
  JSON.stringify([
    d.context.organization_id,
    d.context.mission_id,
    d.plan.id,
    d.plan.version,
    d.plan.content_sha256,
  ]);
export const planPath = (d: PlanDetail) =>
  `/missions/${encodeURIComponent(d.context.mission_id)}/ops/plans/${encodeURIComponent(d.plan.id)}`;
export function reviewHref(
  d: PlanDetail,
  versionNumber = d.plan.version,
  key?: PageKey,
  pageNumber?: number,
) {
  const params = new URLSearchParams({ version: String(versionNumber) });
  if (versionNumber === d.plan.version)
    for (const p of pageKeys) if (d.query[p] !== 1) params.set(p, String(d.query[p]));
  if (key && pageNumber) params.set(key, String(pageNumber));
  return planPath(d) + "?" + params;
}
export function completedReceipt<A extends PlanAction>(
  value: unknown,
  d: PlanDetail,
  action: A,
): value is PlanReceipt<A> {
  if (!record(value) || !id(value.receiptId) || !time(value.completedAt) || !record(value.result))
    return false;
  const r = value.result;
  if (r.contactPlanId !== d.plan.id) return false;
  return action === "execute-plan"
    ? number(r.executionItemCount) &&
        oneOf(
          ["approved", "executing", "partially_reserved", "reserved", "failed"],
          r.lifecycleState,
        )
    : r.version === d.plan.version && r.contentSha256 === d.plan.content_sha256;
}
