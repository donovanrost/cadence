<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import { ApKeyValue } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import AlarmTrendPanel from "./AlarmTrendPanel.vue";
import EventLogPanel from "./EventLogPanel.vue";
import SistersPanel from "./SistersPanel.vue";
import { DEFAULT_RANGE, pickAlarm, type RangeKey } from "./model.ts";
import { useSpacecraftAlarms } from "./useInvestigate.ts";

/** J2 · Investigate tab: B1 trend, B2 events, B4 same point in limits, technical details. */
const props = defineProps<{ sc: FleetSpacecraft; fleet: readonly FleetSpacecraft[] }>();
const scope = useMissionScope();
const route = useRoute();
const missionId = computed(() => scope.value.mission.id);
const alarms = useSpacecraftAlarms(
  missionId,
  computed(() => props.sc.id),
);
const range = ref<RangeKey>(DEFAULT_RANGE);

const alarm = computed(() => {
  const state = alarms.state.value;
  const id = typeof route.query.alarm === "string" ? route.query.alarm : null;
  return state.status === "ready" ? pickAlarm(state.value.alarms, id) : null;
});

const details = computed(() => [
  { key: "sc", label: "Spacecraft id", value: props.sc.id, mono: true },
  ...(props.sc.profile
    ? [{ key: "profile", label: "Profile id", value: props.sc.profile.id, mono: true }]
    : []),
  ...(alarm.value
    ? [
        { key: "point", label: "Point id", value: alarm.value.point.id, mono: true },
        { key: "alarm", label: "Alarm id", value: alarm.value.id, mono: true },
      ]
    : []),
]);
</script>

<template>
  <div
    class="grid grid-cols-1 gap-2.5 console:min-h-0 console:flex-1 console:grid-cols-[minmax(0,1fr)_380px]"
  >
    <div class="flex flex-col gap-2.5 console:min-h-0">
      <AlarmTrendPanel
        v-model:range="range"
        :sc="sc"
        :alarms="alarms.state.value"
        :alarm="alarm"
        @retry="alarms.refetch"
      />
      <EventLogPanel class="min-h-[160px] flex-1" />
    </div>
    <aside class="flex flex-col gap-2.5 console:min-h-0" aria-label="Context">
      <SistersPanel class="min-h-[160px] flex-1" :sc="sc" :fleet="fleet" :alarm="alarm" />
      <details class="flex-none border border-hairline bg-panel px-4 py-2.5">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <div class="pt-2.5"><ApKeyValue :items="details" /></div>
      </details>
    </aside>
  </div>
</template>
