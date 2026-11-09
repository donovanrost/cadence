import { computed, onScopeDispose, ref, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { decoders as d, useRemoteQuery, type ApiError } from "@/api";
import { useChannelEvent } from "@/live";
import { continueDraft, fetchDraft, fetchPlan, fetchPlans, startDraft } from "./api.ts";
import { currentPlan, planView } from "./plan-state.ts";

const progressReader = d.object({ kind: d.string, id: d.token, state: d.string });

/**
 * K1 data owner: the day's plans (S6), the draft run named by `?run=` (S3, followed by
 * `scheduling_progress` and a 5 s poll while running), the current plan's detail, and the
 * start / continue actions. Exposes one derived `view`.
 */
export function usePlanDay(missionId: Readonly<Ref<string>>, day: Readonly<Ref<string>>) {
  const route = useRoute();
  const router = useRouter();
  const runId = computed(() => (typeof route.query.run === "string" ? route.query.run : null));
  const notSetUp = ref<readonly string[] | null>(null);
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
        notSetUp.value = null;
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
        notSetUp.value = details;
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

  const view = computed(() =>
    planView({
      notSetUp: notSetUp.value,
      runId: runId.value,
      draft: runId.value ? draft.state.value : null,
      plans: plans.state.value,
      plan: planId.value ? plan.state.value : null,
    }),
  );

  return {
    view,
    busy,
    actionError,
    draftDay,
    resume,
    refetch: () => (runId.value ? draft.refetch() : plans.refetch()),
  };
}
