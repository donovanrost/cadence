import { record, oneOf, type Snapshot } from "@cadence/plugin-sdk/admission";
import type {
  PlanAction,
  PlanDetail,
  PlanDetailPort,
  PlanInputs,
  PlanResults,
} from "./OpsContactPlanShow.contracts";
import { admitPlanDetail, completedReceipt, planDecision } from "./plan-detail";

export const planReviewActions = [
  "submit-plan",
  "approve-plan",
  "reject-plan",
  "execute-plan",
] as const;
export const sameReviewData = (a: unknown, b: unknown): boolean => {
  if (a === b) return true;
  if (!a || !b || typeof a !== "object" || typeof b !== "object") return false;
  const left: Record<string, unknown> = Object.fromEntries(Object.entries(a)),
    right: Record<string, unknown> = Object.fromEntries(Object.entries(b));
  const ak = Object.keys(left),
    bk = Object.keys(right);
  return (
    ak.length === bk.length &&
    ak.every((k) => Object.hasOwn(right, k) && sameReviewData(left[k], right[k]))
  );
};
const id = (v: unknown): v is string =>
  typeof v === "string" &&
  v.length > 0 &&
  new TextEncoder().encode(v).length <= 240 &&
  v.split("").every((c) => c.charCodeAt(0) > 32 && c.charCodeAt(0) !== 127);
export const reviewFeedback = {
  forbidden: "Your current authority does not permit this decision.",
  review_changed: "This decision could not be applied to the reviewed plan. Refresh its evidence.",
  invalid_input: "Review the decision input before continuing.",
};
export type ReviewOperation = {
  [A in PlanAction]: Snapshot<
    {
      sequence: number;
      action: A;
      input: PlanInputs[A];
    } & (
      | {
          status: "completed";
          receipt: {
            receiptId: string;
            completedAt: string;
            result: PlanResults[A] & {
              contract_version: 1;
              actor_id: string;
              organization_id: string;
              mission_id: string;
              action: A;
              version: number;
              contentSha256: string;
            };
          };
        }
      | { status: "rejected"; receipt: null; feedback: (keyof typeof reviewFeedback)[] }
      | { status: "unconfirmed"; receipt: null }
    )
  >;
}[PlanAction];
export type ReviewCompletion = Extract<ReviewOperation, { status: "completed" }>;
export type PlanReviewPage = Snapshot<{
  detail: PlanDetail;
  actor_id: string;
  sequence: number;
  operation: ReviewOperation | null;
}>;

export function admitReviewOperation(
  value: unknown,
  d: PlanDetail,
  actor: string,
): ReviewOperation | null {
  return validReviewOperation(value, d, actor) ? value : null;
}
function validReviewOperation(
  value: unknown,
  d: PlanDetail,
  actor: string,
): value is ReviewOperation {
  try {
    if (
      !record(value) ||
      typeof value.sequence !== "number" ||
      !Number.isSafeInteger(value.sequence) ||
      value.sequence < 1 ||
      value.sequence > 1000000 ||
      !oneOf(planReviewActions, value.action)
    )
      return false;
    const action = value.action,
      input = value.input;
    if (!record(input)) return false;
    const wrapper = input[action === "submit-plan" ? "submission" : "decision"];
    const reason = action === "execute-plan" ? "" : record(wrapper) ? wrapper.reason : undefined;
    if (
      typeof reason !== "string" ||
      (action !== "execute-plan" &&
        (!reason.trim() || new TextEncoder().encode(reason).length > 4096))
    )
      return false;
    if (!sameReviewData(input, planDecision(d, action, reason))) return false;
    if (value.status === "completed") {
      if (!completedReceipt(value.receipt, d, action)) return false;
      const r: unknown = value.receipt.result;
      if (!record(r)) return false;
      if (
        r.contract_version !== 1 ||
        r.actor_id !== actor ||
        r.organization_id !== d.context.organization_id ||
        r.mission_id !== d.context.mission_id ||
        r.action !== action ||
        r.version !== d.plan.version ||
        r.contentSha256 !== d.plan.content_sha256
      )
        return false;
    } else if (value.receipt !== null) return false;
    else if (value.status === "rejected") {
      if (
        !Array.isArray(value.feedback) ||
        value.feedback.length < 1 ||
        value.feedback.length > 3 ||
        !value.feedback.every(
          (v: unknown) => typeof v === "string" && Object.hasOwn(reviewFeedback, v),
        )
      )
        return false;
    } else if (value.status !== "unconfirmed") return false;
    return true;
  } catch {
    return false;
  }
}

export function admitPlanReviewPage(
  value: unknown,
  context?: PlanDetailPort["context"],
  actor?: string,
): PlanReviewPage | null {
  try {
    const encoded = JSON.stringify(value);
    if (new TextEncoder().encode(encoded).length > 280000) return null;
    const v: unknown = JSON.parse(encoded);
    if (
      !record(v) ||
      !id(v.actor_id) ||
      (actor !== undefined && actor !== v.actor_id) ||
      typeof v.sequence !== "number" ||
      !Number.isSafeInteger(v.sequence) ||
      v.sequence < 0 ||
      v.sequence > 1000000
    )
      return null;
    const detail = admitPlanDetail(v.detail, context);
    if (!detail) return null;
    if (v.operation === null)
      return v.sequence === 0
        ? { detail, actor_id: v.actor_id, sequence: 0, operation: null }
        : null;
    const operation = admitReviewOperation(v.operation, detail, v.actor_id);
    return operation && operation.sequence === v.sequence
      ? { detail, actor_id: v.actor_id, sequence: v.sequence, operation }
      : null;
  } catch {
    return null;
  }
}
