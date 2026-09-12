import {
  pageKeys,
  type PlanAction,
  type PlanDetail,
  type PlanDetailPort,
  type PageKey,
} from "./OpsContactPlanShow.contracts";
const record = (v: unknown): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const text = (v: unknown, max = 512): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
const id = (v: unknown): v is string => text(v, 240) && v.length > 0 && !/[\x00-\x20\x7f]/.test(v);
const number = (v: unknown, max = Number.MAX_SAFE_INTEGER): v is number =>
  Number.isSafeInteger(v) && (v as number) >= 0 && (v as number) <= max;
const version = (v: unknown): v is number => number(v, 2147483647) && v > 0;
const hash = (v: unknown) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const time = (v: unknown) =>
  text(v, 40) &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const optionalId = (v: unknown) => v === null || id(v);
const optionalVersion = (v: unknown) => v === null || version(v);
const approval = (v: any) =>
  record(v) &&
  id(v.id) &&
  version(v.version) &&
  hash(v.content_sha256) &&
  ["approved", "rejected"].includes(v.decision) &&
  text(v.reason, 8192) &&
  id(v.actor_id) &&
  ["user", "service"].includes(v.actor_kind) &&
  time(v.decided_at);
const page = (v: any, check: (v: any) => boolean, identity = (v: any) => v.id) =>
  record(v) &&
  number(v.page, 1000000) &&
  v.page > 0 &&
  typeof v.more === "boolean" &&
  Array.isArray(v.entries) &&
  v.entries.length <= 25 &&
  (!v.more || v.entries.length === 25) &&
  v.entries.every(check) &&
  new Set(v.entries.map(identity)).size === v.entries.length;
export function admitPlanDetail(
  value: unknown,
  context?: PlanDetailPort["context"],
): PlanDetail | null {
  try {
    if (
      !record(value) ||
      new TextEncoder().encode(JSON.stringify(value)).length > 262144 ||
      value.contract_version !== 1
    )
      return null;
    const { plan: p, context: c, permissions, query: q } = value;
    if (!record(c) || !id(c.organization_id) || !id(c.mission_id) || !record(p) || !id(p.id))
      return null;
    if (
      context &&
      (c.organization_id !== context.organization_id ||
        c.mission_id !== context.mission_id ||
        (context.plan_id !== undefined && p.id !== context.plan_id))
    )
      return null;
    if (
      !version(p.version) ||
      !version(p.current_version) ||
      p.version > p.current_version ||
      !hash(p.content_sha256) ||
      !time(p.created_at) ||
      !text(p.rationale, 8192)
    )
      return null;
    if (
      ![
        "draft",
        "pending_approval",
        "approved",
        "executing",
        "partially_reserved",
        "reserved",
        "failed",
        "canceled",
        "superseded",
      ].includes(p.lifecycle_state)
    )
      return null;
    if (
      !optionalVersion(p.approved_version) ||
      (p.approved_version !== null && p.approved_version > p.current_version)
    )
      return null;
    if (
      p.reviewed_decision !== null &&
      (!approval(p.reviewed_decision) ||
        p.reviewed_decision.version !== p.version ||
        p.reviewed_decision.content_sha256 !== p.content_sha256)
    )
      return null;
    if (![p.selected_count, p.locked_count, p.rejected_count].every((v) => number(v))) return null;
    if (
      ![p.coverage_satisfied, p.conflicts_clear, p.unsatisfied_clear, p.manual_review].every(
        (v) => typeof v === "boolean",
      )
    )
      return null;
    if (
      !record(permissions) ||
      typeof permissions.operate !== "boolean" ||
      typeof permissions.decide !== "boolean"
    )
      return null;
    if (!record(q) || q.contact_plan_id !== p.id || q.version !== p.version) return null;
    if (
      !page(
        value.versions,
        (v) =>
          record(v) &&
          id(v.id) &&
          version(v.version) &&
          v.version <= p.version &&
          hash(v.content_sha256) &&
          time(v.created_at),
      )
    )
      return null;
    if (!page(value.approvals, (v) => approval(v) && v.version <= p.version)) return null;
    if (
      !page(
        value.opportunities,
        (o) =>
          record(o) &&
          id(o.id) &&
          ["selected", "locked", "rejected"].includes(o.disposition) &&
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
          ["available", "limited", "unavailable"].includes(o.availability) &&
          optionalId(o.provider_id) &&
          optionalVersion(o.provider_version) &&
          optionalId(o.transport_id) &&
          optionalVersion(o.transport_version),
      )
    )
      return null;
    if (
      !page(
        value.execution,
        (e) =>
          record(e) &&
          id(e.id) &&
          e.version === p.version &&
          id(e.snapshot_id) &&
          ["pending", "requesting", "reserved", "uncertain", "rejected", "failed"].includes(
            e.state,
          ) &&
          number(e.attempts) &&
          optionalId(e.reservation_id),
      )
    )
      return null;
    if (
      !page(
        value.requirements,
        (r) =>
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
      return null;
    if (
      !page(
        value.issues,
        (r) =>
          record(r) &&
          id(r.id) &&
          text(r.code, 120) &&
          optionalId(r.requirement_id) &&
          optionalVersion(r.requirement_version) &&
          text(r.message) &&
          Array.isArray(r.snapshot_ids) &&
          r.snapshot_ids.length <= 2 &&
          r.snapshot_ids.every(id),
      )
    )
      return null;
    for (const key of pageKeys) {
      const collection = key.slice(0, -5);
      if (q[key] !== value[collection].page) return null;
    }
    return value as PlanDetail;
  } catch {
    return null;
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
        ["approved", "executing", "partially_reserved", "failed"].includes(p.lifecycle_state) &&
        p.approved_version === p.version &&
        p.reviewed_decision?.decision === "approved"
      );
  }
}
export function planDecision(
  d: PlanDetail,
  action: PlanAction,
  reason: string,
): Record<string, unknown> {
  const input: Record<string, unknown> = {
    contact_plan_id: d.plan.id,
    plan_evidence: {
      contract_version: 1,
      organization_id: d.context.organization_id,
      mission_id: d.context.mission_id,
      plan_id: d.plan.id,
      plan_version: d.plan.version,
      content_sha256: d.plan.content_sha256,
    },
  };
  if (action !== "execute-plan")
    input[action === "submit-plan" ? "submission" : "decision"] = { reason: reason.trim() };
  return input;
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
export function completedReceipt(value: unknown, d: PlanDetail, action: PlanAction) {
  if (!record(value) || !id(value.receiptId) || !time(value.completedAt) || !record(value.result))
    return false;
  const r = value.result;
  if (r.contactPlanId !== d.plan.id) return false;
  return action === "execute-plan"
    ? number(r.executionItemCount) &&
        ["approved", "executing", "partially_reserved", "reserved", "failed"].includes(
          r.lifecycleState,
        )
    : r.version === d.plan.version && r.contentSha256 === d.plan.content_sha256;
}
