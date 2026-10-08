import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type {
  ContactSchedulePort,
  ScheduleOpportunity,
  ScheduleReservation,
  ScheduleSearchResult,
} from "./OpsContactSchedule.contracts";
import type { ScheduleCommand, ScheduleOperation, ScheduleProjection } from "./schedule-service";
import {
  admitContactSchedule,
  cancellable,
  cancelEvidence,
  sameEvidence,
} from "./contact-schedule";
import { recordOperation, unresolved, type ScheduleMutation } from "./schedule-transitions";
import {
  useScheduleDraft,
  scheduleSearch,
  invalidScheduleWindow,
  availableOpportunity,
} from "./schedule-draft";

type SearchState =
  | { readonly kind: "idle" }
  | { readonly kind: "searching"; readonly request: number }
  | { readonly kind: "reviewed"; readonly result: ScheduleSearchResult };

export function useContactSchedule(input: () => unknown, port?: ContactSchedulePort) {
  const schedule = shallowRef(admitContactSchedule(input(), port?.context));
  const projection = shallowRef<ScheduleProjection | null>(null);
  const searchState = shallowRef<SearchState>({ kind: "idle" });
  const mutations = shallowRef<ReadonlyMap<string, ScheduleMutation>>(new Map());
  const cancellation = shallowRef<ScheduleReservation | null>(null);
  const notice = ref("");
  const lastSubmitted = ref<string>();
  const reading = ref(false);
  let active = true,
    readEpoch = 0,
    searchEpoch = 0;
  const query = schedule.value?.query;
  const { draft, now } = useScheduleDraft(() => schedule.value);

  function record(operation: ScheduleOperation) {
    const next = new Map(mutations.value);
    next.set(operation.operation_id, recordOperation(next.get(operation.operation_id), operation));
    mutations.value = next;
  }
  function accept(next: ScheduleProjection) {
    if (query && !sameEvidence(query, next.model.query)) throw Error("Different scheduling query");
    const merged = new Map(mutations.value);
    for (const op of next.operations.entries)
      merged.set(op.operation_id, recordOperation(merged.get(op.operation_id), op));
    mutations.value = merged;
    projection.value = next;
    schedule.value = next.model;
  }
  function admit(value: unknown) {
    if (!port) {
      schedule.value = admitContactSchedule(value);
      return;
    }
    try {
      accept(port.admit(value));
    } catch {
      notice.value = "Updated evidence could not be verified. Previous evidence is retained.";
    }
  }
  admit(input());
  // LiveVue patches nested props in place. Every ingress runs the same decoder.
  watch(
    input,
    (value) => {
      readEpoch++;
      reading.value = false;
      admit(value);
    },
    { deep: true },
  );
  onBeforeUnmount(() => {
    active = false;
    readEpoch++;
    searchEpoch++;
  });

  async function observe(mutation: ScheduleMutation) {
    if (!port || !unresolved(mutation) || mutation.kind === "submitting") return;
    const ref =
      mutation.kind === "recorded"
        ? { operationId: mutation.operation.operation_id, action: mutation.operation.action }
        : mutation.command;
    const op = await port.observe(ref);
    if (active && op) record(op);
  }
  async function refresh() {
    if (!port) return;
    const epoch = ++readEpoch;
    reading.value = true;
    try {
      const next = await port.read();
      if (!active || epoch !== readEpoch) return;
      accept(next);
      await Promise.all([...mutations.value.values()].map(observe));
      if (active && epoch === readEpoch)
        notice.value = "Contact ledgers and recorded operations refreshed.";
    } catch {
      if (active && epoch === readEpoch)
        notice.value =
          "Updated evidence is unavailable. Previous evidence and recorded results are retained.";
    } finally {
      if (active && epoch === readEpoch) reading.value = false;
    }
  }
  async function search() {
    const model = schedule.value;
    const route = model?.routes.entries.find((r) => r.key === draft.route_key);
    if (!port || !projection.value || !model?.permissions.operate || !route) return;
    const review = scheduleSearch(draft, route);
    if (!review) {
      notice.value = invalidScheduleWindow;
      return;
    }
    const epoch = ++searchEpoch;
    searchState.value = { kind: "searching", request: epoch };
    try {
      const result = await port.search(
        { contact_search: review, route_evidence: route.evidence },
        route,
      );
      if (!active || epoch !== searchEpoch) return;
      const currentRoute = schedule.value?.routes.entries.find((r) => r.key === draft.route_key);
      const currentSearch = currentRoute && scheduleSearch(draft, currentRoute);
      if (
        !currentRoute ||
        !currentSearch ||
        !sameEvidence(currentRoute.evidence, route.evidence) ||
        !sameEvidence(currentSearch, review)
      ) {
        searchState.value = { kind: "idle" };
        return;
      }
      searchState.value = { kind: "reviewed", result };
      notice.value = "Search complete. Review an opportunity before reserving.";
    } catch {
      if (active && epoch === searchEpoch) {
        searchState.value = { kind: "idle" };
        notice.value = "Opportunity search failed. Refresh route evidence and try again.";
      }
    }
  }
  const result = computed(() =>
    searchState.value.kind === "reviewed" ? searchState.value.result : null,
  );
  function tokenUsed(token: string) {
    return [...mutations.value.values()].some(
      (m) => m.command?.action === "reserve" && m.command.input.token === token,
    );
  }
  function reservable(opportunity: ScheduleOpportunity) {
    const model = schedule.value,
      found = result.value;
    const route = model?.routes.entries.find((r) => r.key === draft.route_key);
    const currentSearch = route && scheduleSearch(draft, route);
    return (
      !!port &&
      !!projection.value &&
      !!model?.permissions.operate &&
      !!route &&
      !!found &&
      !!currentSearch &&
      sameEvidence(currentSearch, found.search) &&
      sameEvidence(route.evidence, found.route.evidence) &&
      !tokenUsed(opportunity.token) &&
      availableOpportunity(found, opportunity, Math.max(now.value, Date.now()))
    );
  }
  function cancelling(id: string) {
    return [...mutations.value.values()].some(
      (m) =>
        unresolved(m) &&
        ((m.command?.action === "cancel" &&
          m.command.input.reservation_evidence.reservation_id === id) ||
          (m.kind === "recorded" && m.operation.reservation_id === id)),
    );
  }
  async function submit(command: ScheduleCommand) {
    if (!port) return;
    lastSubmitted.value = command.operationId;
    mutations.value = new Map(mutations.value).set(command.operationId, {
      kind: "submitting",
      command,
    });
    try {
      const operation = await port.submit(command);
      if (!active) return;
      if (operation.status === "not_accepted") {
        // A concurrent observation may already prove this intent was accepted.
        if (mutations.value.get(command.operationId)?.kind === "recorded") return;
        mutations.value = new Map(mutations.value).set(command.operationId, {
          kind: "rejected",
          command,
          reason: operation.reason,
        });
        notice.value =
          operation.reason === "conflict"
            ? "An operation already exists for this reservation. Refresh to review its outcome."
            : "The reviewed evidence could not be accepted. Refresh before continuing.";
        return;
      }
      record(operation);
      if (command.action === "cancel") cancellation.value = null;
      notice.value = "Operation recorded. Refresh to check its provider outcome.";
    } catch {
      if (!active) return;
      if (mutations.value.get(command.operationId)?.kind !== "submitting") return;
      mutations.value = new Map(mutations.value).set(command.operationId, {
        kind: "unknown",
        command,
      });
      notice.value =
        "Acceptance is unconfirmed. Refresh to check this operation before retrying it.";
    }
  }
  async function reserve(opportunity: ScheduleOpportunity) {
    if (reservable(opportunity))
      await submit({
        operationId: crypto.randomUUID(),
        action: "reserve",
        input: { token: opportunity.token },
      });
  }
  function reviewCancel(row: ScheduleReservation) {
    if (
      port &&
      projection.value &&
      schedule.value?.permissions.cancel &&
      schedule.value.reservations.entries.includes(row) &&
      cancellable(row) &&
      !cancelling(row.id)
    )
      cancellation.value = structuredClone(row);
  }
  async function cancel() {
    const row = cancellation.value,
      model = schedule.value;
    if (port && model?.permissions.cancel && row && cancellable(row) && !cancelling(row.id))
      await submit({
        operationId: crypto.randomUUID(),
        action: "cancel",
        input: { reservation_evidence: cancelEvidence(model.context, row) },
      });
  }
  async function retry(mutation: ScheduleMutation) {
    if (mutation.kind === "unknown") await submit(mutation.command);
  }
  const operations = computed(() => [...mutations.value.values()]);
  const latest = computed(() =>
    mutations.value.get(
      lastSubmitted.value ?? projection.value?.operations.entries[0]?.operation_id ?? "",
    ),
  );
  return {
    schedule,
    draft,
    result,
    cancellation,
    notice,
    reading,
    searching: computed(() => searchState.value.kind === "searching"),
    operations,
    operationPage: computed(() => projection.value?.operations),
    receipt: computed(() =>
      latest.value?.kind === "recorded" ? latest.value.operation.result : null,
    ),
    uncertain: computed(() => operations.value.some(unresolved)),
    connected: !!port,
    operable: computed(() => !!port && !!projection.value),
    refresh,
    search,
    reservable,
    reserve,
    reviewCancel,
    cancel,
    cancelling,
    retry,
  };
}
