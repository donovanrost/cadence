import { computed, onScopeDispose, ref, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { decoders as d, useRemoteQuery, type ApiError } from "@/api";
import { useChannelEvent, useMissionInvalidation } from "@/live";
import {
  continueDraft,
  editPlan,
  executePlan,
  fetchAlternatives,
  fetchDayDemand,
  fetchDraft,
  fetchPlan,
  fetchPlans,
  fetchSetup,
  startDraft,
  submitPlan,
  type Acknowledgement,
  type PlanDetail,
} from "./api.ts";
import { currentPlan, planView } from "./plan-state.ts";

const progressReader = d.object({ kind: d.string, id: d.token, state: d.string });

/**
 * K1 data owner: the day's plans (S6), the draft run named by `?run=` (S3, followed by
 * `scheduling_progress` and a 5 s poll while running), the current plan's detail, and the
 * start / continue actions. Exposes one derived `view`.
 */
export function usePlanDay(
  missionId: Readonly<Ref<string>>,
  day: Readonly<Ref<string>>,
  focused: Readonly<Ref<string | null>>,
) {
  const route = useRoute();
  const router = useRouter();
  const runId = computed(() => (typeof route.query.run === "string" ? route.query.run : null));
  /** Fallback when a draft request is refused before the setup read caught up. */
  const refusedNotSetUp = ref<readonly string[] | null>(null);
  const setup = useRemoteQuery(missionId, (id, signal) => fetchSetup(id, signal));
  const dayDemand = useRemoteQuery(
    () => `${missionId.value}|${day.value}`,
    (_k, signal) => fetchDayDemand(missionId.value, day.value, signal),
  );
  const notSetUp = computed<readonly string[] | null>(() => {
    const s = setup.state.value;
    if (s.status === "ready" && !s.value.setup.ready) return s.value.setup.missing;
    return refusedNotSetUp.value;
  });
  const actionError = ref<ApiError | null>(null);
  const busy = ref(false);

  const plans = useRemoteQuery(
    () => `${missionId.value}|${day.value}`,
    (_k, signal) => fetchPlans(missionId.value, day.value, signal),
  );
  const draft = useRemoteQuery(runId, (id, signal) => fetchDraft(missionId.value, id, signal));
  const planId = computed(() => {
    if (runId.value) return null;
    const p = plans.state.value;
    return p.status === "ready" ? (currentPlan(p.value.plans)?.id ?? null) : null;
  });
  const plan = useRemoteQuery(planId, (id, signal) => fetchPlan(missionId.value, id, signal));

  useChannelEvent(
    computed(() => `mission:${missionId.value}`),
    "scheduling_progress",
    progressReader,
    {
      onEvent: (event) => {
        if (event.id === runId.value) draft.refetch();
        plans.refetch();
      },
      onResync: () => {
        draft.refetch();
        plans.refetch();
      },
    },
  );
  // Reservation changes (booking confirmations / rejections) invalidate `contacts` (S10).
  useMissionInvalidation(missionId, ["contacts"], () => {
    plans.refetch();
    if (!runId.value) plan.refetch();
  });
  const poll = setInterval(() => {
    const s = draft.state.value;
    if (runId.value && s.status === "ready" && ["queued", "running"].includes(s.value.run.state))
      draft.refetch();
  }, 5_000);
  onScopeDispose(() => clearInterval(poll));

  async function draftDay() {
    busy.value = true;
    actionError.value = null;
    try {
      const result = await startDraft(missionId.value, day.value, crypto.randomUUID());
      if (result.ok) {
        refusedNotSetUp.value = null;
        await router.replace({ query: { ...route.query, run: result.value.run_id } });
      } else if (result.error.kind === "invalid" && result.error.code === "planning_not_set_up") {
        const missing = d.optional(d.object({ missing: d.array(d.string) }));
        const details = (() => {
          try {
            return missing(result.error.details)?.missing ?? [];
          } catch {
            return [];
          }
        })();
        refusedNotSetUp.value = details;
        setup.refetch();
      } else {
        actionError.value = result.error;
      }
    } finally {
      busy.value = false;
    }
  }

  async function resume() {
    if (!runId.value) return;
    busy.value = true;
    actionError.value = null;
    try {
      const result = await continueDraft(missionId.value, runId.value);
      if (!result.ok) actionError.value = result.error;
      draft.refetch();
    } finally {
      busy.value = false;
    }
  }

  /** S5: admin → approve + execute (202); member → pending_approval. The caller shows errors. */
  async function submit(plan: PlanDetail, acknowledgements: readonly Acknowledgement[]) {
    busy.value = true;
    try {
      const result = await submitPlan(missionId.value, plan, crypto.randomUUID(), acknowledgements);
      refresh();
      return result;
    } finally {
      busy.value = false;
    }
  }

  async function execute(planIdToRun: string) {
    busy.value = true;
    actionError.value = null;
    try {
      const result = await executePlan(missionId.value, planIdToRun);
      if (!result.ok) actionError.value = result.error;
      refresh();
    } finally {
      busy.value = false;
    }
  }

  function refresh() {
    plans.refetch();
    if (runId.value) draft.refetch();
    else plan.refetch();
  }

  const view = computed(() =>
    planView({
      notSetUp: notSetUp.value,
      runId: runId.value,
      draft: runId.value ? draft.state.value : null,
      plans: plans.state.value,
      plan: planId.value ? plan.state.value : null,
      demand: dayDemand.state.value.status === "ready" ? dayDemand.state.value.value : null,
    }),
  );

  /** S4: alternatives for the focused spacecraft on the current plan (nothing is written). */
  const currentPlanId = computed(() => (view.value.kind === "plan" ? view.value.plan.id : null));
  const currentVersion = computed(() =>
    view.value.kind === "plan" ? view.value.plan.version : null,
  );
  const alternatives = useRemoteQuery(
    () =>
      currentPlanId.value && focused.value
        ? `${currentPlanId.value}|${currentVersion.value}|${focused.value}`
        : null,
    (_k, signal) =>
      fetchAlternatives(missionId.value, currentPlanId.value ?? "", focused.value ?? "", signal),
  );

  /** S4 edit: a new plan version. A stale version (409 plan_changed) reloads and says so. */
  async function edit(plan: PlanDetail, change: Readonly<{ add?: string[]; remove?: string[] }>) {
    busy.value = true;
    actionError.value = null;
    try {
      const result = await editPlan(missionId.value, plan, change);
      if (!result.ok) actionError.value = result.error;
      refresh();
      alternatives.refetch();
    } finally {
      busy.value = false;
    }
  }

  return {
    view,
    busy,
    actionError,
    draftDay,
    resume,
    submit,
    execute,
    edit,
    alternatives: alternatives.state,
    refresh,
  };
}
