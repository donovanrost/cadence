import { computed, onBeforeUnmount, onMounted, reactive, ref, shallowRef, watch } from "vue";
import type {
  ContactSchedule,
  ContactSchedulePort,
  ScheduleOpportunity,
  ScheduleReservation,
} from "./OpsContactSchedule.contracts";
import { admitReceipt, cancellable, cancelEvidence, parseScheduleUTC } from "./contact-schedule";
import { useContactWorkflow } from "./contact-workflow-state";

export function useCapturedSchedule(input: () => unknown, port: ContactSchedulePort) {
  const cancellation = shallowRef<ScheduleReservation | null>(null);
  const state = useContactWorkflow(input, port, "schedule", port.context, {
    execute: (action, payload) => port.execute(action as "search" | "reserve" | "cancel", payload),
    completed(op) {
      if (op.action !== "search") cancellation.value = null;
    },
    reconciled(op, page) {
      if (op.action === "search") return !!page.search;
      const result = op.receipt?.result.value;
      const row =
        page.operation_reservation?.reservation ??
        (page.model as ContactSchedule).reservations.entries.find(
          (r) => r.id === result?.providerReservationId,
        );
      return (
        !!row &&
        row.provider_revision >= result!.providerRevision &&
        (op.action !== "cancel" || row.lifecycle_state === "canceled") &&
        !["requesting", "canceling", "unknown", "failed"].includes(row.lifecycle_state)
      );
    },
  });
  const schedule = computed(() => state.page.value?.model as ContactSchedule | null);
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
  const draft = reactive({
    route_key: schedule.value?.routes.entries[0]?.key ?? "",
    starts_at: schedule.value?.initial_window.starts_at.slice(0, 19) ?? "",
    ends_at: schedule.value?.initial_window.ends_at.slice(0, 19) ?? "",
  });
  const now = ref(Date.now());
  let ticker: ReturnType<typeof setInterval> | undefined;
  onMounted(() => {
    ticker = setInterval(() => {
      now.value = Date.now();
    }, 1000);
  });
  onBeforeUnmount(() => clearInterval(ticker));
  async function search() {
    const model = schedule.value,
      route = model?.routes.entries.find((r) => r.key === draft.route_key);
    if (!model?.permissions.operate || !route || state.pending.value || state.locked.value) return;
    const starts = parseScheduleUTC(draft.starts_at),
      ends = parseScheduleUTC(draft.ends_at);
    if (
      !Number.isFinite(starts) ||
      !Number.isFinite(ends) ||
      ends <= starts ||
      starts < Date.now() - 60000 ||
      ends - starts > 604800000
    ) {
      state.notice.value = "Choose a future UTC window of at most seven days.";
      return;
    }
    await state.execute("search", {
      contact_search: {
        spacecraft_id: route.spacecraft_id,
        route_key: route.key,
        starts_at: new Date(starts).toISOString().replace(".000Z", "Z"),
        ends_at: new Date(ends).toISOString().replace(".000Z", "Z"),
      },
      route_evidence: route.evidence,
    });
  }
  function reservable(o: ScheduleOpportunity) {
    return (
      !!schedule.value?.permissions.operate &&
      !state.pending.value &&
      !state.locked.value &&
      !state.page.value?.consumed.includes(o.token) &&
      ["available", "limited"].includes(o.availability) &&
      Date.parse(o.expires_at) > Math.max(now.value, Date.now()) &&
      !!result.value?.opportunities.includes(o)
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
