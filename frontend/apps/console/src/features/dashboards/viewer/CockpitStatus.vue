<script setup lang="ts">
import { computed } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";
import { useMissionScope } from "@/shell";
import { useFleet } from "@/features/fleet/index.ts";
import { ApStatusMark, stateTextClass } from "@/ui";

/**
 * The cockpit cluster (ux): fleet health counts (critical and caution link to Alarms, stale to
 * Fleet). The takeover header draws UTC itself (qa: it showed twice inside ClockCluster). One
 * fleet read per open dashboard, refreshed by invalidations (lead).
 */
const scope = useMissionScope();
const fleet = useFleet(
  computed(() => scope.value.mission.id),
  { live: false },
);
const alarms: RouteLocationRaw = { name: "ops.alarms" };
const fleetTo: RouteLocationRaw = { name: "ops.fleet" };
const chips = computed(() => {
  const s = fleet.state.value;
  if (s.status !== "ready") return [];
  const c = s.value.counts;
  return [
    { state: "crit" as const, count: c.critical, label: "critical", to: alarms },
    { state: "caution" as const, count: c.caution, label: "caution", to: alarms },
    { state: "stale" as const, count: c.stale, label: "stale", to: fleetTo },
  ].filter((chip) => chip.count > 0);
});
</script>

<template>
  <span v-if="chips.length" class="flex items-center gap-5">
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
  </span>
</template>
