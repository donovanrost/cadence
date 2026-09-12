import { validReviewReason } from "../../shared/workflow-protocol";
import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type {
  PlanAction,
  PlanDetailPort,
  PlanDetail,
  PlanRequest,
} from "./OpsContactPlanShow.contracts";
import { canAct, planRequest, planPageRequest, reviewIdentity } from "./plan-detail";
import {
  admitPlanReviewPage,
  admitReviewOperation,
  reviewFeedback,
  sameReviewData as equal,
  type ReviewOperation,
  type ReviewCompletion,
} from "./plan-review";

export function usePlanPageWorkflow(
  input: () => unknown,
  port: Extract<PlanDetailPort, { protocol: "page-snapshot" }>,
) {
  const initial = admitPlanReviewPage(input(), port.context, port.actorId);
  const detail = shallowRef(initial?.detail ?? null);
  const reasons = ref({ submission: "", approval: "", rejection: "" });
  const pending = ref(false),
    locked = ref(initial?.operation?.status === "unconfirmed"),
    notice = ref("");
  const confirmed = shallowRef<ReviewCompletion | null>(
    initial?.operation?.status === "completed" ? initial.operation : null,
  );
  let sequence = initial?.sequence ?? 0,
    operation = initial?.operation ?? null;
  let attempted: { sequence: number; request: PlanRequest } | null = null;
  let active = true,
    generation = 0,
    effectPending = false;
  const identity = initial ? reviewIdentity(initial.detail) : null;
  const actor = port.actorId;

  function settle(op: ReviewOperation) {
    if (
      !attempted ||
      op.sequence !== attempted.sequence ||
      op.action !== attempted.request[0] ||
      !equal(op.input, attempted.request[1])
    )
      throw Error("Different plan operation");
    operation = op;
    sequence = op.sequence;
    locked.value = true;
    if (op.status === "completed") {
      confirmed.value = op;
      const key =
        op.action === "submit-plan"
          ? "submission"
          : op.action === "approve-plan"
            ? "approval"
            : op.action === "reject-plan"
              ? "rejection"
              : null;
      const reason =
        op.action === "execute-plan"
          ? undefined
          : op.action === "submit-plan"
            ? op.input.submission.reason
            : op.input.decision.reason;
      if (key && reasons.value[key].trim() === reason) reasons.value[key] = "";
      notice.value = "The reviewed decision completed. Refreshing its evidence…";
    } else
      notice.value =
        op.status === "rejected"
          ? (op.feedback ?? []).map((k) => reviewFeedback[k]).join(" ")
          : "The outcome remains unconfirmed. Refresh before another decision.";
  }
  function reconciled(op: ReviewOperation, model: PlanDetail) {
    const p = model.plan;
    if (op.status === "rejected") return true;
    if (op.status !== "completed") return false;
    if (op.action === "submit-plan")
      return p.lifecycle_state !== "draft" || p.reviewed_decision !== null;
    if (op.action === "approve-plan") return p.reviewed_decision?.decision === "approved";
    if (op.action === "reject-plan") return p.reviewed_decision?.decision === "rejected";
    return (
      p.reviewed_decision?.decision === "approved" &&
      p.approved_version === p.version &&
      ["executing", "partially_reserved", "reserved", "failed", "canceled", "superseded"].includes(
        p.lifecycle_state,
      )
    );
  }
  function accept(value: unknown) {
    const next = admitPlanReviewPage(value, port.context, actor);
    if (!next || reviewIdentity(next.detail) !== identity || next.sequence < sequence)
      throw Error("Unavailable reviewed plan");
    if (next.sequence === sequence && !equal(next.operation, operation))
      throw Error("Changed plan operation");
    if (next.sequence > sequence) {
      if (!next.operation) throw Error("Missing plan operation");
      settle(next.operation);
    }
    detail.value = next.detail;
    // A refresh without the attempted receipt cannot settle a lost response.
    locked.value =
      attempted && sequence < attempted.sequence
        ? true
        : !!operation && !reconciled(operation, next.detail);
  }
  async function read(n: number) {
    const value = await port.refresh();
    if (active && generation === n) accept(value);
  }
  async function refresh() {
    if (pending.value) return;
    const n = ++generation;
    pending.value = true;
    try {
      await read(n);
      if (active && generation === n)
        notice.value = locked.value
          ? "Review refreshed; the previous outcome is not confirmed. Further decisions remain disabled."
          : "Review refreshed. Unsaved reasons are retained.";
    } catch {
      if (active && generation === n)
        notice.value =
          "Review could not be refreshed. Previous evidence, reasons and confirmed receipt are retained.";
    } finally {
      if (active && generation === n) pending.value = false;
    }
  }
  const enabled = (action: PlanAction) =>
    !!detail.value && !pending.value && !locked.value && canAct(detail.value, action);
  async function execute(action: PlanAction, reason = "") {
    const d = detail.value;
    if (!d || !enabled(action)) return;
    if (action !== "execute-plan" && !validReviewReason(reason)) {
      notice.value = "Enter a reason of at most 4096 bytes.";
      return;
    }
    const current = { sequence: sequence + 1, request: planRequest(d, action, reason) },
      n = ++generation;
    attempted = current;
    pending.value = true;
    effectPending = true;
    notice.value = "Sending the reviewed decision…";
    try {
      const result = await port.execute(...planPageRequest(current.sequence, ...current.request));
      if (!active || generation !== n) return;
      const op = admitReviewOperation(result, d, actor);
      if (!op) throw Error("Unavailable plan receipt");
      settle(op);
      if (op.status !== "unconfirmed") {
        try {
          await read(n);
          if (active && generation === n && op.status === "completed")
            notice.value = locked.value
              ? "Decision completed. Updated evidence is not yet available."
              : "Decision completed. Review updated.";
        } catch {
          if (active && generation === n)
            notice.value =
              "The response is retained, but the review could not be refreshed. Refresh before another decision.";
        }
      }
    } catch {
      if (active && generation === n) {
        locked.value = true;
        notice.value =
          "No confirmed response was received. Keep this review open and refresh to recover its receipt.";
      }
    } finally {
      if (active && generation === n) {
        pending.value = false;
        effectPending = false;
      }
    }
  }
  watch(input, (value) => {
    if (equal(value, initial) || pending.value) return;
    try {
      accept(value);
    } catch {
      locked.value = true;
      notice.value =
        "Updated review could not be admitted. Previous evidence and reasons are retained.";
    }
  });
  const release = port.guardNavigation?.(() => !effectPending);
  onBeforeUnmount(() => {
    active = false;
    generation++;
    release?.();
  });
  return {
    detail,
    reasons,
    pending,
    locked,
    notice,
    enabled,
    execute,
    refresh,
    confirmed,
    connected: computed(() => true),
  };
}
