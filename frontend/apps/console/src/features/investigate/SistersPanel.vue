<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import { useNow, ApCallout, ApEmptyState, ApListRow, ApPanel, ApRemote } from "@/ui";
import { AlarmsMore, formatValue, withUnit, type Alarm } from "@/features/alarms/index.ts";
import { fleetOpState, type FleetSpacecraft } from "@/features/fleet/index.ts";
import { sisters } from "./model.ts";
import PlaneRing from "./PlaneRing.vue";
import SisterSpark from "./SisterSpark.vue";
import { aosShort } from "./sisters.ts";
import { useSisterAlarms } from "./useInvestigate.ts";

/**
 * B4 · Same plane, same point currently in limits: the plane ring, then each sister with its value,
 * next AOS and a 6 h sparkline (the first 12; each is one M10 read). Titled "same point in limits" because the
 * backend doesn't compute signature similarity (ux decision). Hidden content without a plane.
 */
const props = defineProps<{
  sc: FleetSpacecraft;
  fleet: readonly FleetSpacecraft[];
  alarm: Alarm | null;
}>();
const scope = useMissionScope();
const now = useNow();
const SPARKS = 12;
const pointAlarms = useSisterAlarms(
  computed(() => scope.value.mission.id),
  computed(() =>
    props.sc.plane === null || !props.alarm
      ? null
      : { pointId: props.alarm.point.id, plane: props.sc.plane, spacecraftId: props.sc.id },
  ),
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
/** How many sisters are in alarm on this point, from the server (all pages, not those loaded). */
const inAlarm = computed(() => {
  const s = pointAlarms.state.value;
  return s.status === "ready" ? s.value.total : rows.value.length;
});
/** Set while only part of them is loaded (#827). */
const partial = computed(() => {
  const s = pointAlarms.state.value;
  return s.status === "ready" && s.value.next !== null
    ? { shown: s.value.alarms.length, total: s.value.total }
    : null;
});
const tones = computed(
  () =>
    new Map(
      rows.value.map(
        (r) => [r.sc.id, r.alarm.severity === "critical" ? "crit" : "caution"] as const,
      ),
    ),
);
</script>

<template>
  <ApPanel
    index="B4"
    :title="`${planeLabel} · same point in limits`"
    v-bind="alarm && sc.plane !== null ? { meta: `${inAlarm} of ${planeSize}` } : {}"
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
      <AlarmsMore
        v-if="partial"
        class="border-b border-hairline-faint px-4 py-2"
        :shown="partial.shown"
        :total="partial.total"
        :what="`${planeLabel.toLowerCase()} sisters in alarm`"
        :busy="pointAlarms.moreBusy.value"
        :failed="pointAlarms.moreError.value !== null"
        @more="pointAlarms.more()"
      />
      <div class="flex justify-center border-b border-hairline-faint py-2">
        <PlaneRing :fleet="fleet" :sc="sc" :sisters="tones" />
      </div>
      <ApCallout v-if="rows.length === 0" tone="nominal">
        No other spacecraft in {{ planeLabel.toLowerCase() }} have {{ alarm.point.name }} out of
        limits.
      </ApCallout>
      <ul v-else class="m-0 list-none p-0">
        <ApListRow
          v-for="(row, i) in rows"
          :key="row.alarm.id"
          :state="fleetOpState(row.alarm.severity === 'critical' ? 'critical' : 'caution')"
        >
          <template #sentence>
            <span class="font-mono text-text-3 normal-case">{{ alarm.point.name }}</span>
            {{ withUnit(formatValue(row.alarm.value), row.alarm.point.unit) ?? "—"
            }}<template v-if="aosShort(row.sc, now)"> · {{ aosShort(row.sc, now) }}</template>
          </template>
          <template v-if="i < SPARKS" #action>
            <SisterSpark
              :mission-id="scope.mission.id"
              :spacecraft-id="row.sc.id"
              :point-id="alarm.point.id"
              :tone="tones.get(row.sc.id) ?? 'caution'"
            />
          </template>
          <template #title>
            <RouterLink
              :to="{
                name: 'ops.spacecraft',
                params: { scId: row.sc.scid, tab: 'investigate' },
                query: { alarm: row.alarm.id },
              }"
              class="max-md:hit-44 text-readout no-underline hover:text-bright hover:underline"
              >{{ row.sc.name }}</RouterLink
            >
          </template>
        </ApListRow>
      </ul>
    </ApRemote>
  </ApPanel>
</template>
