<script setup lang="ts">
import type { RemoteState } from "@/api/index.ts";
import { computed } from "vue";
import { formatClock, ApCallout, ApEmptyState, ApRemote, ApTimeSeries } from "@/ui";
import { formatValue } from "@/features/alarms/index.ts";
import {
  notPlottable,
  plotSentence,
  pointName,
  seriesChart,
  type VerifierSeries,
} from "../groups/series.ts";

/**
 * One verifier plot (U2): a point over the request window, one faint line per target (failed ones
 * brighter), the commanded value dashed and the band dotted. U51 captions it with its targets when
 * the group plots several points.
 */
const props = defineProps<{ state: RemoteState<VerifierSeries>; caption?: string | undefined }>();
defineEmits<{ retry: [] }>();
const ready = computed(() => (props.state.status === "ready" ? props.state.value : null));
const why = computed(() => (ready.value ? notPlottable(ready.value) : null));
const chart = computed(() => (ready.value ? seriesChart(ready.value) : null));
const tick = (t: number) => formatClock(new Date(t)).slice(0, 5);
const value = (v: number) => formatValue(v) ?? "";
</script>

<template>
  <div class="flex flex-col">
    <p v-if="caption" class="m-0 px-3 pt-3 font-mono text-xs text-text-3 uppercase">
      {{ caption }}
    </p>
    <ApRemote :state="state" loading-label="LOADING VERIFIER…" @retry="$emit('retry')">
      <ApEmptyState v-if="why" state="off" :headline="why" />
      <div v-else-if="chart && ready" class="flex flex-col gap-2 p-3">
        <ApCallout v-if="ready.telemetry === 'degraded'" tone="stale">
          Telemetry history unavailable: samples may be missing.
        </ApCallout>
        <ApTimeSeries
          :series="[]"
          :comparison="chart.lines"
          :window="chart.window"
          :now="Date.now()"
          :label="plotSentence(ready)"
          :format-tick="tick"
          :format-value="value"
          :height="180"
          :series-name="pointName(ready)"
        />
        <p v-if="ready.truncated" class="m-0 font-mono text-xs text-text-4">
          Showing {{ ready.targets.length }} of {{ ready.target_count }} targets.
        </p>
      </div>
    </ApRemote>
  </div>
</template>
