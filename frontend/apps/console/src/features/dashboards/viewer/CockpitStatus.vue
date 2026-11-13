<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { ClockCluster, useMissionScope } from "@/shell";
import { useFleet } from "@/features/fleet/index.ts";
import { ApStatusMark, stateTextClass } from "@/ui";

/**
 * The cockpit cluster (ux): fleet health counts (critical and caution link to Alarms, stale to
 * Fleet), then UTC. One fleet read per open dashboard, refreshed by invalidations (lead).
 */
const scope = useMissionScope();
const fleet = useFleet(
  computed(() => scope.value.mission.id),
  { live: false },
);
const chips = computed(() => {
  const s = fleet.state.value;
  if (s.status !== "ready") return [];
  const c = s.value.counts;
  return [
    { state: "crit" as const, count: c.critical, label: "critical", to: { name: "ops.alarms" } },
    { state: "caution" as const, count: c.caution, label: "caution", to: { name: "ops.alarms" } },
    { state: "stale" as const, count: c.stale, label: "stale", to: { name: "ops.fleet" } },
  ].filter((chip) => chip.count > 0);
});
</script>

<template>
  <ClockCluster>
    <RouterLink
      v-for="chip in chips"
      :key="chip.state"
      :to="chip.to"
      class="flex items-center gap-1.5 tabular-nums no-underline hover:underline"
      :class="stateTextClass(chip.state)"
      :aria-label="`${chip.count} spacecraft ${chip.label}`"
    >
      <ApStatusMark :state="chip.state" />{{ chip.count }}
    </RouterLink>
  </ClockCluster>
</template>
