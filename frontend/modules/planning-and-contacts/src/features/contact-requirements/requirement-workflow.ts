import type { RequirementDetail } from "./OpsContactRequirementShow.contracts";
import { admitRequirementDetail } from "./requirement-detail";
import {
  record,
  safeId,
  validTime,
  natural,
  positive,
  requirementDataEqual,
  requirementSegment,
} from "./requirement-directory";
export type RequirementAction = "plan" | "create-plan";
export type RequirementOperation = {
  sequence: number;
  action: RequirementAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  receipt: null | { receiptId: string; completedAt: string; result: Record<string, any> };
};
export type RequirementPage = {
  detail: RequirementDetail;
  sequence: number;
  operation: RequirementOperation | null;
};
export type RequirementContext = RequirementDetail["context"] & { requirement_id: string };
const hash = (v: unknown) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
function evidence(v: any, c: RequirementContext) {
  return (
    record(v) &&
    Object.keys(v).length === 6 &&
    v.contract_version === 1 &&
    v.organization_id === c.organization_id &&
    v.mission_id === c.mission_id &&
    v.requirement_id === c.requirement_id &&
    positive(v.requirement_version) &&
    hash(v.content_sha256)
  );
}
function receiptResult(op: Record<string, any>, c: RequirementContext) {
  const input = op.input,
    r = op.receipt.result,
    e = input.requirement_evidence;
  if (
    !record(r) ||
    input.contact_requirement_id !== c.requirement_id ||
    !evidence(e, c) ||
    !record(r.navigation)
  )
    return false;
  const base = `/missions/${requirementSegment(c.mission_id)}/ops/`;
  if (op.action === "plan")
    return (
      r.contactRequirementId === c.requirement_id &&
      safeId(r.planningRunId) &&
      natural(r.searchCount) &&
      natural(r.opportunityCount) &&
      r.navigation.href ===
        base +
          `requirements/${requirementSegment(c.requirement_id)}?` +
          new URLSearchParams({
            planning_run_id: r.planningRunId,
            version: String(e.requirement_version),
          }).toString()
    );
  return (
    safeId(r.contactPlanId) &&
    positive(r.version) &&
    hash(r.contentSha256) &&
    r.actorId === c.actor_id &&
    safeId(input.planning_run_id) &&
    r.planningRunId === input.planning_run_id &&
    requirementDataEqual(r.requirementEvidence, e) &&
    r.navigation.href === base + `plans/${requirementSegment(r.contactPlanId)}`
  );
}
export function admitRequirementOperation(
  v: unknown,
  c: RequirementContext,
): RequirementOperation | null {
  if (
    !record(v) ||
    !positive(v.sequence) ||
    v.sequence > 1000000 ||
    !["plan", "create-plan"].includes(v.action) ||
    !record(v.input) ||
    !["completed", "rejected", "unconfirmed"].includes(v.status)
  )
    return null;
  if (v.status !== "completed") return v.receipt === null ? (v as RequirementOperation) : null;
  if (
    !record(v.receipt) ||
    !safeId(v.receipt.receiptId) ||
    !validTime(v.receipt.completedAt) ||
    !receiptResult(v, c)
  )
    return null;
  return v as RequirementOperation;
}
export function requirementContext(d: RequirementDetail): RequirementContext {
  return { ...d.context, requirement_id: d.requirement.id };
}
export function admitRequirementPage(
  input: unknown,
  context?: Partial<RequirementContext>,
  query?: RequirementDetail["query"],
): RequirementPage | null {
  try {
    const s = JSON.stringify(input);
    if (new TextEncoder().encode(s).length > 131072) return null;
    const v = JSON.parse(s);
    if (!record(v)) return null;
    const d = admitRequirementDetail(v.detail);
    if (
      !d ||
      !safeId(d.context.actor_id) ||
      !natural(v.sequence) ||
      v.sequence > 1000000 ||
      (query && !requirementDataEqual(d.query, query))
    )
      return null;
    const c = requirementContext(d);
    if (
      context &&
      Object.entries(context).some(([k, value]) => c[k as keyof RequirementContext] !== value)
    )
      return null;
    if (v.operation === null)
      return v.sequence === 0 ? ({ ...v, detail: d } as RequirementPage) : null;
    const op = admitRequirementOperation(v.operation, c);
    return op && op.sequence === v.sequence
      ? { detail: d, sequence: v.sequence, operation: op }
      : null;
  } catch {
    return null;
  }
}
