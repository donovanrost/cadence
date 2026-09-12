import {
  useScheduleDraft,
  scheduleSearch,
  invalidScheduleWindow,
  availableOpportunity,
} from "./schedule-draft";
import { useSchedulePageWorkflow } from "./schedule-page-workflow";
import { onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type {
  ContactSchedulePort,
  ScheduleOpportunity,
  ScheduleReservation,
  ScheduleReceipt,
  ScheduleSearchResult,
  ScheduleInputs,
} from "./OpsContactSchedule.contracts";
import {
  admitContactSchedule,
  completedResult,
  admitReceipt,
  admitSearch,
  cancellable,
  cancelEvidence,
  sameEvidence,
} from "./contact-schedule";
export function useContactSchedule(input: () => unknown, port?: ContactSchedulePort) {
  if (port?.protocol === "page-snapshot") return useSchedulePageWorkflow(input, port);
  const schedule = shallowRef(admitContactSchedule(input(), port?.context));
  const pending = ref(false),
    notice = ref(""),
    uncertain = ref(false);
  const result = shallowRef<ScheduleSearchResult | null>(null),
    receipt = shallowRef<ScheduleReceipt | null>(null),
    cancellation = shallowRef<ScheduleReservation | null>(null);
  const usedTokens = new Set<string>();
  const { draft, now } = useScheduleDraft(() => schedule.value);
  let active = true,
    generation = 0;
  const initialContext = schedule.value?.context ?? port?.context;
  const initialQuery = schedule.value?.query;
  function admitted(value: unknown) {
    const next = admitContactSchedule(value, initialContext);
    return next && (!initialQuery || sameEvidence(next.query, initialQuery)) ? next : null;
  }
  watch(input, (value) => {
    generation++;
    // A replaced view must not turn an in-flight effect into a retryable effect.
    if (pending.value) uncertain.value = true;
    pending.value = false;
    schedule.value = admitted(value);
    result.value = null;
    cancellation.value = null;
  });
  onBeforeUnmount(() => {
    active = false;
    generation++;
  });
  const current = (run: number) => active && run === generation;
  async function read(run: number) {
    if (!port) return false;
    try {
      const next = admitted(await port.refresh());
      if (!current(run) || !next) return false;
      schedule.value = next;
      return true;
    } catch {
      return false;
    }
  }
  async function refresh() {
    if (!port || pending.value) return;
    pending.value = true;
    const run = ++generation;
    const ok = await read(run);
    if (!current(run)) return;
    notice.value = ok
      ? "Contact ledgers refreshed."
      : "Contact ledgers could not be refreshed. Previous evidence is retained.";
    pending.value = false;
  }
  async function search() {
    const model = schedule.value,
      reviewed = model?.routes.entries.find((r) => r.key === draft.route_key);
    if (
      !port ||
      !model ||
      !model.permissions.operate ||
      !reviewed ||
      pending.value ||
      uncertain.value
    )
      return;
    const form = scheduleSearch(draft, reviewed);
    if (!form) {
      notice.value = invalidScheduleWindow;
      return;
    }
    const run = ++generation;
    pending.value = true;
    result.value = null;
    cancellation.value = null;
    notice.value = "";
    try {
      const response = await port.execute("search", {
        contact_search: form,
        route_evidence: reviewed.evidence,
      });
      if (!current(run)) return;
      result.value = admitSearch(completedResult(response), model.context, form, reviewed);
      notice.value = result.value
        ? "Search complete. Review a provider opportunity before reserving."
        : "The opportunity response could not be verified. Search again after refreshing route evidence.";
    } catch {
      if (current(run))
        notice.value = "Opportunity search failed. Refresh route evidence and try again.";
    } finally {
      if (current(run)) pending.value = false;
    }
  }
  function reservable(o: ScheduleOpportunity) {
    return (
      !!port &&
      schedule.value?.permissions.operate &&
      !pending.value &&
      !uncertain.value &&
      !usedTokens.has(o.token) &&
      availableOpportunity(result.value, o, Math.max(now.value, Date.now()))
    );
  }
  function reviewCancel(row: ScheduleReservation) {
    if (
      !port ||
      pending.value ||
      uncertain.value ||
      !schedule.value?.permissions.cancel ||
      !cancellable(row) ||
      !schedule.value?.reservations.entries.includes(row)
    )
      return;
    cancellation.value = structuredClone(row);
  }
  async function mutate(
    ...request:
      | [action: "reserve", payload: ScheduleInputs["reserve"], expected?: string]
      | [action: "cancel", payload: ScheduleInputs["cancel"], expected?: string]
  ) {
    if (!port || pending.value || uncertain.value) return;
    const [action, payload, expected] = request;
    const run = ++generation;
    pending.value = true;
    receipt.value = null;
    notice.value = "";
    try {
      const next = admitReceipt(
        completedResult(
          await port.execute(
            ...(action === "reserve" ? ([action, payload] as const) : ([action, payload] as const)),
          ),
        ),
        expected,
      );
      if (!current(run)) return;
      if (
        !next ||
        (action === "cancel"
          ? next.lifecycleState !== "canceled"
          : !["pending", "confirmed", "active", "completed"].includes(next.lifecycleState))
      )
        throw new Error("Unconfirmed outcome");
      receipt.value = next;
      cancellation.value = null;
      const ok = await read(run);
      if (current(run))
        notice.value = ok
          ? "Provider response recorded. Contact ledgers refreshed."
          : "Provider response recorded. Refresh the ledgers to see the latest evidence.";
    } catch {
      if (current(run)) {
        uncertain.value = true;
        notice.value =
          "The provider outcome is unconfirmed. Further mutations are paused. Refresh the ledgers and review reservation evidence before leaving this page.";
      }
    } finally {
      if (current(run)) pending.value = false;
    }
  }
  async function reserve(o: ScheduleOpportunity) {
    if (!reservable(o)) return;
    usedTokens.add(o.token);
    await mutate("reserve", { token: o.token });
  }
  async function cancel() {
    const row = cancellation.value,
      model = schedule.value;
    if (!row || !model || !model.permissions.cancel || !cancellable(row)) return;
    await mutate("cancel", { reservation_evidence: cancelEvidence(model.context, row) }, row.id);
  }
  return {
    schedule,
    draft,
    pending,
    notice,
    uncertain,
    result,
    receipt,
    cancellation,
    connected: !!port,
    refresh,
    search,
    reservable,
    reserve,
    reviewCancel,
    cancel,
  };
}
