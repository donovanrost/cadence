import { shallowRef } from "vue";
import { useReservationPageWorkflow } from "./reservation-page-workflow";
import { useQueryReview } from "../../shared/use-query-review";
import type { ReservationPort, ReservationAction } from "./OpsContactDetail.contracts";
import type { ContactCompletion } from "./contact-workflow";
import {
  admitReservation,
  canDecide,
  completedReceipt,
  reservationDecision,
  reviewIdentity,
  decisionState,
} from "./reservation-detail";

export function useReservation(input: () => unknown, port: ReservationPort | undefined) {
  if (port?.protocol === "page-snapshot") return useReservationPageWorkflow(input, port);
  const state = useQueryReview(input, port, {
    admit: (value) => admitReservation(value, port?.context),
    subject: (detail) => detail.reservation.id,
    identity: reviewIdentity,
    reasons: () => ({
      "approve-provider-change": "",
      "reject-provider-change": "",
      "acknowledge-provider-change": "",
    }),
    canAct: canDecide,
    reasonRequired: () => true,
    request: (detail, action, reason) => [action, reservationDecision(detail, reason)],
    completion: (value, detail, action) => {
      if (!completedReceipt(value, detail, action) || !detail.selected) return null;
      return { action, id: detail.selected.id, hash: detail.selected.proposal_hash };
    },
    reconciled: (detail, confirmed) => {
      const selected = detail.selected;
      return (
        selected !== null &&
        selected.id === confirmed.id &&
        selected.proposal_hash === confirmed.hash &&
        selected.lifecycle_state === decisionState(confirmed.action)
      );
    },
  });
  return {
    ...state,
    confirmed: shallowRef<Extract<ContactCompletion, { action: ReservationAction }> | null>(null),
  };
}
