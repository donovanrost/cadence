<script setup lang="ts">
import { computed, ref } from "vue";
import { describeApiError, type ApiError } from "@/api";
import { canAdministerOrganization, TakeoverHeader, useMissionScope, useSession } from "@/shell";
import { ApButton, ApCallout, ApPanel, ApRemote, ApStationBar, plural } from "@/ui";
import { repairableStates, type Acknowledgement, type PlanDetail } from "./api.ts";
import ChangesPanel from "./ChangesPanel.vue";
import DraftGantt from "./DraftGantt.vue";
import { useSpacecraftNames } from "./names.ts";
import PlanFooter from "./PlanFooter.vue";
import { planPrimary } from "./plan-primary.ts";
import type { PlanView } from "./plan-state.ts";
import PlanStatePanel from "./PlanStatePanel.vue";
import SubmitSheet from "./SubmitSheet.vue";
import { useReplan } from "./useReplan.ts";

/** K2 v1 · Re-plan after provider changes (DECISIONS #25), entered from a plan (`?plan=`). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { planId, runId, source, repair, busy, actionError, propose, resume, apply } =
  useReplan(missionId);
const nameOf = useSpacecraftNames(missionId);
const session = useSession();
const isAdmin = computed(() => canAdministerOrganization(session, scope.value.organization));
const sheet = ref<InstanceType<typeof SubmitSheet> | null>(null);
const sheetError = ref<ApiError | null>(null);
const STEPS = ["Impact", "Proposal", "Apply"];

/** The repair run as a K1 view for the shared state panel (drafting / interrupted / failed). */
const runView = computed<Exclude<PlanView, { kind: "plan" }> | null>(() => {
  const r = repair.value;
  if (!runId.value) return null;
  if (r.status === "loading") return { kind: "loading" };
  if (r.status === "failed") return { kind: "failed", error: r.error };
  const { run, plan, diff } = r.value;
  if (run.state === "queued" || run.state === "running")
    return { kind: "drafting", phase: run.phase, startedAt: run.started_at };
  if (run.state === "interrupted") return { kind: "interrupted", phase: run.phase };
  if (run.state === "failed" || run.state === "canceled")
    return { kind: "draft_failed", message: run.failure?.message ?? "The re-plan failed." };
  return plan && diff
    ? null
    : { kind: "draft_failed", message: "The re-plan finished without a proposal." };
});
const proposal = computed(() =>
  repair.value.status === "ready" && repair.value.value.plan && repair.value.value.diff
    ? repair.value.value
    : null,
);
const step = computed(() => (proposal.value ? 1 : 0));
const applyLabel = (plan: PlanDetail) =>
  !isAdmin.value
    ? `Request approval for r${plan.version}`
    : plan.unmet.length > 0
      ? `Accept ${plural(plan.unmet.length, "gap")} and apply r${plan.version}`
      : `Apply r${plan.version} · book ${plural(plan.counts.passes, "pass", "passes")}`;
const primary = computed(() =>
  proposal.value?.plan ? planPrimary(proposal.value.plan, isAdmin.value) : null,
);
const span = computed(() => {
  const r = repair.value;
  return r.status === "ready"
    ? { from: Date.parse(r.value.run.horizon.from), to: Date.parse(r.value.run.horizon.to) }
    : undefined;
});
const context = computed(() => {
  const s = source.value;
  return s.status === "ready"
    ? `Re-plan · live plan r${s.value.version} · ${s.value.state.replaceAll("_", " ")}`
    : "Re-plan";
});
async function onApply(acks: Acknowledgement[]) {
  const plan = proposal.value?.plan;
  if (!plan) return;
  const result = await apply(plan, acks);
  if (result.ok) sheet.value?.close();
  else sheetError.value = result.error;
}
</script>

<template>
  <TakeoverHeader
    title="Re-plan after provider changes"
    :context="context"
    :close="{ name: 'ops.contacts' }"
    close-label="Close re-plan"
    title-as="h1"
  >
    <template #steps
      ><ApStationBar :steps="STEPS" :current="step" label="Re-plan steps"
    /></template>
  </TakeoverHeader>
  <ApPanel v-if="!planId" index="A" title="Impact">
    <ApCallout tone="info"
      >Open a re-plan from a contact plan that has rejected or failed bookings.</ApCallout
    >
  </ApPanel>
  <ApRemote v-else :state="source" loading-label="Loading the live plan…">
    <template #default="{ value: live }">
      <PlanStatePanel v-if="runView" :view="runView" />
      <template v-else-if="proposal && proposal.plan && proposal.diff">
        <div class="grid min-h-0 flex-1 grid-cols-1 gap-3 console:grid-cols-[minmax(0,1fr)_360px]">
          <div class="flex min-h-0 flex-col gap-3">
            <DraftGantt
              :plan="live"
              day=""
              :span="span"
              index="B1"
              :title="`Live plan r${live.version}`"
              :name-of="nameOf"
              :focused="null"
              :selected="null"
            />
            <DraftGantt
              :plan="proposal.plan"
              day=""
              :span="span"
              index="B2"
              :title="`Proposed r${proposal.plan.version}`"
              :name-of="nameOf"
              :focused="null"
              :selected="null"
            />
          </div>
          <ChangesPanel :diff="proposal.diff" :plan="proposal.plan" :name-of="nameOf" />
        </div>
        <PlanFooter
          :plan="proposal.plan"
          :is-admin="isAdmin"
          :busy="busy"
          :sheet-label="applyLabel(proposal.plan)"
          @sheet="sheet?.open()"
        />
        <SubmitSheet
          v-if="primary?.kind === 'sheet'"
          ref="sheet"
          v-model:error="sheetError"
          :plan="proposal.plan"
          :name-of="nameOf"
          :commit-label="applyLabel(proposal.plan)"
          :confirm="primary.confirm"
          :busy="busy"
          @submit="onApply"
        />
      </template>
      <ApPanel v-else index="A" title="Impact">
        <ApCallout v-if="!repairableStates.includes(live.state)" tone="info">
          Live plan r{{ live.version }} is {{ live.state.replaceAll("_", " ") }}. Re-plan applies to
          plans with rejected or failed bookings.
        </ApCallout>
        <p v-else class="m-0 text-base text-text-3">
          Live plan r{{ live.version }} is {{ live.state.replaceAll("_", " ") }}:
          {{ plural(live.counts.passes, "pass", "passes")
          }}<template v-if="live.unmet.length > 0">, {{ live.unmet.length }} not covered</template>.
          A re-plan keeps every committed pass and re-plans the rest. Nothing is booked until you
          apply it.
        </p>
      </ApPanel>
      <ApCallout v-if="actionError" tone="caution">{{ describeApiError(actionError) }}</ApCallout>
      <footer v-if="!proposal" class="flex flex-none justify-end border-t border-hairline pt-3">
        <ApButton
          v-if="!runId && repairableStates.includes(live.state)"
          variant="primary"
          size="commit"
          :disabled="busy"
          @click="propose"
          >Propose a re-plan</ApButton
        >
        <ApButton
          v-else-if="runView?.kind === 'interrupted'"
          variant="primary"
          size="commit"
          :disabled="busy"
          @click="resume"
          >Continue re-planning</ApButton
        >
      </footer>
    </template>
  </ApRemote>
</template>
