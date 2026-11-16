<script setup lang="ts">
import { computed } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";
import { useMissionScope } from "@/shell";
import { useFleet } from "@/features/fleet/index.ts";
import { ApStatusMark, stateTextClass } from "@/ui";

/**
 * The cockpit cluster (ux): fleet health counts (critical and caution link to Alarms, stale to
 * Fleet). The takeover header draws UTC itself (qa: it showed twice inside ClockCluster). One
 * fleet read per open dashboard, refreshed by invalidations (lead). `words` is the phone status
 * bar's form (ux Dashboards.md §Phone): mark, count and word per chip (`◆ 2 crit`), each a 48px
 * link, and `■ Fleet nominal` when there's nothing to report.
 */
const props = defineProps<{ words?: boolean | undefined }>();
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
    { state: "crit" as const, count: c.critical, label: "critical", word: "crit", to: alarms },
    { state: "caution" as const, count: c.caution, label: "caution", word: "caution", to: alarms },
    { state: "stale" as const, count: c.stale, label: "stale", word: "stale", to: fleetTo },
  ].filter((chip) => chip.count > 0);
});
const nominal = computed(
  () => props.words && fleet.state.value.status === "ready" && !chips.value.length,
);
</script>

<template>
  <span v-if="chips.length" class="flex items-center" :class="words ? 'gap-2' : 'gap-5'">
    <template v-for="(chip, i) in chips" :key="chip.state">
      <span v-if="words && i > 0" aria-hidden="true" class="text-text-4">·</span>
      <RouterLink
        :to="chip.to"
        class="flex items-center gap-1.5 tabular-nums no-underline hover:underline"
        :class="[stateTextClass(chip.state), words ? 'h-12' : '']"
        :aria-label="`${chip.count} spacecraft ${chip.label}`"
      >
        <ApStatusMark :state="chip.state" />{{ chip.count
        }}<template v-if="words"> {{ chip.word }}</template>
      </RouterLink>
    </template>
  </span>
  <span v-else-if="nominal" class="flex items-center gap-1.5" :class="stateTextClass('nominal')">
    <ApStatusMark state="nominal" />Fleet nominal
  </span>
</template>
