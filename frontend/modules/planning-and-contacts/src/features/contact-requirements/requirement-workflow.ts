import { arrayOf, oneOf, type Snapshot } from "@cadence/plugin-sdk/admission";
import type {
  RequirementDetail,
  Evidence,
  PlanInput,
  CreatePlanInput,
} from "./OpsContactRequirementShow.contracts";
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
export type RequirementInputs = { plan: PlanInput; "create-plan": CreatePlanInput };
export type RequirementAction = keyof RequirementInputs;
export type RequirementResults = {
  plan: {
    contactRequirementId: string;
    planningRunId: string;
    searchCount: number;
    opportunityCount: number;
    navigation: { href: string };
  };
  "create-plan": {
    contactPlanId: string;
    version: number;
    contentSha256: string;
    actorId: string | null;
    planningRunId: string;
    requirementEvidence: Evidence;
    navigation: { href: string };
  };
};
export type RequirementCommand = {
  [A in RequirementAction]: Snapshot<{ action: A; input: RequirementInputs[A] }>;
}[RequirementAction];
export type RequirementRequest = {
  [A in RequirementAction]: [action: A, input: RequirementInputs[A]];
}[RequirementAction];
export type RequirementOperation = {
  [A in RequirementAction]: Snapshot<
    {
      sequence: number;
      action: A;
      input: RequirementInputs[A];
    } & (
      | {
          status: "completed";
          receipt: { receiptId: string; completedAt: string; result: RequirementResults[A] };
        }
      | { status: "rejected" | "unconfirmed"; receipt: null }
    )
  >;
}[RequirementAction];
export type RequirementPage = Snapshot<{
  detail: RequirementDetail;
  sequence: number;
  operation: RequirementOperation | null;
}>;
export type RequirementContext = RequirementDetail["context"] & { readonly requirement_id: string };
const hash = (v: unknown) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
function evidence(v: unknown, c: RequirementContext): v is Evidence {
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
function receiptResult(op: RequirementCommand, r: unknown, c: RequirementContext) {
  const e = op.input.requirement_evidence;
  if (
    !record(r) ||
    op.input.contact_requirement_id !== c.requirement_id ||
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
  const input = op.input;
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
export function isRequirementCommand(
  v: unknown,
  c: RequirementContext,
): v is RequirementCommand & Record<string, unknown> {
  return (
    record(v) &&
    oneOf(["plan", "create-plan"], v.action) &&
    record(v.input) &&
    v.input.contact_requirement_id === c.requirement_id &&
    evidence(v.input.requirement_evidence, c) &&
    (v.action === "plan" ||
      (safeId(v.input.planning_run_id) && arrayOf(v.input.selected_snapshot_ids, safeId)))
  );
}
export function admitRequirementOperation(
  v: unknown,
  c: RequirementContext,
): RequirementOperation | null {
  return validRequirementOperation(v, c) ? v : null;
}
function validRequirementOperation(v: unknown, c: RequirementContext): v is RequirementOperation {
  if (
    !record(v) ||
    !positive(v.sequence) ||
    v.sequence > 1000000 ||
    !isRequirementCommand(v, c) ||
    !oneOf(["completed", "rejected", "unconfirmed"], v.status)
  )
    return false;
  if (v.status !== "completed") return v.receipt === null;
  if (
    !record(v.receipt) ||
    !safeId(v.receipt.receiptId) ||
    !validTime(v.receipt.completedAt) ||
    !receiptResult(v, v.receipt.result, c)
  )
    return false;
  return true;
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
    const v: unknown = JSON.parse(s);
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
      return v.sequence === 0 ? { detail: d, sequence: 0, operation: null } : null;
    const op = admitRequirementOperation(v.operation, c);
    return op && op.sequence === v.sequence
      ? { detail: d, sequence: v.sequence, operation: op }
      : null;
  } catch {
    return null;
  }
}
