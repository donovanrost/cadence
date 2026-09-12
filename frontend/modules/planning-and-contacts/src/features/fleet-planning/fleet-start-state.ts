import { computed, onBeforeUnmount, reactive, ref, shallowRef, watch } from "vue";
import type {
  FleetStartPort,
  FleetStartReview,
  FleetStartReceipt,
} from "./OpsFleetPlanningNew.contracts";
import {
  admitFleetStart,
  admitFleetStartReview,
  admitFleetStartReceipt,
  fleetCompletion,
  fleetWindow,
} from "./fleet-start";
export function useFleetStart(input: () => unknown, port?: FleetStartPort) {
  const model = shallowRef(admitFleetStart(input(), port?.context));
  let context = port?.context ?? model.value?.context,
    generation = 0,
    active = true;
  const pending = ref<"preview" | "create" | "read" | null>(null),
    notice = ref(""),
    uncertain = ref(false);
  const review = shallowRef<FleetStartReview | null>(null),
    receipt = shallowRef<FleetStartReceipt | null>(null);
  const draft = reactive({
    horizon_start: model.value?.defaults.horizon_start.slice(0, 19) ?? "",
    horizon_end: model.value?.defaults.horizon_end.slice(0, 19) ?? "",
    include_recurring: model.value?.defaults.include_recurring ?? false,
  });
  watch(draft, () => {
    review.value = null;
    notice.value = "";
  });
  watch(input, (v) => {
    if (pending.value === "create") uncertain.value = true;
    generation++;
    pending.value = null;
    model.value = admitFleetStart(v, context);
    context ??= model.value?.context;
    review.value = null;
  });
  onBeforeUnmount(() => {
    active = false;
    generation++;
  });
  const current = (n: number) => active && generation === n;
  const locked = computed(() => !!pending.value || uncertain.value || !!receipt.value);
  const window = computed(() => fleetWindow(draft));
  const withinHorizon = computed(
    () =>
      !!window.value &&
      !!model.value?.policy &&
      Date.parse(window.value.horizon_end) - Date.parse(window.value.horizon_start) <=
        model.value.policy.max_horizon_seconds * 1000,
  );
  const canPreview = computed(() => !!port && !locked.value && withinHorizon.value);
  const canCreate = computed(
    () =>
      canPreview.value &&
      !!review.value &&
      review.value.requirements.total + review.value.eligible_occurrence_count > 0,
  );
  async function preview(requirements_page = 1, templates_page = 1) {
    if (!canPreview.value || !model.value || !window.value || !port) return;
    const captured = { ...window.value },
      base = model.value,
      n = ++generation;
    pending.value = "preview";
    review.value = null;
    notice.value = "";
    try {
      const value: any = fleetCompletion(
        await port.execute("preview", { fleet_run: captured, requirements_page, templates_page }),
      );
      if (!current(n)) return;
      const admitted = admitFleetStartReview(value?.review, base, captured, {
        requirements_page,
        templates_page,
      });
      if (!admitted) throw Error("Unavailable review");
      review.value = admitted;
      notice.value = "Review the exact inputs below before creating the run.";
    } catch {
      if (current(n))
        notice.value =
          "Fleet inputs could not be reviewed. Refresh the policy and try reviewing again.";
    } finally {
      if (current(n)) pending.value = null;
    }
  }
  async function create() {
    if (!canCreate.value || !review.value || !port) return;
    const captured = review.value,
      n = ++generation;
    pending.value = "create";
    notice.value = "";
    try {
      const value = fleetCompletion(
        await port.execute("create", {
          fleet_run: { ...captured.window },
          evidence: { ...captured.evidence },
        }),
      );
      if (!current(n)) return;
      const admitted = admitFleetStartReceipt(value, captured);
      if (!admitted) throw Error("Unavailable creation receipt");
      receipt.value = admitted;
      notice.value = "The queued run was created. Open it to review and continue planning.";
    } catch {
      if (current(n)) {
        uncertain.value = true;
        notice.value =
          "Creation has no confirmed receipt. Check the run directory before starting another run.";
      }
    } finally {
      if (current(n)) pending.value = null;
    }
  }
  async function refresh() {
    if (!port || pending.value) return;
    const n = ++generation;
    pending.value = "read";
    try {
      const value = await port.refresh();
      if (!current(n)) return;
      const admitted = admitFleetStart(value, context);
      if (!admitted) throw Error("Unavailable policy");
      context ??= admitted.context;
      model.value = admitted;
      review.value = null;
      if (!draft.horizon_start) {
        draft.horizon_start = admitted.defaults.horizon_start.slice(0, 19);
        draft.horizon_end = admitted.defaults.horizon_end.slice(0, 19);
        draft.include_recurring = admitted.defaults.include_recurring;
      }
      notice.value = "Policy refreshed. Review the inputs for this horizon again.";
    } catch {
      if (current(n)) notice.value = "Policy refresh failed. Previous evidence is retained.";
    } finally {
      if (current(n)) pending.value = null;
    }
  }
  return {
    model,
    draft,
    pending,
    notice,
    review,
    receipt,
    uncertain,
    locked,
    canPreview,
    canCreate,
    window,
    withinHorizon,
    preview,
    create,
    refresh,
    connected: !!port,
  };
}
