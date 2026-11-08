<script setup lang="ts">
import { computed } from "vue";
import type { RemoteState } from "@/api/index.ts";
import {
  formatAbsolute,
  ApCallout,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApStatStrip,
  ApStatTile,
} from "@/ui";
import { conditionWords, crossedLimit, type Alarm, type Alarms } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import TrendBlock from "./TrendBlock.vue";
import { formatValue } from "./format.ts";
import { RANGES, type RangeKey } from "./model.ts";

/** B1 · Alarm trend: readouts, range, chart. Spec: Investigate.md §B1. */
const props = defineProps<{
  sc: FleetSpacecraft;
  alarms: RemoteState<Alarms>;
  alarm: Alarm | null;
}>();
defineEmits<{ retry: [] }>();
const range = defineModel<RangeKey>("range", { required: true });

const tone = computed(() =>
  props.alarm?.severity === "critical"
    ? "crit"
    : props.alarm?.severity === "caution"
      ? "caution"
      : undefined,
);
const title = computed(() => {
  const a = props.alarm;
  if (!a) return "Alarm trend";
  const words = conditionWords(a.condition);
  return words ? `${a.point.name} · ${words}` : a.point.name;
});
const meta = computed(() =>
  props.alarm?.first_crossed_at
    ? `First crossed ${formatAbsolute(new Date(props.alarm.first_crossed_at))}`
    : undefined,
);
const limit = computed(() => (props.alarm ? crossedLimit(props.alarm) : null));
const ranges = RANGES.map((r) => ({ value: r.value, label: r.label }));
</script>

<template>
  <ApPanel
    index="B1"
    :title="title"
    v-bind="{ ...(tone ? { alert: tone } : {}), ...(meta ? { meta } : {}) }"
    class="flex-none"
  >
    <ApRemote :state="alarms" loading-label="LOADING ALARMS…" @retry="$emit('retry')">
      <ApCallout v-if="!alarm" tone="nominal">No active alarm on {{ sc.name }}.</ApCallout>
      <div v-else class="flex flex-col gap-3">
        <div class="flex flex-wrap items-end justify-between gap-3">
          <ApStatStrip :columns="2" label="Readouts" class="min-w-[280px] flex-1">
            <ApStatTile label="Now" :value="formatValue(alarm.value)" :state="tone ?? 'neutral'" />
            <ApStatTile
              :label="alarm.condition?.startsWith('red') ? 'Red limit' : 'Limit'"
              :value="limit === null ? null : formatValue(limit)"
            />
          </ApStatStrip>
          <ApSegmented v-model="range" :options="ranges" label="Chart window" variant="micro" />
        </div>
        <TrendBlock :sc="sc" :alarm="alarm" :range="range" />
      </div>
    </ApRemote>
  </ApPanel>
</template>
