<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import { plural, ApButton, ApCallout, ApPageHeader, ApPanel, ApRemote } from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import AlarmTable from "./AlarmTable.vue";
import ByPointPanel from "./ByPointPanel.vue";
import { alarmRows, byPoint } from "./list.ts";
import { useActiveAlarms } from "./useAlarms.ts";

/**
 * Alarms (OpsLists.md §Alarms): what's out of limits now. Lifecycle tabs and the Owner column
 * wait for the alarm lifecycle (DECISIONS #6); grouping is by point in L2.
 */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const missionId = computed(() => scope.value.mission.id);
const alarms = useActiveAlarms(missionId);
const fleet = useFleet(missionId);

const point = computed(() => (typeof route.query.point === "string" ? route.query.point : null));
function selectPoint(pointId: string | null) {
  const { point: _drop, ...rest } = route.query;
  router
    .replace({ query: pointId === null ? rest : { ...rest, point: pointId } })
    .catch((error: unknown) => console.error("Navigation failed", error));
}

const fleetRows = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);
const limitsOff = computed(
  () => fleet.state.value.status === "ready" && !fleet.state.value.value.limits.configured,
);
const active = computed(() =>
  alarms.state.value.status === "ready" ? alarms.state.value.value.summary.active : null,
);
const headline = computed(() => {
  if (active.value === null) return "Alarms";
  if (active.value === 0) return limitsOff.value ? "Ground limits off" : "No active alarms";
  return `${plural(active.value, "alarm")} active`;
});
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader :label="`${scope.mission.name} · alarms`" :title="headline" />
    <ApCallout v-if="limitsOff" tone="off">
      Ground limits aren't configured on this mission, so no point is checked against limits.
      <template #action>
        <ApButton size="compact" :to="{ name: 'setup.apps' }">Set up</ApButton>
      </template>
    </ApCallout>
    <ApRemote :state="alarms.state.value" loading-label="LOADING ALARMS…" @retry="alarms.refetch">
      <template #default="{ value }">
        <ApCallout v-if="value.summary.active === 0 && !limitsOff" tone="nominal">
          No active alarms. Every evaluated point is in limits.
        </ApCallout>
        <div
          v-else-if="value.summary.active > 0"
          class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[minmax(0,1fr)_340px]"
        >
          <ApPanel
            index="L1"
            title="Alarm table"
            :meta="point ? `filtered: ${point}` : 'severity, then oldest'"
            pane
            flush
          >
            <AlarmTable :rows="alarmRows(value.alarms, fleetRows, point)" />
          </ApPanel>
          <ByPointPanel :points="byPoint(value.alarms)" :selected="point" @select="selectPoint" />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
