<script setup lang="ts">
import { tailPoints, useSpacecraftTail } from "./tail.ts";
import { computed, ref, watch } from "vue";
import type { RemoteState } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  formatAbsolute,
  formatClock,
  ApCallout,
  ApChip,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApStatStrip,
  ApStatTile,
} from "@/ui";
import {
  formatLimitLike,
  formatValue,
  conditionWords,
  crossedCondition,
  crossedLimit,
  AlarmsMore,
  type Alarm,
  type AlarmsPage,
  valueLabel,
  type Episode,
  type EpisodeDetail,
} from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import type { TelemetryPoint } from "@/features/telemetry/index.ts";
import AddPointSearch from "./AddPointSearch.vue";
import AlarmProvenance from "./AlarmProvenance.vue";
import PointPlot from "./telemetry/PointPlot.vue";
import TrendBlock from "./TrendBlock.vue";
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
  alarms: RemoteState<AlarmsPage>;
  /** Load more of this spacecraft's alarms (#827): the list holds a page at a time. */
  more: { load: () => void; busy: boolean; failed: boolean };
  alarm: Alarm | null;
  /** U13: without ground limits, "no active alarm" is unknown, not nominal (qa #9). */
  limitsConfigured: boolean;
  /** Lifecycle episode for the shown alarm, when one exists (label: Now vs At evaluation). */
  episode?: EpisodeDetail | null;
  /** No active alarm: the latest cleared episode, shown back in limits (§B1). */
  resolved?: Episode | null;
}>();
defineEmits<{ retry: [] }>();
const range = defineModel<RangeKey>("range", { required: true });
const scope = useMissionScope();
/** What B1 plots: the alarm's point, else the last resolved alarm's. */
/** Set while the list holds only part of this spacecraft's active alarms (#827). */
const partial = computed(() => {
  const s = props.alarms;
  return s.status === "ready" && s.value.next !== null
    ? { shown: s.value.alarms.length, total: s.value.total }
    : null;
});

const subject = computed(() => {
  const a = props.alarm;
  if (a)
    return { id: a.point.id, name: a.point.name, unit: a.point.unit, thresholds: a.thresholds };
  const r = props.resolved;
  return r
    ? { id: r.point.id, name: r.point.name, unit: r.point.unit, thresholds: r.thresholds }
    : null;
});
/** "Resolved at 02:31:07Z" today, else with the date (§4). */
const resolvedAt = computed(() => {
  const at = props.resolved?.cleared_at;
  if (!at) return null;
  const d = new Date(at);
  return at.slice(0, 10) === new Date().toISOString().slice(0, 10)
    ? `${formatClock(d)}Z`
    : formatAbsolute(d);
});

const trend = usePointTrend(
  computed(() => scope.value.mission.id),
  computed(() => props.sc.id),
  computed(() => subject.value?.id ?? null),
  range,
);
const rangeLabel = computed(
  () => RANGES.find((r) => r.value === range.value)?.label ?? range.value,
);
/**
 * Added points (§B1: max 3, chips with remove): stacked under the alarm's plot on the same time
 * axis and crosshair, each with its own unit and limits (never two y-axes on one plot).
 */
