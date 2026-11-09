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
  }>(),
  { height: 220, compact: false },
);
defineEmits<{ retry: [] }>();

const unavailable = computed(() =>
  props.history.status === "failed" && props.history.error.kind === "unavailable"
    ? props.history.error.message
    : null,
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
      >
        <template v-if="!compact" #default>
          {{ pointName }}{{ unit ? ` (${unit})` : "" }} mean with min–max band · dashed: limits
        </template>
      </TrendChart>
      <p v-if="!compact && view.series.length === 0" class="m-0 pt-2 text-md text-text-3">
        No samples for this point in the last {{ rangeLabel }}.
      </p>
    </template>
  </ApRemote>
</template>
