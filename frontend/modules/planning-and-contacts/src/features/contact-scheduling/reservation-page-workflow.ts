import { validReviewReason } from "../../shared/workflow-protocol";
import { computed, ref } from "vue";
import type { ReservationAction, ReservationPort } from "./OpsContactDetail.contracts";
import { canDecide, reservationDecision, decisionState } from "./reservation-detail";
import { useContactWorkflow } from "./contact-workflow-state";
export function useReservationPageWorkflow(
  input: () => unknown,
  port: Extract<ReservationPort, { protocol: "page-snapshot" }>,
) {
  const reasons = ref({
    "approve-provider-change": "",
    "reject-provider-change": "",
    "acknowledge-provider-change": "",
  });
  const state = useContactWorkflow(
    input,
    port,
    "reservation",
    {
      ...port.context,
      ...(port.context.reservation_id === undefined
        ? {}
        : { resource_id: port.context.reservation_id }),
    },
    {
      execute: (...request) => {
        if (request[0] === "search" || request[0] === "reserve" || request[0] === "cancel")
          throw Error("Not a reservation review action");
        return port.execute(...request);
      },
      completed(op) {
        if (op.action === "search" || op.action === "reserve" || op.action === "cancel") return;
        const action = op.action;
        if (reasons.value[action].trim() === op.input.reason) reasons.value[action] = "";
      },
      reconciled(op, page) {
        if (
          page.kind !== "reservation" ||
          op.action === "search" ||
          op.action === "reserve" ||
          op.action === "cancel"
        )
          return false;
        const selected = page.model.selected;
        return (
          !!selected &&
          selected.id === op.input.change_evidence.change_id &&
          selected.proposal_hash === op.input.change_evidence.proposal_hash &&
          selected.lifecycle_state === decisionState(op.action)
        );
      },
    },
  );
  const detail = computed(() =>
    state.page.value?.kind === "reservation" ? state.page.value.model : null,
  );
  const enabled = (action: ReservationAction) =>
    !!detail.value &&
    !state.pending.value &&
    !state.locked.value &&
    canDecide(detail.value, action);
  async function execute(action: ReservationAction, reason = "") {
    if (!detail.value || !enabled(action)) return;
    if (!validReviewReason(reason)) {
      state.notice.value = "Enter a reason of at most 4096 bytes.";
      return;
    }
    await state.execute(action, reservationDecision(detail.value, reason));
  }
  return {
    detail,
    reasons,
    pending: state.pending,
    locked: state.locked,
    notice: state.notice,
    confirmed: computed(() => {
      const op = state.confirmed.value;
      return op && op.action !== "search" && op.action !== "reserve" && op.action !== "cancel"
        ? op
        : null;
    }),
    enabled,
    execute,
    refresh: state.refresh,
    connected: computed(() => true),
  };
}