const MAX_ADDED = 3;
const added = ref<TelemetryPoint[]>([]);
watch(
  () => props.sc.id,
  () => (added.value = []),
);
const plotted = computed(() => [
  ...(subject.value ? [subject.value.id] : []),
  ...added.value.map((p) => p.id),
]);
const addPoint = (p: TelemetryPoint) => {
  if (added.value.length < MAX_ADDED) added.value = [...added.value, p];
};
const removePoint = (id: string) => (added.value = added.value.filter((p) => p.id !== id));
const hover = ref<number | null>(null);
/** M8 live tail for the shown points; history stays authoritative and refetches as before. */
const tail = useSpacecraftTail(
  computed(() => scope.value.mission.id),
  computed(() => props.sc.id),
  plotted,
  () => trend.history.refetch(),
);
const view = computed(() => {
  const h = trend.history.state.value;
  const a = subject.value;
  if (h.status !== "ready" || !a) return null;
  const historySeries = toSeries(h.value);
  const lastBucket = historySeries.at(-1)?.t ?? Date.parse(h.value.from);
  const live = tailPoints(tail.tails.value.get(a.id) ?? [], lastBucket);
  const series = [...historySeries, ...live];
  const window = {
    from: Date.parse(h.value.from),
    to: Math.max(Date.parse(h.value.to), live.at(-1)?.t ?? 0),
  };
  const i = trend.intervals.state.value;
  const limits = limitSegments(i.status === "ready" ? i.value : null, window, a.thresholds);
  return {
    window,
    series,
    limits,
    rate: ratePerHour(series, h.value.bucket_width_ms),
    stepMs: h.value.bucket_width_ms,
    sentence: trendSentence(a.name, rangeLabel.value, series, limits),
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
    : props.resolved
      ? "Last alarm · back in limits"
      : "Alarm trend",
);
const limit = computed(() => (props.alarm ? crossedLimit(props.alarm) : null));
const ranges = RANGES.map((r) => ({ value: r.value, label: r.label }));
</script>

<template>
  <ApPanel index="B1" :title="title" v-bind="tone ? { alert: tone } : {}" class="flex-none">
    <template v-if="!alarm && resolved" #meta>
      <span class="font-mono normal-case">{{ resolved.point.name }}</span>
    </template>
    <template v-else-if="alarm" #meta>
      <span class="font-mono normal-case">{{ alarm.point.name }}</span
      ><template v-if="alarm.first_crossed_at">
        · first crossed {{ formatAbsolute(new Date(alarm.first_crossed_at)) }}</template
      >
    </template>
    <ApRemote :state="alarms" loading-label="LOADING ALARMS…" @retry="$emit('retry')">
      <AlarmsMore
        v-if="partial"
        class="mb-3"
        :shown="partial.shown"
        :total="partial.total"
        :what="`active alarms on ${sc.name}`"
        :busy="more.busy"
        :failed="more.failed"
        @more="more.load"
      />
      <ApCallout v-if="!alarm && !limitsConfigured" tone="off">
        Ground limits aren't configured, so no point on {{ sc.name }} is checked against limits.
      </ApCallout>
      <ApCallout v-else-if="!subject" tone="nominal">No active alarm on {{ sc.name }}.</ApCallout>
      <div v-else class="flex flex-col gap-3">
        <slot name="lifecycle" />
        <AlarmProvenance v-if="episode" :episode="episode" :sc="sc" />
        <div class="flex flex-wrap items-end justify-between gap-3">
          <ApCallout v-if="!alarm" tone="nominal" class="flex-1">
            Resolved at {{ resolvedAt ?? "an unknown time" }} · back in limits.
          </ApCallout>
          <ApStatStrip v-else :columns="3" label="Readouts" class="min-w-[360px] flex-1">
            <ApStatTile
              :label="valueLabel(episode ?? null)"
              :value="formatValue(alarm.value)"
              :unit="alarm.point.unit ?? undefined"
              :state="tone ?? 'neutral'"
            />
            <ApStatTile
              :label="condition?.startsWith('red') ? 'Red limit' : 'Limit'"
              :value="formatLimitLike(limit, alarm.value)"
              :unit="alarm.point.unit ?? undefined"
            />
            <ApStatTile
              class="max-md:col-span-2"
              label="Rate"
              :value="view?.rate == null ? null : formatRate(view.rate)"
              :caption="
                view?.rate == null
                  ? 'needs 15 min of data'
                  : alarm.point.unit
                    ? `${alarm.point.unit}/h`
                    : 'per hour'
              "
            />
          </ApStatStrip>
          <ApSegmented v-model="range" :options="ranges" label="Chart window" variant="micro" />
        </div>
        <TrendBlock
          :point-name="subject.name"
          :unit="subject.unit"
          :range-label="rangeLabel"
          :history="trend.history.state.value"
          :view="view"
          :height="episode ? 170 : 220"
          v-model:hover="hover"
          @retry="trend.history.refetch"
        />
        <div class="flex flex-wrap items-center gap-2">
          <ApChip
            v-for="p in added"
            :key="p.id"
            removable
            :remove-label="`Remove ${p.name}`"
            @remove="removePoint(p.id)"
            >{{ p.name }}</ApChip
          >
          <AddPointSearch
            :mission-id="scope.mission.id"
            :spacecraft-id="sc.id"
            :exclude="plotted"
            :full="added.length >= MAX_ADDED"
            @add="addPoint"
          />
        </div>
        <PointPlot
          v-for="p in added"
          :key="p.id"
          v-model:hover="hover"
          :mission-id="scope.mission.id"
          :spacecraft-id="sc.id"
          :point="p"
          :range="range"
          :range-label="rangeLabel"
          :tail="tail.tails.value.get(p.id) ?? []"
          :height="110"
          :bands="[]"
        />
      </div>
    </ApRemote>
  </ApPanel>
</template>
