import { computed, onScopeDispose, ref, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { decoders as d, useRemoteQuery, type ApiError } from "@/api";
import { useChannelEvent, useMissionInvalidation } from "@/live";
import {
  continueDraft,
  fetchPlan,
  fetchRepair,
  startRepair,
  submitPlan,
  type Acknowledgement,
  type PlanDetail,
} from "./api.ts";

const progressReader = d.object({ kind: d.string, id: d.token, state: d.string });

/**
 * K2 v1 data owner (DECISIONS #25): the source plan (`?plan=`), the repair run (`?run=`, S8,
 * followed by progress events + a 5 s poll while running), and start / continue / apply (S5 on the
 * new plan).
 */
export function useReplan(missionId: Readonly<Ref<string>>) {
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
  useMissionInvalidation(missionId, ["contacts"], () => {
    source.refetch();
    if (runId.value) repair.refetch();
  });
  const poll = setInterval(() => {
    const s = repair.state.value;
    if (runId.value && s.status === "ready" && ["queued", "running"].includes(s.value.run.state))
      repair.refetch();
  }, 5_000);
  onScopeDispose(() => clearInterval(poll));

  async function propose() {
    if (!planId.value) return;
    busy.value = true;
    actionError.value = null;
    try {
      const result = await startRepair(missionId.value, planId.value, crypto.randomUUID());
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

  async function apply(plan: PlanDetail, acks: readonly Acknowledgement[]) {
    busy.value = true;
    try {
      const result = await submitPlan(missionId.value, plan, crypto.randomUUID(), acks);
      repair.refetch();
      source.refetch();
      return result;
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
  };
}
