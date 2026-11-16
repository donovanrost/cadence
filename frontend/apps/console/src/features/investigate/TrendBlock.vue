<script setup lang="ts">
import { formatValue } from "@/features/alarms/index.ts";
import { computed } from "vue";
import type { RemoteState } from "@/api/index.ts";
import { formatClock, ApEmptyState, ApRemote } from "@/ui";
import type { History } from "./api.ts";
import {
  ApTimeSeries as TrendChart,
  type LimitSegment,
  type SeriesPoint,
  type TimeBand,
  type TimeMark,
  type TimeWindow,
} from "@/ui";

/** The chart area of B1: history unavailable (503), loading/failed, or the chart + legend. */
const props = withDefaults(
  defineProps<{
    pointName: string;
    unit: string | null;
    rangeLabel: string;
    history: RemoteState<History>;
    view: {
      window: TimeWindow;
      series: readonly SeriesPoint[];
      limits: readonly LimitSegment[];
      sentence: string;
      stepMs: number;
    } | null;
    /** Plot height in px (B1: 220; Mobile sparkline: 80). */
    height?: number;
    /** Sparkline: no legend line and no "no samples" sentence. */
    compact?: boolean;
    /** Pass / outage spans behind the series (kit e80c3fc8). */
    bands?: readonly TimeBand[];
    /** ux U71 A7: a sample to ring (kit b7d6be8ec). */
    marks?: readonly TimeMark[];
  }>(),
  { height: 220, compact: false, bands: () => [], marks: () => [] },
);
/** Shared crosshair time: stacked plots bind one ref so their readouts move together. */
const hover = defineModel<number | null>("hover", { default: null });
defineEmits<{ retry: [] }>();

const unavailable = computed(() =>
  props.history.status === "failed" && props.history.error.kind === "unavailable"
    ? props.history.error.message
    : null,
);
/** §11c(D) D11 (ux): the read hit its cap, so the plot is missing samples; never cut silently. */
const incomplete = computed(
  () => props.history.status === "ready" && props.history.value.truncated,
);
const tick = (t: number) => formatClock(new Date(t)).slice(0, 5);
const value = (v: number) => formatValue(v) ?? "";
</script>

<template>
  <ApEmptyState
    v-if="unavailable"
    state="off"
    headline="History not available"
    :sentence="`The telemetry history store can't be reached (${unavailable}).`"
  />
  <ApRemote v-else :state="history" loading-label="LOADING HISTORY…" @retry="$emit('retry')">
    <template v-if="view">
      <TrendChart
        :series="view.series"
        :limits="view.limits"
        :window="view.window"
        :now="Date.now()"
        :label="view.sentence"
        :format-tick="tick"
        :format-value="value"
        :height="height"
        :step-ms="view.stepMs"
        :bands="bands"
        :marks="marks"
        :series-name="unit ? `${pointName} (${unit})` : pointName"
        v-model:hover="hover"
      >
        <template v-if="!compact" #default>
          {{ pointName }}{{ unit ? ` (${unit})` : "" }} mean with min–max band · dashed: limits
        </template>
      </TrendChart>
      <p v-if="!compact && view.series.length === 0" class="m-0 pt-2 text-md text-text-3">
        No samples for this point in the last {{ rangeLabel }}.
      </p>
      <p v-if="incomplete" class="m-0 pt-2 text-sm text-caution-text">
        This range has more samples than one read returns (20,000), so the plot is incomplete. Pick
        a shorter range to see all of it.
      </p>
    </template>
  </ApRemote>
</template>
