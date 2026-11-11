<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { throttle } from "@/features/fleet/index.ts";
import type { TelemetryPoint } from "@/features/telemetry/index.ts";
import { fetchHistory, fetchLimitIntervals } from "../api.ts";
import { limitSegments, rangeWindow, toSeries, trendSentence, type RangeKey } from "../model.ts";
import { tailPoints, type TailSample } from "../tail.ts";
import TrendBlock from "../TrendBlock.vue";
import type { TimeBand } from "@/ui";

/**
 * One T2 small multiple: a point's history over the range (M10) with its limit bands (M11) and the
 * M8 tail after the last bucket. Stacked plots share the window, so their time axes line up.
 */
const props = defineProps<{
  missionId: string;
  spacecraftId: string;
  point: TelemetryPoint;
  range: RangeKey;
  rangeLabel: string;
  tail: readonly TailSample[];
  height: number;
  bands: readonly TimeBand[];
}>();
const hover = defineModel<number | null>("hover", { default: null });
const key = computed(
  () => `${props.missionId}|${props.spacecraftId}|${props.point.id}|${props.range}`,
);
const win = () => {
  const w = rangeWindow(props.range, new Date());
  return { from: new Date(w.from), to: new Date(w.to) };
};
const history = useRemoteQuery(key, (_k, signal) =>
  fetchHistory(props.missionId, props.point.id, props.spacecraftId, win(), signal),
);
const intervals = useRemoteQuery(key, (_k, signal) =>
  fetchLimitIntervals(props.missionId, props.point.id, props.spacecraftId, win(), signal),
);
const slow = throttle(history.refetch, 10_000);
useMissionInvalidation(
  computed(() => props.missionId),
  ["telemetry"],
  slow.call,
);
useMissionInvalidation(
  computed(() => props.missionId),
  ["limits"],
  intervals.refetch,
);
const view = computed(() => {
  const h = history.state.value;
  if (h.status !== "ready") return null;
  const hist = toSeries(h.value);
  const live = tailPoints(props.tail, hist.at(-1)?.t ?? Date.parse(h.value.from));
  const series = [...hist, ...live];
  const window = {
    from: Date.parse(h.value.from),
    to: Math.max(Date.parse(h.value.to), live.at(-1)?.t ?? 0),
  };
  const i = intervals.state.value;
  const limits = limitSegments(i.status === "ready" ? i.value : null, window, null);
  return {
    window,
    series,
    limits,
    stepMs: h.value.bucket_width_ms,
    sentence: trendSentence(props.point.name, props.rangeLabel, series, limits),
  };
});
</script>

<template>
  <TrendBlock
    :point-name="point.name"
    :unit="point.unit"
    :range-label="rangeLabel"
    :history="history.state.value"
    :view="view"
    :height="height"
    :bands="bands"
    v-model:hover="hover"
    @retry="history.refetch"
  />
</template>
