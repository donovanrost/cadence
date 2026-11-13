<script setup lang="ts">
import { computed } from "vue";
import { formatClock, ApEmptyState, ApPanel, ApRemote, ApTimeSeries, ApCallout } from "@/ui";
import { formatValue } from "@/features/alarms/index.ts";
import { notPlottable, pointName, seriesChart, seriesMeta } from "../groups/series.ts";
import type { VerifierSeriesQuery } from "./useVerifierSeries.ts";

/**
 * U2 · Verifier (CommandFlow C3, M26): the plotted command's verifier point over the request
 * window, one faint line per target (failed ones brighter), the commanded value dashed and the band
 * dotted. UplinkView owns the read (N Needs you shares it).
 */
const props = defineProps<{ series: VerifierSeriesQuery }>();
const ready = computed(() => props.series.ready.value);
const why = computed(() => (ready.value ? notPlottable(ready.value) : null));
const chart = computed(() => (ready.value ? seriesChart(ready.value) : null));
const tick = (t: number) => formatClock(new Date(t)).slice(0, 5);
const value = (v: number) => formatValue(v) ?? "";
</script>

<template>
  <ApPanel index="U2" title="Verifier" :meta="ready ? seriesMeta(ready) : undefined" flush>
    <ApRemote
      :state="series.state.value"
      loading-label="LOADING VERIFIER…"
      @retry="series.refetch()"
    >
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
          :label="`${pointName(ready)} for ${ready.targets.length} targets`"
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
  </ApPanel>
</template>
