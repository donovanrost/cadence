<script setup lang="ts">
import { RouterLink } from "vue-router";
import { formatClock, ApEmptyState, ApPanel, ApRemote, ApTimeRange, type TimeRange } from "@/ui";
import type { RemoteState } from "@/api/index.ts";
import { formatValue } from "@/features/alarms/index.ts";
import { TrendChart } from "@/features/investigate/index.ts";
import { windowPresets } from "./window.ts";
import type { PlotView } from "./plot.ts";
import type { SeriesData } from "./useSeries.ts";

/** T2 · Plot: one series per spacecraft × point (max 6), grays and dashes, never status hues. */
const QUESTIONS = [
  { label: "Recent anomalies", to: { name: "ops.alarms", query: { tab: "cleared" } } },
  { label: "What changed", to: { name: "ops.timeline", query: { kind: "config" } } },
  { label: "Missing telemetry", to: { name: "setup.data-sources" } },
  { label: "Link health", to: { name: "ops.contacts" } },
] as const;
defineProps<{
  state: RemoteState<SeriesData[]>;
  view: PlotView | null;
  empty: boolean;
  dropped: number;
  windowLabel: string;
}>();
defineEmits<{ retry: [] }>();
const window = defineModel<TimeRange>("window", { required: true });
/** Presets resolve when the picker opens; choosing one goes back through the owner (sliding). */
const presets = windowPresets(new Date());
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
        <ApTimeRange v-model="window" label="Plot window" :presets="presets" />
      </div>
      <ApEmptyState
        v-if="empty"
        headline="Pick a point to plot"
        sentence="Add a spacecraft and search for a point. Each spacecraft × point is one series."
      >
        <!-- Legacy canned questions (L20) are parked (DECISIONS #75); each has a console home. -->
        <ul class="m-0 flex list-none flex-col gap-1 p-0" aria-label="Other questions">
          <li v-for="q in QUESTIONS" :key="q.label">
            <RouterLink
              :to="q.to"
              class="max-md:hit-44 text-md text-readout no-underline hover:text-bright hover:underline"
              >{{ q.label }} →</RouterLink
            >
          </li>
        </ul>
      </ApEmptyState>
      <ApEmptyState
        v-else-if="state.status === 'failed' && state.error.kind === 'unavailable'"
        state="off"
        headline="History not available"
        :sentence="`The telemetry history store can't be reached (${state.error.message}).`"
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
          :label="`${view.legend.length} series over ${windowLabel}: ${view.legend.map((l) => l.label).join(', ')}`"
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
