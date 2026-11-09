<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { canAdministerOrganization, TakeoverHeader, useMissionScope, useSession } from "@/shell";
import type { ApiError } from "@/api";
import { ApButton, ApCallout, ApStationBar } from "@/ui";
import { editableStates, type Acknowledgement } from "./api.ts";
import DayNav from "./DayNav.vue";
import DemandPanel from "./DemandPanel.vue";
import DraftGantt from "./DraftGantt.vue";
import { dayLabel, useSpacecraftNames } from "./names.ts";
import PlanFooter from "./PlanFooter.vue";
import { planHeaderTail } from "./plan-primary.ts";
import PlanStatePanel from "./PlanStatePanel.vue";
import SelectedPanel from "./SelectedPanel.vue";
import { planErrorText } from "./errors.ts";
import SubmitSheet from "./SubmitSheet.vue";
import SupersededCallout from "./SupersededCallout.vue";
import { stationHits } from "./unavailable.ts";
import { planPrimary } from "./plan-primary.ts";
import type { PlanView } from "./plan-state.ts";
import { usePlanDay } from "./usePlanDay.ts";

/** K1 · Plan a day (ScheduleFlow.md). States: plan-state.ts; data: usePlanDay. */
const route = useRoute();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const day = computed(() => {
  const q = route.query.day;
  return typeof q === "string" && /^\d{4}-\d{2}-\d{2}$/.test(q)
    ? q
    : new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
});
const focused = ref<string | null>(null);
const {
  view,
  busy,
  actionError,
  draftDay,
  resume,
  submit,
  execute,
  edit,
  alternatives,
  availability,
} = usePlanDay(missionId, day, focused);
const session = useSession();
const isAdmin = computed(() => canAdministerOrganization(session, scope.value.organization));
const sheet = ref<InstanceType<typeof SubmitSheet> | null>(null);
const sheetError = ref<ApiError | null>(null);
/** U26: drafted passes inside station outage/maintenance (blocking) or degraded (at risk) windows. */
const hits = computed(() =>
  view.value.kind === "plan"
    ? stationHits(view.value.plan, availability.value)
    : { blocking: [], atRisk: [] },
);
const primary = computed(() =>
  view.value.kind === "plan" ? planPrimary(view.value.plan, isAdmin.value) : null,
);

async function onSubmit(acks: Acknowledgement[]) {
  if (view.value.kind !== "plan") return;
  const result = await submit(view.value.plan, acks);
  if (result.ok) sheet.value?.close();
  else sheetError.value = result.error;
}
const editable = computed(
  () => view.value.kind === "plan" && editableStates.includes(view.value.plan.state),
);
function onEdit(change: { add?: string[]; remove?: string[] }) {
  if (view.value.kind !== "plan") return;
  void edit(view.value.plan, change);
  selected.value = null;
}
const actionText = computed(() => (actionError.value ? planErrorText(actionError.value) : null));
function onExecute() {
  if (view.value.kind === "plan") void execute(view.value.plan.id);
}
const nameOf = useSpacecraftNames(missionId);
const selected = ref<string | null>(null);

const STEPS = ["Demand", "Opportunities", "Draft", "Reserve"];
const step = computed(() =>
  view.value.kind === "drafting" ? 2 : view.value.kind === "plan" ? 2 : 0,
);
/** Header mono line per state (ScheduleFlow "K1 plan states"). */
function headerFor(v: PlanView, d: string): string {
  switch (v.kind) {
    case "not_set_up":
      return "Contact plan · not set up";
    case "no_draft":
      return `Contact plan · ${d} · no draft`;
    case "drafting":
      return `Drafting · ${(v.phase ?? "queued").replaceAll("_", " ")}`;
    case "interrupted":
      return "Drafting stopped";
    case "draft_failed":
    case "failed":
      return `Contact plan · ${d}`;
    case "loading":
      return `Contact plan · ${d}`;
    case "plan":
      return v.plan.superseded
        ? `Contact plan · R${v.plan.version} draft · superseded`
        : `Contact plan · R${v.plan.version} ${v.plan.state.replaceAll("_", " ")} · ${planHeaderTail(v.plan)}`;
  }
}
const headerLine = computed(() => headerFor(view.value, dayLabel(day.value)));
const setupLink = computed(() => ({ name: "setup.contact-planning" }));
</script>

<template>
  <TakeoverHeader
    :title="`Plan ${dayLabel(day)}`"
    :context="headerLine"
    :close="{ name: 'ops.contacts' }"
    close-label="Close plan"
    title-as="h1"
  >
    <template #steps><ApStationBar :steps="STEPS" :current="step" label="Plan steps" /></template>
  </TakeoverHeader>
  <DayNav :day="day" />
  <template v-if="view.kind === 'plan'">
    <SupersededCallout v-if="view.plan.superseded" :superseded="view.plan.superseded" />
    <div
      class="grid min-h-0 flex-1 grid-cols-1 gap-3 console:grid-cols-[300px_minmax(0,1fr)_340px]"
    >
      <DemandPanel
        :plan="view.plan"
        :name-of="nameOf"
        :focused="focused"
        @focus="focused = focused === $event ? null : $event"
      />
      <DraftGantt
        :plan="view.plan"
        :day="day"
        :name-of="nameOf"
        :focused="focused"
        :selected="selected"
        :alternatives="alternatives"
        :availability="availability"
        :muted="view.plan.superseded !== null"
        @select="selected = $event"
      />
      <SelectedPanel
        :plan="view.plan"
        :selected="selected"
        :focused="focused"
        :alternatives="alternatives"
        :name-of="nameOf"
        :editable="editable"
        :busy="busy"
        @add="onEdit({ add: [$event] })"
        @remove="onEdit({ remove: [$event] })"
        :hits="hits"
        @focus="focused = $event"
        @select="selected = $event"
      />
    </div>
    <ApCallout v-if="actionText" tone="caution">{{ actionText }}</ApCallout>
    <PlanFooter
      :plan="view.plan"
      :is-admin="isAdmin"
      :busy="busy"
      @sheet="sheet?.open()"
      @redraft="draftDay"
      @execute="onExecute"
    />
    <SubmitSheet
      v-if="primary?.kind === 'sheet'"
      ref="sheet"
      v-model:error="sheetError"
      :plan="view.plan"
      :name-of="nameOf"
      :commit-label="primary.label"
      :confirm="primary.confirm"
      :busy="busy"
      @submit="onSubmit"
    />
  </template>
  <template v-else>
    <PlanStatePanel :view="view" />
    <ApCallout v-if="actionText" tone="caution">{{ actionText }}</ApCallout>
    <footer class="flex flex-none justify-end border-t border-hairline pt-3">
      <ApButton v-if="view.kind === 'not_set_up'" variant="primary" size="commit" :to="setupLink"
        >Set up contact planning</ApButton
      >
      <ApButton
        v-else-if="view.kind === 'no_draft' || view.kind === 'draft_failed'"
        variant="primary"
        size="commit"
        :disabled="busy"
        @click="draftDay"
        >Draft the day</ApButton
      >
      <ApButton
        v-else-if="view.kind === 'interrupted'"
        variant="primary"
        size="commit"
        :disabled="busy"
        @click="resume"
        >Continue drafting</ApButton
      >
    </footer>
  </template>
</template>
