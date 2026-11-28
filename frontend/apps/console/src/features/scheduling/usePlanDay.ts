import type { MissionId } from "@/api/index.ts";
import { markPlanAct } from "./plan-acts.ts";
import { computed, ref, shallowRef, watch, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { decoders as d, isError, useRemoteQuery, type ApiError } from "@/api";
import { useChannelEvent, useMissionInvalidation } from "@/live";
import {
  continueDraft,
  editPlan,
  executePlan,
  fetchAlternatives,
  fetchAvailability,
  fetchDayDemand,
  fetchDraft,
  fetchPlan,
  fetchPlans,
  fetchSetup,
  type PlanningSetup,
  rejectPlan,
  startDraft,
  type Acknowledgement,
  type PlanDetail,
} from "./api.ts";
import { openProposal, planOfDay, planView } from "./plan-state.ts";
import { reviewOps, runReview, type ReviewAct } from "./review-run.ts";

const progressReader = d.object({
  kind: d.known(["draft", "execute"]),
  id: d.token,
  // free-text: only triggers a refetch; never shown or compared
  state: d.string,
});

/**
 * K1 data owner: the day's plans (S6), the draft run named by `?run=` (S3, followed by
 * `scheduling_progress` and `contact_plans` invalidations), the current plan's detail, and the
 * start / continue actions. Exposes one derived `view`.
 */
export function usePlanDay(
  missionId: Readonly<Ref<MissionId>>,
  day: Readonly<Ref<string>>,
  focused: Readonly<Ref<string | null>>,
) {
  const route = useRoute();
  const router = useRouter();
  const runId = computed(() => (typeof route.query.run === "string" ? route.query.run : null));
  /** Fallback when a draft request is refused before the setup read caught up. */
  const refusedNotSetUp = ref<readonly string[] | null>(null);
  const setup = useRemoteQuery(
    computed(() => ({ m: missionId.value, day: day.value })),
    (k, signal) => fetchSetup(k.m, k.day, signal),
  );
  /**
   * Set-up-ness isn't per day: keep the last answer while another day's setup loads, so the
   * no-plan branch doesn't flash between 'not set up' and 'no draft' (fe-ops). The estimate is per
   * day, so it reads only the current answer.
   */
  const lastSetup = shallowRef<PlanningSetup | null>(null);
  watch(setup.state, (s) => {
    if (s.status === "ready") lastSetup.value = s.value.setup;
  });
  /** U52: the day's template fan-out against the limit, with each template's per-run cap. */
  const estimate = computed(() =>
    setup.state.value.status === "ready"
      ? (setup.state.value.value.setup.template_requirements_estimate ?? null)
      : null,
  );
  const dayDemand = useRemoteQuery(
    () => `${missionId.value}|${day.value}`,
    (_k, signal) => fetchDayDemand(missionId.value, day.value, signal),
  );
  const notSetUp = computed<readonly string[] | null>(() => {
    const s = lastSetup.value;
    if (s && !s.ready) return s.missing;
    return refusedNotSetUp.value;
  });
  const actionError = ref<ApiError | null>(null);
  const busy = ref(false);

  const plans = useRemoteQuery(
    () => `${missionId.value}|${day.value}`,
    (_k, signal) => fetchPlans(missionId.value, day.value, signal),
  );
  const draft = useRemoteQuery(runId, (id, signal) => fetchDraft(missionId.value, id, signal));
  /** U61: `?plan=` opens one plan of the day (a refusal's or a superseded line's Open R44). */
  const pinnedPlan = computed(() =>
    typeof route.query.plan === "string" && route.query.plan ? route.query.plan : null,
  );
  const planId = computed(() => {
    if (runId.value) return null;
    if (pinnedPlan.value) return pinnedPlan.value;
    const p = plans.state.value;
    return p.status === "ready" ? (planOfDay(p.value.plans)?.id ?? null) : null;
  });
  /** U73 A10: `?version=N` opens an older version of the plan, read-only. */
  const version = computed(() => {
    const v = Number(route.query.version);
    return Number.isInteger(v) && v > 0 ? v : null;
  });
  const plan = useRemoteQuery(
    computed(() => (planId.value ? { id: planId.value, version: version.value } : null)),
    (k, signal) => fetchPlan(missionId.value, k.id, signal, k.version),
  );
  /** S7 station availability for the Gantt's outage / maintenance / degraded bands. */
  const availability = useRemoteQuery(missionId, (id, signal) => fetchAvailability(id, signal));
  useMissionInvalidation(missionId, ["stations"], availability.refetch);

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
  // S10 (api d13ed37c): `contact_plans` covers plan and fleet-run changes (approvals, execution,
  // supersession, the #52 window); `contacts` covers reservation changes. No poll: a reconnect
  // refetches (onResync), which also covers events lost across a server restart.
  useMissionInvalidation(missionId, ["contacts", "contact_plans"], () => {
    plans.refetch();
    if (runId.value) draft.refetch();
    else plan.refetch();
  });

  async function draftDay() {
    markPlanAct();
    busy.value = true;
    actionError.value = null;
    try {
      const result = await startDraft(missionId.value, day.value, crypto.randomUUID());
      if (result.ok) {
        refusedNotSetUp.value = null;
        await router.replace({ query: { ...route.query, run: result.value.run_id } });
      } else if (result.error.kind === "invalid" && isError(result.error, "planning_not_set_up")) {
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
    markPlanAct();
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

  /** #257 (U97): submit, approve, or the one act; op ids are reused for a retry of the same request. */
  const ops = reviewOps();
  async function review(
    act: ReviewAct,
    plan: PlanDetail,
    acknowledgements: readonly Acknowledgement[],
    note: string | undefined,
    userId: string,
  ) {
    busy.value = true;
    try {
      const ctx = { missionId: missionId.value, ops, userId, day: day.value };
      const result = await runReview(ctx, act, plan, acknowledgements, note);
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

  /** U28: an unapplied K2 repair proposal for the day (K1 links to it, never opens it). */
  const proposal = computed(() =>
    plans.state.value.status === "ready"
      ? openProposal(plans.state.value.value.repair_proposals)
      : null,
  );

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
  // #895: a finished pass-prediction run changes the alternatives' geometry.
  useMissionInvalidation(missionId, ["predicted_passes"], alternatives.refetch);

  /** Send back (admin, pending_approval): the plan returns to draft with the reason. */
  async function sendBack(plan: PlanDetail, reason: string) {
    busy.value = true;
    try {
      const result = await rejectPlan(missionId.value, plan, reason);
      refresh();
      return result;
    } finally {
      busy.value = false;
    }
  }

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
    proposal,
    busy,
    actionError,
    estimate,
    draftDay,
    resume,
    review,
    execute,
    edit,
    sendBack,
    alternatives: alternatives.state,
    availability: availability.state,
    refresh,
  };
}
