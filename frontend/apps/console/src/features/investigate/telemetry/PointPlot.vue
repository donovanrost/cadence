<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { SpacecraftId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { throttle } from "@/features/fleet/index.ts";
import type { TelemetryPoint } from "@/features/telemetry/index.ts";
import { fetchHistory, fetchLimitIntervals } from "../api.ts";
import {
  centredWindow,
  limitSegments,
  rangeWindow,
  toSeries,
  trendSentence,
  type RangeKey,
} from "../model.ts";
import { tailPoints, type TailSample } from "../tail.ts";
import TrendBlock from "../TrendBlock.vue";
import { formatClock, type TimeBand } from "@/ui";

/**
 * One T2 small multiple: a point's history over the range (M10) with its limit bands (M11) and the
 * M8 tail after the last bucket. Stacked plots share the window, so their time axes line up.
 */
const props = defineProps<{
  missionId: MissionId;
  spacecraftId: SpacecraftId;
  point: TelemetryPoint;
  range: RangeKey;
  rangeLabel: string;
  tail: readonly TailSample[];
  height: number;
  bands: readonly TimeBand[];
  /** ux U71 A7 (?at=): centre the window on this sample and ring it. */
  at?: number | null | undefined;
}>();
const hover = defineModel<number | null>("hover", { default: null });
const key = computed(
  () =>
    `${props.missionId}|${props.spacecraftId}|${props.point.id}|${props.range}|${props.at ?? ""}`,
);
const win = () => {
  const w = props.at
    ? centredWindow(props.range, props.at, new Date())
    : rangeWindow(props.range, new Date());
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
const marks = computed(() =>
  props.at ? [{ t: props.at, label: `the sample at ${formatClock(new Date(props.at))}Z` }] : [],
);
/** §4 short (ux #11): `15:31Z` today, `11-10 15:31Z` otherwise. */
const edge = (t: number) => {
  const iso = new Date(t).toISOString();
  const today = iso.slice(0, 10) === new Date().toISOString().slice(0, 10);
  return `${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}Z`;
};
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
  <!-- ux review 5: no empty 0–1 axis; say which window had no samples. -->
  <p v-if="view && view.series.length === 0" class="m-0 px-1 py-6 text-center text-sm text-text-3">
    No samples between {{ edge(view.window.from) }} and {{ edge(view.window.to) }}.
  </p>
  <TrendBlock
    v-else
    :point-name="point.name"
    :unit="point.unit"
    :range-label="rangeLabel"
    :history="history.state.value"
    :view="view"
    :height="height"
    :bands="bands"
    :marks="marks"
    v-model:hover="hover"
    @retry="history.refetch"
  />
</template>
