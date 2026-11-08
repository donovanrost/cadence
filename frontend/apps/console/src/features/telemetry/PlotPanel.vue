<script setup lang="ts">
import { formatClock, ApEmptyState, ApPanel, ApRemote, ApSegmented } from "@/ui";
import type { RemoteState } from "@/api/index.ts";
import { formatValue } from "@/features/alarms/index.ts";
import { RANGES, TrendChart, type RangeKey } from "@/features/investigate/index.ts";
import type { PlotView } from "./plot.ts";
import type { SeriesData } from "./useSeries.ts";

/** T2 · Plot: one series per spacecraft × point (max 6), grays and dashes, never status hues. */
defineProps<{
  state: RemoteState<SeriesData[]>;
  view: PlotView | null;
  empty: boolean;
  dropped: number;
}>();
defineEmits<{ retry: [] }>();
const range = defineModel<RangeKey>("range", { required: true });
const ranges = RANGES.map((r) => ({ value: r.value, label: r.label }));
const tick = (t: number) => formatClock(new Date(t)).slice(0, 5);
const value = (v: number) => formatValue(v) ?? "";
const dashClass = {
  solid: "border-solid",
  dashed: "border-dashed",
  dotted: "border-dotted",
} as const;
const toneClass = {
  readout: "border-readout",
  "text-2": "border-text-2",
  "text-3": "border-text-3",
  "text-4": "border-text-4",
} as const;
</script>

<template>
  <ApPanel
    index="T2"
    title="Plot"
    :meta="dropped ? `${dropped} more series not shown (max 6)` : undefined"
    pane
    flush
  >
    <div class="flex flex-col gap-3 p-4">
      <div class="flex justify-end">
        <ApSegmented v-model="range" :options="ranges" label="Window" variant="micro" />
      </div>
      <ApEmptyState
        v-if="empty"
        headline="Pick a point to plot"
        sentence="Add a spacecraft and a point id in Points. Each spacecraft × point is one series."
      />
      <ApRemote v-else :state="state" loading-label="LOADING HISTORY…" @retry="$emit('retry')">
        <TrendChart
          v-if="view"
          :series="view.primary"
          :comparison="view.comparison"
          :limits="view.limits"
          :window="view.window"
          :now="Date.now()"
          :step-ms="view.stepMs"
          :label="`${view.legend.length} series over ${range}: ${view.legend.map((l) => l.label).join(', ')}`"
          :format-tick="tick"
          :format-value="value"
        >
          <span
            v-for="item in view.legend"
            :key="item.label"
            class="mr-4 inline-flex items-center gap-2 normal-case"
          >
            <span
              aria-hidden="true"
              class="inline-block w-5 border-t-2"
              :class="[dashClass[item.style.dash], toneClass[item.style.tone]]"
            />{{ item.label }}
          </span>
        </TrendChart>
      </ApRemote>
    </div>
  </ApPanel>
</template>
