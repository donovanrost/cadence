<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useMissionScope, useMobileHeader } from "@/shell";
import { ApCallout, ApEmptyState, ApPanel, ApRemote, formatRelative, useNow } from "@/ui";
import { conditionWords, crossedCondition } from "@/features/alarms/index.ts";
import { useFleet } from "@/features/fleet/index.ts";
import {
  DEFAULT_RANGE,
  limitSegments,
  pickAlarm,
  RANGES,
  ratePerHour,
  toSeries,
  trendSentence,
  usePointTrend,
  useSpacecraftAlarms,
} from "@/features/investigate/index.ts";
import MobileAlarmPanel from "./MobileAlarmPanel.vue";

/**
 * J6 paged view (Mobile.md), the ops.spacecraft route under 768px: is this real? Alarm, its trend
 * and timing first. GO polls (M16+) and Ack / Hand off (alarm lifecycle) join when they exist.
 */
const route = useRoute();
const scope = useMissionScope();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const fleet = useFleet(missionId);
const scid = computed(() => Number(route.params.scId));
const sc = computed(() => {
  const f = fleet.state.value;
  return f.status === "ready"
    ? (f.value.spacecraft.find((row) => row.scid === scid.value) ?? null)
    : null;
});
const alarms = useSpacecraftAlarms(
  missionId,
  computed(() => sc.value?.id ?? null),
);
const alarm = computed(() => {
  const a = alarms.state.value;
  const id = typeof route.query.alarm === "string" ? route.query.alarm : null;
  return a.status === "ready" ? pickAlarm(a.value.alarms, id) : null;
});

const range = computed(() => DEFAULT_RANGE);
const rangeLabel = RANGES.find((r) => r.value === DEFAULT_RANGE)?.label ?? DEFAULT_RANGE;
const trend = usePointTrend(
  missionId,
  computed(() => sc.value?.id ?? null),
  computed(() => alarm.value?.point.id ?? null),
  range,
);
const view = computed(() => {
  const h = trend.history.state.value;
  const a = alarm.value;
  if (h.status !== "ready" || !a) return null;
  const window = { from: Date.parse(h.value.from), to: Date.parse(h.value.to) };
  const i = trend.intervals.state.value;
  const series = toSeries(h.value);
  const limits = limitSegments(i.status === "ready" ? i.value : null, window, a.thresholds);
  return {
    window,
    series,
    limits,
    stepMs: h.value.bucket_width_ms,
    rate: ratePerHour(series, h.value.bucket_width_ms),
    sentence: trendSentence(a.point.name, rangeLabel, series, limits),
  };
});

useMobileHeader(() => {
  const a = alarm.value;
  const since = a?.first_crossed_at
    ? ` ${formatRelative(new Date(a.first_crossed_at), now.value)}`
    : "";
  return {
    title: a
      ? `${a.point.subsystem ?? "Point"} ${conditionWords(crossedCondition(a)) ?? "out of limits"}`
      : (sc.value?.name ?? "Spacecraft"),
    context: `${a ? `Alarm${since}` : "Spacecraft"} · ${scope.value.mission.name}`,
    back: { name: "ops.alarms" },
  };
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <ApRemote :state="fleet.state.value" loading-label="LOADING FLEET…" @retry="fleet.refetch">
      <template v-if="sc">
        <ApRemote
          :state="alarms.state.value"
          loading-label="LOADING ALARM…"
          @retry="alarms.refetch"
        >
          <MobileAlarmPanel
            v-if="alarm"
            :sc="sc"
            :alarm="alarm"
            :history="trend.history.state.value"
            :view="view"
            :range-label="rangeLabel"
            @retry="trend.history.refetch"
          />
          <template v-else>
            <h1 class="m-0 font-display text-[22px] font-bold tracking-id uppercase">
              {{ sc.name }}
            </h1>
            <ApCallout tone="nominal"
              >No active alarm on {{ sc.name }}. It may have cleared since you were
              paged.</ApCallout
            >
          </template>
        </ApRemote>
        <ApPanel index="T" title="Timing" flush>
          <ApEmptyState
            state="off"
            headline="Next AOS not available yet"
            sentence="Pass predictions aren't connected to the console. Check Contacts on a desktop."
          />
        </ApPanel>
      </template>
      <template v-else>
        <h1 class="m-0 font-display text-[22px] font-bold tracking-id uppercase">
          Spacecraft not found
        </h1>
        <ApCallout tone="caution"
          >No spacecraft with SCID {{ route.params.scId }} in {{ scope.mission.name }}.</ApCallout
        >
      </template>
    </ApRemote>
    <p class="m-0 pt-2 text-center font-mono text-xs text-text-4 uppercase">
      New uplink sequences are desktop only, by design
    </p>
  </div>
</template>
