<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { TakeoverHeader, useMissionScope } from "@/shell";
import { ApButton, ApEmptyState, ApPanel, ApStationBar } from "@/ui";

/**
 * K2 v1 · Re-plan after provider changes (DECISIONS #25): entered from a plan (`?plan=`) or a
 * rejected reservation (`?reservation=`). Skeleton until api ships S8 (repair proposal + apply).
 */
const route = useRoute();
const scope = useMissionScope();
const subject = computed(() =>
  typeof route.query.plan === "string"
    ? `plan ${route.query.plan}`
    : typeof route.query.reservation === "string"
      ? `reservation ${route.query.reservation}`
      : null,
);
const STEPS = ["Impact", "Proposal", "Apply"];
const legacy = computed(
  () => `/missions/${encodeURIComponent(scope.value.mission.id)}/ops/planning`,
);
</script>

<template>
  <TakeoverHeader
    title="Re-plan after provider changes"
    :context="subject ? `Re-plan · ${subject}` : 'Re-plan'"
    :close="{ name: 'ops.contacts' }"
    close-label="Close re-plan"
    title-as="h1"
  >
    <template #steps>
      <ApStationBar :steps="STEPS" :current="0" label="Re-plan steps" />
    </template>
  </TakeoverHeader>
  <ApPanel index="A" title="Impact" flush>
    <ApEmptyState
      state="off"
      headline="Re-planning isn't connected to the console yet"
      sentence="Cadence can repair a plan around rejected or cancelled reservations. Until the repair reads land here, start a repair from the planning run in the existing pages."
    >
      <ApButton :href="legacy">Open fleet planning ↗</ApButton>
    </ApEmptyState>
  </ApPanel>
</template>
