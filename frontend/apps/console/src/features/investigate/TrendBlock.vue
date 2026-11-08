<script setup lang="ts">
import { computed } from "vue";
import { useMissionScope } from "@/shell/index.ts";
import { formatClock, ApEmptyState, ApRemote } from "@/ui";
import type { Alarm } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import TrendChart from "./chart/TrendChart.vue";
import { formatValue } from "./format.ts";
import {
  limitSegments,
  RANGES,
  ratePerHour,
  toSeries,
  trendSentence,
  type RangeKey,
} from "./model.ts";
import { usePointTrend } from "./useInvestigate.ts";

/** The chart for one alarm's point: history (M10) + limit bands (M11), or an honest state. */
const props = defineProps<{ sc: FleetSpacecraft; alarm: Alarm; range: RangeKey }>();
const scope = useMissionScope();
const { history, intervals } = usePointTrend(
  computed(() => scope.value.mission.id),
  computed(() => props.sc.id),
  computed(() => props.alarm.point.id),
  computed(() => props.range),
);

const historyUnavailable = computed(() => {
  const s = history.state.value;
  return s.status === "failed" && s.error.kind === "unavailable" ? s.error.message : null;
});
const rangeLabel = computed(
  () => RANGES.find((r) => r.value === props.range)?.label ?? props.range,
);

const view = computed(() => {
  const h = history.state.value;
  if (h.status !== "ready") return null;
  const window = { from: Date.parse(h.value.from), to: Date.parse(h.value.to) };
  const i = intervals.state.value;
  const series = toSeries(h.value);
  const limits = limitSegments(
    i.status === "ready" ? i.value : null,
    window,
    props.alarm.thresholds,
  );
  const rate = ratePerHour(series);
  return {
    window,
    series,
    limits,
    rate: rate === null ? null : `${formatValue(rate)} per hour`,
    sentence: trendSentence(props.alarm.point.name, rangeLabel.value, series, limits),
  };
});
const tick = (t: number) => formatClock(new Date(t)).slice(0, 5);
const value = (v: number) => formatValue(v) ?? "";
</script>

<template>
  <ApEmptyState
    v-if="historyUnavailable"
    state="off"
    headline="History not available"
    :sentence="`The telemetry history store can't be reached (${historyUnavailable}).`"
  />
  <ApRemote
    v-else
    :state="history.state.value"
    loading-label="LOADING HISTORY…"
    @retry="history.refetch"
  >
    <template v-if="view">
      <TrendChart
        :series="view.series"
        :limits="view.limits"
        :window="view.window"
        :now="Date.now()"
        :label="view.sentence"
        :format-tick="tick"
        :format-value="value"
      >
        {{ alarm.point.name }} mean with min–max band · dashed: limits{{
          view.rate ? ` · rate ${view.rate}` : ""
        }}
      </TrendChart>
      <p v-if="view.series.length === 0" class="m-0 pt-2 text-md text-text-3">
        No samples for this point in the last {{ rangeLabel }}.
      </p>
    </template>
  </ApRemote>
</template>
