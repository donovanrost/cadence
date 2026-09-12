import { computed, onBeforeUnmount, reactive, ref, shallowRef, watch } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  admitSourceOperation,
  admitSourcePage,
  same,
  type SourceAction,
  type SourceInputs,
  type SourceEffectAction,
  isSourceEffect,
  type SourceOperation,
  type SourcePage,
  type Binding,
  type Source,
  validInput,
} from "./native-contract";
export function useDataSources(
  initial: () => SourcePage,
  port: OpsPagePort,
  readPort: OpsPageReadPort,
) {
  const first = initial();
  const page = shallowRef(first),
    pending = ref(false),
    stale = ref(false),
    unknown = ref(false),
    notice = ref("");
  const lastEffect = shallowRef<SourceOperation<SourceEffectAction> | null>(
    first.operation && isSourceEffect(first.operation) ? first.operation : null,
  );
  const draft = reactive({ ...first.model.defaults });
  const reviewedSource = shallowRef<Source | null>(first.model.selected?.source ?? null);
  const targetSource = shallowRef<Source | null>(null);
  const selectedBinding = shallowRef<Binding | null>(null);
  let active = true,
    readGeneration = 0;
  let awaiting: { sequence: number; action: SourceAction; input: Record<string, unknown> } | null =
    null;
  const locked = computed(() => unknown.value || page.value.operation?.status === "unconfirmed");
  const disabled = computed(
    () => pending.value || locked.value || stale.value || page.value.read_error,
  );
  const dirty = computed(
    () => !same(draft, first.model.defaults) || !!selectedBinding.value || !!targetSource.value,
  );
  const dispose = port.guardNavigation?.(
    () =>
      !pending.value &&
      !locked.value &&
      (!dirty.value ||
        window.confirm(
          "Leave this page and discard the unsaved registration and binding selection?",
        )),
  );
  onBeforeUnmount(() => {
    active = false;
    readGeneration++;
    dispose?.();
  });
  function selectBinding(binding: Binding | null) {
    selectedBinding.value = binding ? { ...binding } : null;
  }
  function accept(value: unknown): boolean {
    const next = admitSourcePage(value, first.model.context, first.model.mode);
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
    if (next.sequence === page.value.sequence && !same(next.operation, page.value.operation))
      return false;
    page.value = next;
    stale.value = false;
    if (next.operation && isSourceEffect(next.operation)) lastEffect.value = next.operation;
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
        ? "The outcome is still unconfirmed. Inspect the source audit before taking another action."
        : "Source evidence refreshed. Unsaved inputs were retained.";
    } catch {
      if (active && generation === readGeneration) {
        stale.value = true;
        notice.value =
          "The current evidence could not be read. Your inputs are retained; refresh before continuing.";
      }
    }
  }
  async function execute<A extends SourceAction>(action: A, input: SourceInputs[NoInfer<A>]) {
    if ((disabled.value && action !== "read-page") || pending.value || locked.value) return;
    if (!validInput(input, action)) {
      notice.value = "Check the required fields and input lengths before continuing.";
      return;
    }
    readGeneration++;
    pending.value = true;
    notice.value = "";
    const sequence = page.value.sequence + 1;
    awaiting = { sequence, action, input: structuredClone(input) };
    try {
      const value = await port.execute(action, { sequence, payload: input });
      if (!active) return;
      const op = admitSourceOperation(value, page.value);
      if (!op || op.sequence !== sequence || op.action !== action || !same(op.input, input))
        throw Error("unconfirmed");
      page.value = { ...page.value, sequence, operation: op };
      if (isSourceEffect(op)) lastEffect.value = op;
      unknown.value = op.status === "unconfirmed";
      if (!unknown.value) awaiting = null;
      await refresh();
      if (op.status === "rejected")
        notice.value =
          "The operation was not accepted. Review current evidence, permissions and input values before trying again.";
      if (op.action === "validate-registration" && op.status === "completed")
        notice.value = op.result.valid
          ? "The source configuration is valid for registration."
          : "The source configuration or credential reference is unavailable. Check the identity and configuration.";
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
    reviewedSource,
    targetSource,
    acceptSource: () => {
      reviewedSource.value = page.value.model.selected?.source ?? null;
    },
    selectTarget: (source: Source | null) => {
      targetSource.value = source ? { ...source } : null;
    },
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
