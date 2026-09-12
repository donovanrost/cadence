import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { PlanAction, PlanDetailPort } from "./OpsContactPlanShow.contracts";
import { useCapturedPlanReview } from "./plan-review-state";
import {
  admitPlanDetail,
  canAct,
  completedReceipt,
  planDecision,
  reviewIdentity,
} from "./plan-detail";
export function usePlanDetail(input: () => unknown, port: PlanDetailPort | undefined) {
  if (port?.captured) return useCapturedPlanReview(input, port);
  const detail = shallowRef(admitPlanDetail(input(), port?.context));
  const reasons = ref({ submission: "", approval: "", rejection: "" });
  const pending = ref(false),
    locked = ref(false),
    notice = ref("");
  let generation = 0,
    active = true;
  let confirmed: { action: PlanAction; version: number; hash: string } | undefined;
  let planId = detail.value?.plan.id;
  function replace(value: unknown) {
    let next = admitPlanDetail(value, port?.context);
    if (next && planId && next.plan.id !== planId) next = null;
    if (!next || !detail.value || reviewIdentity(next) !== reviewIdentity(detail.value))
      reasons.value = { submission: "", approval: "", rejection: "" };
    if (next) planId ??= next.plan.id;
    detail.value = next;
  }
  watch(input, (v) => {
    if (pending.value) locked.value = true;
    generation++;
    pending.value = false;
    replace(v);
  });
  function reconciled() {
    const p = detail.value?.plan;
    if (!confirmed || !p || p.version !== confirmed.version || p.content_sha256 !== confirmed.hash)
      return false;
    if (confirmed.action === "submit-plan") return p.lifecycle_state !== "draft";
    if (confirmed.action === "approve-plan") return p.reviewed_decision?.decision === "approved";
    if (confirmed.action === "reject-plan") return p.reviewed_decision?.decision === "rejected";
    return p.reviewed_decision?.decision === "approved" && p.approved_version === p.version;
  }
  onBeforeUnmount(() => {
    active = false;
    generation++;
  });
  async function refresh() {
    if (!port || pending.value) return;
    const run = ++generation;
    pending.value = true;
    try {
      const value = await port.refresh();
      if (!active || run !== generation) return;
      replace(value);
      if (reconciled()) locked.value = false;
      notice.value = !locked.value
        ? "Review refreshed."
        : confirmed
          ? "Decision completed, but its updated evidence is not yet available. Further decisions remain disabled."
          : "Review refreshed. The previous operation has an uncertain outcome; another submission remains disabled.";
    } catch {
      if (active && run === generation)
        notice.value = "Review could not be refreshed. Your reasons are retained.";
    } finally {
      if (active && run === generation) pending.value = false;
    }
  }
  const enabled = (action: PlanAction) =>
    !!port && !!detail.value && !pending.value && !locked.value && canAct(detail.value, action);
  async function execute(action: PlanAction, reason = "") {
    const d = detail.value;
    if (!d || !port || !enabled(action)) return;
    if (
      action !== "execute-plan" &&
      (!reason.trim() || new TextEncoder().encode(reason.trim()).length > 4096)
    ) {
      notice.value = "Enter a reason of at most 4096 bytes.";
      return;
    }
    const run = ++generation;
    confirmed = undefined;
    pending.value = true;
    notice.value = "Sending the reviewed decision…";
    try {
      const receipt = await port.execute(action, planDecision(d, action, reason));
      if (!active || run !== generation) return;
      if (!completedReceipt(receipt, d, action)) throw new Error("Uncertain receipt");
      confirmed = { action, version: d.plan.version, hash: d.plan.content_sha256 };
      reasons.value = { submission: "", approval: "", rejection: "" };
      // Until a fresh read arrives, the old review must not allow a duplicate decision.
      locked.value = true;
      try {
        const value = await port.refresh();
        if (!active || run !== generation) return;
        replace(value);
        locked.value = !reconciled();
        notice.value =
          detail.value && !locked.value
            ? "Decision completed. Review updated."
            : "Decision completed, but the refreshed review was unavailable.";
      } catch {
        if (active && run === generation)
          notice.value = "Decision completed. Refresh the review before continuing.";
      }
    } catch {
      if (!active || run !== generation) return;
      locked.value = true;
      notice.value =
        "The operation could not be confirmed. Keep this review open and refresh its evidence; do not submit it again.";
    } finally {
      if (active && run === generation) pending.value = false;
    }
  }
  return {
    detail,
    reasons,
    pending,
    locked,
    notice,
    enabled,
    execute,
    refresh,
    confirmed: shallowRef(null),
    connected: computed(() => !!port),
  };
}
