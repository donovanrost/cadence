<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { TakeoverHeader, useMissionScope } from "@/shell";
import { ApButton, ApStationBar } from "@/ui";
import DemandPanel from "./DemandPanel.vue";
import DraftGantt from "./DraftGantt.vue";
import { dayLabel, useSpacecraftNames } from "./names.ts";
import PlanFooter from "./PlanFooter.vue";
import PlanStatePanel from "./PlanStatePanel.vue";
import SelectedPanel from "./SelectedPanel.vue";
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
const { view, busy, draftDay, resume } = usePlanDay(missionId, day);
const nameOf = useSpacecraftNames(missionId);
const focused = ref<string | null>(null);
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
    case "plan": {
      const p = v.plan;
      const tail =
        p.conflicts.length > 0
          ? `${p.conflicts.length} conflicts`
          : p.unmet.length > 0
            ? `${p.unmet.length} not covered`
            : "ready";
      return `R${p.version} ${p.state.replaceAll("_", " ")} · ${tail}`;
    }
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
  <template v-if="view.kind === 'plan'">
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
        @select="selected = $event"
      />
      <SelectedPanel :plan="view.plan" :selected="selected" :name-of="nameOf" />
    </div>
    <PlanFooter :plan="view.plan" />
  </template>
  <template v-else>
    <PlanStatePanel :view="view" />
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
