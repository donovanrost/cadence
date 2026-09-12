import { computed, ref } from "vue";
import type {
  ReservationAction,
  ReservationDetail,
  ReservationPort,
} from "./OpsContactDetail.contracts";
import { canDecide, reservationDecision, decisionState } from "./reservation-detail";
import { useContactWorkflow } from "./contact-workflow-state";
export function useCapturedReservation(input: () => unknown, port: ReservationPort) {
  const reasons = ref({
    "approve-provider-change": "",
    "reject-provider-change": "",
    "acknowledge-provider-change": "",
  });
  const state = useContactWorkflow(
    input,
    port,
    "reservation",
    { ...port.context, resource_id: port.context.reservation_id },
    {
      execute: (action, payload) => port.execute(action as ReservationAction, payload),
      completed(op) {
        const action = op.action as ReservationAction;
        if (reasons.value[action].trim() === op.input.reason) reasons.value[action] = "";
      },
      reconciled(op, page) {
        const selected = (page.model as ReservationDetail).selected;
        return (
          !!selected &&
          selected.id === op.input.change_evidence.change_id &&
          selected.proposal_hash === op.input.change_evidence.proposal_hash &&
          selected.lifecycle_state === decisionState(op.action as ReservationAction)
        );
      },
    },
  );
  const detail = computed(() => state.page.value?.model as ReservationDetail | null);
  const enabled = (action: ReservationAction) =>
    !!detail.value &&
    !state.pending.value &&
    !state.locked.value &&
    canDecide(detail.value, action);
  async function execute(action: ReservationAction, reason = "") {
    if (!detail.value || !enabled(action)) return;
    if (!reason.trim() || new TextEncoder().encode(reason.trim()).length > 4096) {
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
    confirmed: state.confirmed,
    enabled,
    execute,
    refresh: state.refresh,
    connected: computed(() => true),
  };
}
