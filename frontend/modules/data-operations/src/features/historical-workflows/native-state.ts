import { computed, onBeforeUnmount, reactive, ref, shallowRef, watch } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  admitHistoryOperation,
  admitHistoryPage,
  same,
  type HistoryAction,
  type HistoryOperation,
  type HistoryPage,
  type Binding,
} from "./native-contract";
export function useHistoricalWorkflows(
  initial: () => HistoryPage,
  port: OpsPagePort,
  readPort: OpsPageReadPort,
) {
  const first = initial();
  const page = shallowRef(first),
    pending = ref(false),
    stale = ref(false),
    unknown = ref(false),
    notice = ref("");
  const lastEffect = shallowRef<HistoryOperation | null>(
    first.operation && !["read-page", "validate-request"].includes(first.operation.action)
      ? first.operation
      : null,
  );
  const draft = reactive({ ...first.model.defaults });
  const reasons = reactive({ transition: "", retry: "", correction: "" });
  const selectedBinding = shallowRef<Binding | null>(null);
  let active = true,
    readGeneration = 0;
  let awaiting: { sequence: number; action: HistoryAction; input: Record<string, unknown> } | null =
    null;
  const locked = computed(() => unknown.value || page.value.operation?.status === "unconfirmed");
  const disabled = computed(
    () => pending.value || locked.value || stale.value || page.value.read_error,
  );
  const dirty = computed(
    () => !same(draft, first.model.defaults) || Object.values(reasons).some(Boolean),
  );
  const dispose = port.guardNavigation?.(
    () =>
      !pending.value &&
      !locked.value &&
      (!dirty.value ||
        window.confirm("Leave this page and discard the unsaved request and decision reasons?")),
  );
  onBeforeUnmount(() => {
    active = false;
    readGeneration++;
    dispose?.();
  });
  function selectBinding(binding: Binding) {
    selectedBinding.value = { ...binding };
    draft.source_binding_id = binding.id;
    draft.data_source_id = binding.source_id;
    draft.realm = binding.realm;
  }
  function accept(value: unknown): boolean {
    const next = admitHistoryPage(value, first.model.context, first.model.mode);
    if (!next || next.actor_id !== first.actor_id || next.sequence < page.value.sequence)
      return false;
    if (
      awaiting &&
      (next.sequence !== awaiting.sequence ||
        !next.operation ||
        next.operation.action !== awaiting.action ||
        !same(next.operation.input, awaiting.input))
    )
      return false;
    page.value = next;
    stale.value = false;
    if (next.operation && !["read-page", "validate-request"].includes(next.operation.action))
      lastEffect.value = next.operation;
    unknown.value = next.operation?.status === "unconfirmed";
    if (!unknown.value) awaiting = null;
    return true;
  }
  watch(initial, (value) => {
    if (!pending.value && !accept(value)) stale.value = true;
  });
  async function refresh() {
    const generation = ++readGeneration;
    try {
      const value = await readPort.read();
      if (!active || generation !== readGeneration) return;
      if (!accept(value)) throw Error("unavailable");
      notice.value = locked.value
        ? "The outcome is still unconfirmed. Inspect the group audit before taking another action."
        : "Workflow evidence refreshed. Unsaved inputs were retained.";
    } catch {
      if (active && generation === readGeneration) {
        stale.value = true;
        notice.value =
          "The current evidence could not be read. Your inputs are retained; refresh before continuing.";
      }
    }
  }
  async function execute(action: HistoryAction, input: Record<string, unknown>) {
    if ((disabled.value && action !== "read-page") || pending.value || locked.value) return;
    pending.value = true;
    notice.value = "";
    const sequence = page.value.sequence + 1;
    awaiting = { sequence, action, input: structuredClone(input) };
    try {
      const value = await port.execute(action, { sequence, payload: input });
      if (!active) return;
      const op = admitHistoryOperation(value, page.value);
      if (!op || op.sequence !== sequence || op.action !== action || !same(op.input, input))
        throw Error("unconfirmed");
      page.value = { ...page.value, sequence, operation: op };
      if (!["read-page", "validate-request"].includes(action)) lastEffect.value = op;
      unknown.value = op.status === "unconfirmed";
      if (!unknown.value) awaiting = null;
      await refresh();
      if (op.status === "rejected")
        notice.value =
          "The operation was not accepted. Review current evidence, permissions and input values before trying again.";
      if (action === "validate-request" && op.result)
        notice.value = op.result.valid
          ? "The request is valid for the reviewed binding."
          : "The request is invalid or the binding has changed. Check the source, UTC range and input limits, then select the current binding.";
    } catch {
      if (active) {
        unknown.value = true;
        notice.value =
          "The response was lost or could not be verified. Refresh to recover the operation outcome; do not submit it again.";
      }
    } finally {
      if (active) pending.value = false;
    }
  }
  async function chooseQuery(patch: Record<string, string>) {
    const current = Object.fromEntries(
      Object.entries(page.value.model.query)
        .filter(([, v]) => v !== null)
        .map(([k, v]) => [k, String(v)]),
    );
    await execute("read-page", { query: { ...current, ...patch } });
  }
  return {
    page,
    draft,
    reasons,
    selectedBinding,
    lastEffect,
    pending,
    stale,
    locked,
    disabled,
    notice,
    selectBinding,
    execute,
    refresh,
    chooseQuery,
  };
}
