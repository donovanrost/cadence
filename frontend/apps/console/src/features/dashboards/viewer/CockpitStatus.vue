<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { ClockCluster, useMissionScope, useOpsCounts } from "@/shell";
import { ApStatusMark, stateTextClass } from "@/ui";

/**
 * The cockpit cluster (ux): mission alarm counts linking to Alarms, then UTC. A count the server
 * can't compute is left out rather than shown as zero.
 */
const scope = useMissionScope();
const { counts } = useOpsCounts(computed(() => scope.value.mission.id));
const chips = computed(() => {
  const a = counts.value?.alarms;
  if (!a) return [];
  return [
    { state: "crit" as const, count: a.critical, label: "critical" },
    { state: "caution" as const, count: a.caution, label: "caution" },
  ].filter((c) => c.count > 0);
});
</script>

<template>
  <ClockCluster>
    <RouterLink
      v-for="chip in chips"
      :key="chip.state"
      :to="{ name: 'ops.alarms' }"
      class="flex items-center gap-1.5 tabular-nums no-underline hover:underline"
      :class="stateTextClass(chip.state)"
      :aria-label="`${chip.count} ${chip.label} alarms`"
    >
      <ApStatusMark :state="chip.state" />{{ chip.count }}
    </RouterLink>
  </ClockCluster>
</template>
