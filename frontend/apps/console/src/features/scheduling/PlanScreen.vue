<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { TakeoverHeader, useMissionScope } from "@/shell";
import { ApButton, ApEmptyState, ApPanel, ApStationBar } from "@/ui";

/**
 * K1 · Plan a day (ScheduleFlow.md). Skeleton until api ships S1–S5 (docs/apogee/plans/scheduling.md):
 * the takeover frame and step bar are real; the body says plainly that planning isn't connected yet
 * and links to the existing planning pages.
 */
const route = useRoute();
const scope = useMissionScope();
const day = computed(() => {
  const q =
    typeof route.query.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(route.query.day)
      ? route.query.day
      : null;
  return q ?? new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
});
const STEPS = ["Demand", "Opportunities", "Draft", "Reserve"];
const legacy = computed(
  () => `/missions/${encodeURIComponent(scope.value.mission.id)}/ops/planning`,
);
</script>

<template>
  <TakeoverHeader
    :title="`Plan ${day}`"
    context="Contact plan"
    :close="{ name: 'ops.contacts' }"
    close-label="Close plan"
    title-as="h1"
  >
    <template #steps>
      <ApStationBar :steps="STEPS" :current="0" label="Plan steps" />
    </template>
  </TakeoverHeader>
  <ApPanel index="A" title="Plan the day" flush>
    <ApEmptyState
      state="off"
      headline="Planning isn't connected to the console yet"
      sentence="Cadence can already draft a day across providers. This screen will start from the spacecraft whose contact rule isn't met. Until the planning reads land, use the existing planning pages."
    >
      <ApButton :href="legacy">Open fleet planning ↗</ApButton>
    </ApEmptyState>
  </ApPanel>
</template>
