import type { PlanAction, PlanDetail, PlanDetailPort } from "./OpsContactPlanShow.contracts";
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
  const ak = Object.keys(a),
    bk = Object.keys(b);
  return (
    ak.length === bk.length &&
    ak.every((k) => Object.hasOwn(b, k) && sameReviewData((a as any)[k], (b as any)[k]))
  );
};
const record = (v: any): v is Record<string, any> =>
  !!v && typeof v === "object" && !Array.isArray(v);
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
  sequence: number;
  action: PlanAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  feedback?: (keyof typeof reviewFeedback)[];
  receipt: null | { receiptId: string; completedAt: string; result: Record<string, any> };
};
export type PlanReviewPage = {
  detail: PlanDetail;
  actor_id: string;
  sequence: number;
  operation: ReviewOperation | null;
};

export function admitReviewOperation(
  value: unknown,
  d: PlanDetail,
  actor: string,
): ReviewOperation | null {
  try {
    if (
      !record(value) ||
      !Number.isSafeInteger(value.sequence) ||
      value.sequence < 1 ||
      value.sequence > 1000000 ||
      !planReviewActions.includes(value.action)
    )
      return null;
    const action = value.action as PlanAction,
      input = value.input;
    if (!record(input)) return null;
    const reason =
      action === "execute-plan"
        ? ""
        : input[action === "submit-plan" ? "submission" : "decision"]?.reason;
    if (
      typeof reason !== "string" ||
      (action !== "execute-plan" &&
        (!reason.trim() || new TextEncoder().encode(reason).length > 4096))
    )
      return null;
    if (!sameReviewData(input, planDecision(d, action, reason))) return null;
    if (value.status === "completed") {
      if (!completedReceipt(value.receipt, d, action)) return null;
      const r = value.receipt.result;
      if (
        r.contract_version !== 1 ||
        r.actor_id !== actor ||
        r.organization_id !== d.context.organization_id ||
        r.mission_id !== d.context.mission_id ||
        r.action !== action ||
        r.version !== d.plan.version ||
        r.contentSha256 !== d.plan.content_sha256
      )
        return null;
    } else if (value.receipt !== null) return null;
    else if (value.status === "rejected") {
      if (
        !Array.isArray(value.feedback) ||
        value.feedback.length < 1 ||
        value.feedback.length > 3 ||
        !value.feedback.every(
          (v: unknown) => typeof v === "string" && Object.hasOwn(reviewFeedback, v),
        )
      )
        return null;
    } else if (value.status !== "unconfirmed") return null;
    return value as ReviewOperation;
  } catch {
    return null;
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
    const v = JSON.parse(encoded);
    if (
      !record(v) ||
      !id(v.actor_id) ||
      (actor !== undefined && actor !== v.actor_id) ||
      !Number.isSafeInteger(v.sequence) ||
      v.sequence < 0 ||
      v.sequence > 1000000
    )
      return null;
    const detail = admitPlanDetail(v.detail, context);
    if (!detail) return null;
    if (v.operation === null) return v.sequence === 0 ? ({ ...v, detail } as PlanReviewPage) : null;
    const operation = admitReviewOperation(v.operation, detail, v.actor_id);
    return operation && operation.sequence === v.sequence
      ? { detail, actor_id: v.actor_id, sequence: v.sequence, operation }
      : null;
  } catch {
    return null;
  }
}
