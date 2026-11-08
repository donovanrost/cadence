<script setup lang="ts">
import { computed } from "vue";
import type { RemoteState } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  formatAbsolute,
  ApCallout,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApStatStrip,
  ApStatTile,
} from "@/ui";
import {
  conditionWords,
  crossedCondition,
  crossedLimit,
  type Alarm,
  type Alarms,
} from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import TrendBlock from "./TrendBlock.vue";
import { formatValue } from "./format.ts";
import {
  formatRate,
  limitSegments,
  RANGES,
  ratePerHour,
  toSeries,
  trendSentence,
  type RangeKey,
} from "./model.ts";
import { usePointTrend } from "./useInvestigate.ts";

/** B1 · Alarm trend: readouts (Now, Limit, Rate), range, chart. Spec: Investigate.md §B1. */
const props = defineProps<{
  sc: FleetSpacecraft;
  alarms: RemoteState<Alarms>;
  alarm: Alarm | null;
}>();
defineEmits<{ retry: [] }>();
const range = defineModel<RangeKey>("range", { required: true });
const scope = useMissionScope();

const trend = usePointTrend(
  computed(() => scope.value.mission.id),
  computed(() => props.sc.id),
  computed(() => props.alarm?.point.id ?? null),
  range,
);
const rangeLabel = computed(
  () => RANGES.find((r) => r.value === range.value)?.label ?? range.value,
);
const view = computed(() => {
  const h = trend.history.state.value;
  const a = props.alarm;
  if (h.status !== "ready" || !a) return null;
  const window = { from: Date.parse(h.value.from), to: Date.parse(h.value.to) };
  const i = trend.intervals.state.value;
  const series = toSeries(h.value);
  const limits = limitSegments(i.status === "ready" ? i.value : null, window, a.thresholds);
  return {
    window,
    series,
    limits,
    rate: ratePerHour(series, h.value.bucket_width_ms),
    stepMs: h.value.bucket_width_ms,
    sentence: trendSentence(a.point.name, rangeLabel.value, series, limits),
  };
});

const tone = computed(() =>
  props.alarm?.severity === "critical"
    ? "crit"
    : props.alarm?.severity === "caution"
      ? "caution"
      : undefined,
);
const condition = computed(() => (props.alarm ? crossedCondition(props.alarm) : null));
/** Words only (ids are never case-transformed; the literal id goes in the meta, untransformed). */
const title = computed(() =>
  props.alarm
    ? `${props.alarm.point.subsystem ?? "Point"} · ${conditionWords(condition.value) ?? "out of limits"}`
    : "Alarm trend",
);
const limit = computed(() => (props.alarm ? crossedLimit(props.alarm) : null));
const ranges = RANGES.map((r) => ({ value: r.value, label: r.label }));
</script>

<template>
  <ApPanel index="B1" :title="title" v-bind="tone ? { alert: tone } : {}" class="flex-none">
    <template v-if="alarm" #meta>
      <span class="font-mono normal-case">{{ alarm.point.name }}</span
      ><template v-if="alarm.first_crossed_at">
        · first crossed {{ formatAbsolute(new Date(alarm.first_crossed_at)) }}</template
      >
    </template>
    <ApRemote :state="alarms" loading-label="LOADING ALARMS…" @retry="$emit('retry')">
      <ApCallout v-if="!alarm" tone="nominal">No active alarm on {{ sc.name }}.</ApCallout>
      <div v-else class="flex flex-col gap-3">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <ApStatStrip :columns="3" label="Readouts" class="min-w-[360px] flex-1">
            <ApStatTile label="Now" :value="formatValue(alarm.value)" :state="tone ?? 'neutral'" />
            <ApStatTile
              :label="condition?.startsWith('red') ? 'Red limit' : 'Limit'"
              :value="limit === null ? null : formatValue(limit)"
            />
            <ApStatTile
              label="Rate"
              :value="view?.rate == null ? null : formatRate(view.rate)"
              :caption="view?.rate == null ? 'needs 15 min of data' : 'per hour'"
            />
          </ApStatStrip>
          <ApSegmented v-model="range" :options="ranges" label="Chart window" variant="micro" />
        </div>
        <TrendBlock
          :point-name="alarm.point.name"
          :range-label="rangeLabel"
          :history="trend.history.state.value"
          :view="view"
          @retry="trend.history.refetch"
        />
      </div>
    </ApRemote>
  </ApPanel>
</template>
