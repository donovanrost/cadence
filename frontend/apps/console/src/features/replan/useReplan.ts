import type { MissionId } from "@/api/index.ts";
import { markPlanAct } from "@/features/scheduling/plan-acts.ts";
import { computed, ref, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { decoders as d, useRemoteQuery, type ApiError } from "@/api";
import { useChannelEvent, useMissionInvalidation } from "@/live";
import {
  continueDraft,
  executePlan,
  fetchPlan,
  fetchRepair,
  startRepair,
  type Acknowledgement,
  type PlanDetail,
} from "@/features/scheduling/index.ts";
import { reviewOps, runReview, type ReviewAct } from "@/features/scheduling/review-run.ts";

/** Only the run id matters: a progress event for this run refetches it. */
const progressReader = d.object({ id: d.token });

/**
 * K2 v1 data owner (DECISIONS #25): the source plan (`?plan=`), the repair run (`?run=`, S8,
 * followed by progress events + a 5 s poll while running), and start / continue / apply (S5 on the
 * new plan).
 */
export function useReplan(missionId: Readonly<Ref<MissionId>>) {
  const route = useRoute();
  const router = useRouter();
  const planId = computed(() => (typeof route.query.plan === "string" ? route.query.plan : null));
  const runId = computed(() => (typeof route.query.run === "string" ? route.query.run : null));
  const busy = ref(false);
  const actionError = ref<ApiError | null>(null);

  const source = useRemoteQuery(planId, (id, signal) => fetchPlan(missionId.value, id, signal));
  const repair = useRemoteQuery(runId, (id, signal) => fetchRepair(missionId.value, id, signal));

  useChannelEvent(
    computed(() => `mission:${missionId.value}`),
    "scheduling_progress",
    progressReader,
    {
      onEvent: (event) => {
        if (event.id === runId.value) repair.refetch();
      },
      onResync: () => repair.refetch(),
    },
  );
  // `contacts` fires per reservation change (Apply sends a burst); `contact_plans` on plan and
  // fleet-run changes (drafting, repair, execution, the #52 window), so no poll is needed.
  useMissionInvalidation(
    missionId,
    ["contacts", "contact_plans"],
    () => {
      source.refetch();
      if (runId.value) repair.refetch();
    },
    { throttleMs: 2_000 },
  );

  async function propose(window?: Readonly<{ from: string; to: string }>) {
    if (!planId.value) return;
    markPlanAct();
    busy.value = true;
    actionError.value = null;
    try {
      const result = await startRepair(missionId.value, planId.value, crypto.randomUUID(), window);
      if (result.ok) await router.replace({ query: { ...route.query, run: result.value.run_id } });
      else actionError.value = result.error;
    } finally {
      busy.value = false;
    }
  }

  async function resume() {
    if (!runId.value) return;
    busy.value = true;
    try {
      const result = await continueDraft(missionId.value, runId.value);
      if (!result.ok) actionError.value = result.error;
      repair.refetch();
    } finally {
      busy.value = false;
    }
  }

  /** #257 (U97): Apply submits, approves, or both (the one act); a retry reuses the op ids. */
  const ops = reviewOps();
  async function apply(
    act: ReviewAct,
    plan: PlanDetail,
    acks: readonly Acknowledgement[],
    note: string | undefined,
    userId: string,
  ) {
    busy.value = true;
    try {
      const ctx = {
        missionId: missionId.value,
        ops,
        userId,
        day: plan.window.from?.slice(0, 10) ?? "",
      };
      const result = await runReview(ctx, act, plan, acks, note);
      repair.refetch();
      source.refetch();
      return result;
    } finally {
      busy.value = false;
    }
  }

  /** Continue booking an interrupted proposal (S5 execute; items are idempotent). */
  async function execute(planId: string) {
    busy.value = true;
    actionError.value = null;
    try {
      const result = await executePlan(missionId.value, planId);
      if (!result.ok) actionError.value = result.error;
      repair.refetch();
      source.refetch();
    } finally {
      busy.value = false;
    }
  }

  return {
    planId,
    runId,
    source: source.state,
    repair: repair.state,
    busy,
    actionError,
    propose,
    resume,
    apply,
    execute,
    /** After a U32 resolution: the plans' unconfirmed lists and states changed. */
    refresh: () => {
      source.refetch();
      if (runId.value) repair.refetch();
    },
  };
}
