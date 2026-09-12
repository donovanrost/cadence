import { useCapturedReservation } from "./captured-reservation-state";
import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { ReservationAction, ReservationPort } from "./OpsContactDetail.contracts";
import {
  admitReservation,
  canDecide,
  completedReceipt,
  reservationDecision,
  reviewIdentity,
  decisionState,
} from "./reservation-detail";
export function useReservation(input: () => unknown, port: ReservationPort | undefined) {
  if (port?.captured) return useCapturedReservation(input, port);
  const detail = shallowRef(admitReservation(input(), port?.context));
  const reasons = ref({
    "approve-provider-change": "",
    "reject-provider-change": "",
    "acknowledge-provider-change": "",
  });
  const pending = ref(false),
    locked = ref(false),
    notice = ref("");
  let generation = 0,
    active = true;
  let confirmed: { action: ReservationAction; id: string; hash: string } | undefined;
  let reservationId = detail.value?.reservation.id;
  function replace(value: unknown) {
    let next = admitReservation(value, port?.context);
    if (next && reservationId && next.reservation.id !== reservationId) next = null;
    if (!next || !detail.value || reviewIdentity(next) !== reviewIdentity(detail.value))
      reasons.value = {
        "approve-provider-change": "",
        "reject-provider-change": "",
        "acknowledge-provider-change": "",
      };
    if (next) reservationId ??= next.reservation.id;
    detail.value = next;
  }
  watch(input, (v) => {
    if (pending.value) locked.value = true;
    generation++;
    pending.value = false;
    replace(v);
  });
  function reconciled() {
    const s = detail.value?.selected;
    return (
      !!confirmed &&
      !!s &&
      s.id === confirmed.id &&
      s.proposal_hash === confirmed.hash &&
      s.lifecycle_state === decisionState(confirmed.action)
    );
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
  const enabled = (action: ReservationAction) =>
    !!port && !!detail.value && !pending.value && !locked.value && canDecide(detail.value, action);
  async function execute(action: ReservationAction, reason = "") {
    const d = detail.value;
    if (!d || !port || !enabled(action)) return;
    if (!reason.trim() || new TextEncoder().encode(reason.trim()).length > 4096) {
      notice.value = "Enter a reason of at most 4096 bytes.";
      return;
    }
    const run = ++generation;
    confirmed = undefined;
    pending.value = true;
    notice.value = "Sending the reviewed decision…";
    try {
      const receipt = await port.execute(action, reservationDecision(d, reason));
      if (!active || run !== generation) return;
      if (!completedReceipt(receipt, d, action)) throw new Error("Uncertain receipt");
      confirmed = { action, id: d.selected!.id, hash: d.selected!.proposal_hash };
      reasons.value = {
        "approve-provider-change": "",
        "reject-provider-change": "",
        "acknowledge-provider-change": "",
      };
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
    confirmed: shallowRef<import("./contact-workflow").ContactOperation | null>(null),
    detail,
    reasons,
    pending,
    locked,
    notice,
    enabled,
    execute,
    refresh,
    connected: computed(() => !!port),
  };
}
