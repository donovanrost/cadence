<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import { ApCallout, ApEmptyState, ApListRow, ApPanel, ApRemote } from "@/ui";
import type { Alarm } from "@/features/alarms/index.ts";
import { fleetOpState, type FleetSpacecraft } from "@/features/fleet/index.ts";
import { formatValue } from "./format.ts";
import { sisters } from "./model.ts";
import { usePointAlarms } from "./useInvestigate.ts";

/**
 * B4 · Same plane, same point currently in limits. Titled "same point in limits" because the
 * backend doesn't compute signature similarity (ux decision). Hidden content without a plane.
 */
const props = defineProps<{
  sc: FleetSpacecraft;
  fleet: readonly FleetSpacecraft[];
  alarm: Alarm | null;
}>();
const scope = useMissionScope();
const pointAlarms = usePointAlarms(
  computed(() => scope.value.mission.id),
  computed(() => (props.sc.plane === null ? null : (props.alarm?.point.id ?? null))),
);
const planeLabel = computed(() =>
  props.sc.plane === null ? "Plane" : `Plane ${String(props.sc.plane).padStart(2, "0")}`,
);
const planeSize = computed(() => props.fleet.filter((o) => o.plane === props.sc.plane).length - 1);
const rows = computed(() => {
  const s = pointAlarms.state.value;
  return s.status === "ready" && props.alarm
    ? sisters(s.value.alarms, props.fleet, props.sc, props.alarm.point.id)
    : [];
});
</script>

<template>
  <ApPanel
    index="B4"
    :title="`${planeLabel} · same point in limits`"
    v-bind="alarm && sc.plane !== null ? { meta: `${rows.length} of ${planeSize}` } : {}"
    pane
    flush
  >
    <ApEmptyState
      v-if="sc.plane === null"
      state="off"
      headline="No plane on record"
      sentence="This spacecraft has no plane, so there are no plane sisters to compare."
    />
    <ApEmptyState
      v-else-if="!alarm"
      headline="Nothing to compare"
      sentence="Sisters are shown for the point in alarm on this spacecraft."
    />
    <ApRemote
      v-else
      :state="pointAlarms.state.value"
      loading-label="LOADING…"
      @retry="pointAlarms.refetch"
    >
      <ApCallout v-if="rows.length === 0" tone="nominal">
        No other spacecraft in {{ planeLabel.toLowerCase() }} have {{ alarm.point.name }} out of
        limits.
      </ApCallout>
      <ul v-else class="m-0 list-none p-0">
        <ApListRow
          v-for="row in rows"
          :key="row.alarm.id"
          :state="fleetOpState(row.alarm.severity === 'critical' ? 'critical' : 'caution')"
        >
          <template #sentence>
            <span class="font-mono text-text-3 normal-case">{{ alarm.point.id }}</span>
            {{ formatValue(row.alarm.value) ?? "—" }}
          </template>
          <template #title>
            <RouterLink
              :to="{
                name: 'ops.spacecraft',
                params: { scId: String(row.sc.scid), tab: 'investigate' },
                query: { alarm: row.alarm.id },
              }"
              class="text-readout no-underline hover:text-bright hover:underline"
              >{{ row.sc.name }}</RouterLink
            >
          </template>
        </ApListRow>
      </ul>
    </ApRemote>
  </ApPanel>
</template>
