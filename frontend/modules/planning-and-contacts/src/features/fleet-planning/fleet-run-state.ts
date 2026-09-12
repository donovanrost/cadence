import { computed, onBeforeUnmount, reactive, ref, shallowRef, watch } from "vue";
import type { FleetRunPort, FleetRunReceipt } from "./OpsFleetPlanningRun.contracts";
import { admitFleetRun, fleetRunReceipt } from "./fleet-run";
import { fleetCompletion, fleetWindow } from "./fleet-start";
export function useFleetRun(input: () => unknown, port?: FleetRunPort) {
  const model = shallowRef(admitFleetRun(input(), port?.context));
  let context = port?.context ?? model.value?.context,
    identity = model.value ? { id: model.value.id, query: model.value.query } : undefined,
    generation = 0,
    active = true;
  const pending = ref<"read" | "continue" | "repair" | null>(null),
    notice = ref(""),
    uncertain = ref(false),
    receipt = shallowRef<FleetRunReceipt | null>(null);
  const draft = reactive({
    horizon_start: model.value?.repair.defaults?.horizon_start.slice(0, 19) ?? "",
    horizon_end: model.value?.repair.defaults?.horizon_end.slice(0, 19) ?? "",
  });
  function accept(value: unknown) {
    const next = admitFleetRun(value, context, identity);
    if (!next) return false;
    context ??= next.context;
    identity ??= { id: next.id, query: next.query };
    model.value = next;
    if (!draft.horizon_start && next.repair.defaults) {
      draft.horizon_start = next.repair.defaults.horizon_start.slice(0, 19);
      draft.horizon_end = next.repair.defaults.horizon_end.slice(0, 19);
    }
    return true;
  }
  watch(input, (value) => {
    if (pending.value === "continue" || pending.value === "repair") uncertain.value = true;
    generation++;
    pending.value = null;
    if (!accept(value)) model.value = null;
  });
  onBeforeUnmount(() => {
    active = false;
    generation++;
  });
  const current = (n: number) => active && generation === n;
  const locked = computed(
    () =>
      !!pending.value ||
      uncertain.value ||
      receipt.value?.outcome === "repair_created" ||
      (!!receipt.value &&
        model.value?.evidence.sha256 === (receipt.value.evidence as { sha256: string }).sha256),
  );
  const repairWindow = computed(() => fleetWindow({ ...draft, include_recurring: false }));
  const withinHorizon = computed(
    () =>
      !!repairWindow.value &&
      !!model.value?.repair.policy &&
      Date.parse(repairWindow.value.horizon_end) - Date.parse(repairWindow.value.horizon_start) <=
        model.value.repair.policy.max_repair_horizon_seconds * 1000,
  );
  const canContinue = computed(() => !!port && !locked.value && model.value?.can_continue === true);
  const canRepair = computed(
    () => !!port && !locked.value && model.value?.repair.available === true && withinHorizon.value,
  );
  async function refresh() {
    if (!port || pending.value) return;
    const n = ++generation;
    pending.value = "read";
    try {
      const next = await port.refresh();
      if (!current(n)) return;
      if (!accept(next)) throw Error("Unavailable run");
      notice.value = "Run evidence refreshed.";
    } catch {
      if (current(n)) notice.value = "Run refresh failed. Previous evidence is retained.";
    } finally {
      if (current(n)) pending.value = null;
    }
  }
  async function execute(action: "continue" | "repair") {
    if (!port || !model.value || (action === "continue" ? !canContinue.value : !canRepair.value))
      return;
    const captured = model.value,
      n = ++generation;
    pending.value = action;
    notice.value = "";
    const input: Record<string, unknown> = {
      fleet_planning_run_id: captured.id,
      evidence: { ...(action === "continue" ? captured.evidence : captured.repair.evidence) },
    };
    if (action === "repair")
      input.repair = {
        horizon_start: repairWindow.value!.horizon_start,
        horizon_end: repairWindow.value!.horizon_end,
      };
    try {
      const result = fleetCompletion(await port.execute(action, input));
      if (!current(n)) return;
      const confirmed = fleetRunReceipt(result, captured, action);
      if (!confirmed) throw Error("Unavailable receipt");
      receipt.value = confirmed;
      notice.value =
        action === "continue"
          ? "Planning completed. Refresh to inspect the resulting evidence."
          : "A queued repair run was created with the reviewed locked commitments.";
    } catch {
      if (current(n)) {
        uncertain.value = true;
        notice.value =
          "The action has no confirmed receipt. Refresh the evidence and inspect the run directory before another attempt.";
      }
    } finally {
      if (current(n)) pending.value = null;
    }
  }
  return {
    model,
    draft,
    pending,
    notice,
    uncertain,
    receipt,
    locked,
    withinHorizon,
    canContinue,
    canRepair,
    refresh,
    execute,
    connected: !!port,
  };
}
