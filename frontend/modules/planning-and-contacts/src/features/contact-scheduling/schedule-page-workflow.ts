import {
  useScheduleDraft,
  scheduleSearch,
  invalidScheduleWindow,
  availableOpportunity,
} from "./schedule-draft";
import { computed, shallowRef, watch } from "vue";
import type {
  ContactSchedulePort,
  ScheduleOpportunity,
  ScheduleReservation,
} from "./OpsContactSchedule.contracts";
import { admitReceipt, cancellable, cancelEvidence } from "./contact-schedule";
import { useContactWorkflow } from "./contact-workflow-state";

export function useSchedulePageWorkflow(
  input: () => unknown,
  port: Extract<ContactSchedulePort, { protocol: "page-snapshot" }>,
) {
  const cancellation = shallowRef<ScheduleReservation | null>(null);
  const state = useContactWorkflow(input, port, "schedule", port.context, {
    execute: (...request) => {
      if (request[0] === "search" || request[0] === "reserve" || request[0] === "cancel")
        return port.execute(...request);
      throw Error("Not a scheduling action");
    },
    completed(op) {
      if (op.action !== "search") cancellation.value = null;
    },
    reconciled(op, page) {
      if (page.kind !== "schedule") return false;
      if (op.action === "search") return !!page.search;
      if (op.action !== "reserve" && op.action !== "cancel") return false;
      const result = op.receipt.result.value;
      const row =
        page.operation_reservation?.reservation ??
        page.model.reservations.entries.find((r) => r.id === result.providerReservationId);
      return (
        !!row &&
        row.provider_revision >= result.providerRevision &&
        (op.action !== "cancel" || row.lifecycle_state === "canceled") &&
        !["requesting", "canceling", "unknown", "failed"].includes(row.lifecycle_state)
      );
    },
  });
  const schedule = computed(() =>
    state.page.value?.kind === "schedule" ? state.page.value.model : null,
  );
  const result = computed(() => state.page.value?.search ?? null);
  const lastBooking = shallowRef<ReturnType<typeof admitReceipt>>(null);
  watch(
    state.confirmed,
    (op) => {
      const value = admitReceipt(op?.receipt?.result.value);
      if (value) lastBooking.value = value;
    },
    { immediate: true },
  );
  const receipt = computed(() => {
    const op = state.page.value?.operation;
    const value =
      op?.action !== "search" && op?.receipt
        ? op.receipt.result.value
        : state.confirmed.value?.receipt?.result.value;
    return admitReceipt(value) ?? lastBooking.value;
  });
  const { draft, now } = useScheduleDraft(() => schedule.value);
  async function search() {
    const model = schedule.value,
      route = model?.routes.entries.find((r) => r.key === draft.route_key);
    if (!model?.permissions.operate || !route || state.pending.value || state.locked.value) return;
    const search = scheduleSearch(draft, route);
    if (!search) {
      state.notice.value = invalidScheduleWindow;
      return;
    }
    await state.execute("search", {
      contact_search: search,
      route_evidence: route.evidence,
    });
  }
  function reservable(o: ScheduleOpportunity) {
    return (
      !!schedule.value?.permissions.operate &&
      !state.pending.value &&
      !state.locked.value &&
      !state.page.value?.consumed.includes(o.token) &&
      availableOpportunity(result.value, o, Math.max(now.value, Date.now()))
    );
  }
  async function reserve(o: ScheduleOpportunity) {
    if (reservable(o)) await state.execute("reserve", { token: o.token });
  }
  function reviewCancel(row: ScheduleReservation) {
    if (
      !state.pending.value &&
      !state.locked.value &&
      schedule.value?.permissions.cancel &&
      schedule.value.reservations.entries.includes(row) &&
      cancellable(row)
    )
      cancellation.value = structuredClone(row);
  }
  async function cancel() {
    if (schedule.value?.permissions.cancel && cancellation.value && cancellable(cancellation.value))
      await state.execute("cancel", {
        reservation_evidence: cancelEvidence(schedule.value.context, cancellation.value),
      });
  }
  return {
    schedule,
    draft,
    result,
    receipt,
    cancellation,
    pending: state.pending,
    uncertain: state.locked,
    notice: state.notice,
    connected: true,
    refresh: state.refresh,
    search,
    reservable,
    reserve,
    reviewCancel,
    cancel,
  };
}
