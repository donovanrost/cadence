<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { throttle } from "@/features/fleet/index.ts";
import { formatClock, ApEmptyState, ApPanel, ApRemote, ApTimeSeries, ApCallout } from "@/ui";
import { formatValue } from "@/features/alarms/index.ts";
import { fetchVerifierSeries, notPlottable, seriesChart, seriesMeta } from "../groups/series.ts";

/**
 * U2 · Verifier (CommandFlow C3, M26): the plotted command's verifier point over the request
 * window, one faint line per target (failed ones brighter), the commanded value dashed and the band
 * dotted. Refetches on commanding, and on telemetry at most every 10 s.
 */
const props = defineProps<{ missionId: string; groupId: string }>();
const series = useRemoteQuery(
  computed(() => `${props.missionId}|${props.groupId}`),
  (k, signal) => {
    const [m = "", g = ""] = k.split("|");
    return fetchVerifierSeries(m, g, signal);
  },
);
const mission = computed(() => props.missionId);
useMissionInvalidation(mission, ["commanding"], series.refetch);
const slow = throttle(series.refetch, 10_000);
useMissionInvalidation(mission, ["telemetry"], slow.call);
const ready = computed(() =>
  series.state.value.status === "ready" ? series.state.value.value : null,
);
const why = computed(() => (ready.value ? notPlottable(ready.value) : null));
const chart = computed(() => (ready.value ? seriesChart(ready.value) : null));
const tick = (t: number) => formatClock(new Date(t)).slice(0, 5);
const value = (v: number) => formatValue(v) ?? "";
</script>

<template>
  <ApPanel index="U2" title="Verifier" :meta="ready ? seriesMeta(ready) : undefined" flush>
    <ApRemote :state="series.state.value" loading-label="LOADING VERIFIER…" @retry="series.refetch">
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
          :label="`${ready.point?.name ?? 'Verifier point'} for ${ready.targets.length} targets`"
          :format-tick="tick"
          :format-value="value"
          :height="180"
          :series-name="ready.point?.name ?? 'Value'"
        />
        <p v-if="ready.truncated" class="m-0 font-mono text-xs text-text-4">
          Showing {{ ready.targets.length }} of {{ ready.target_count }} targets.
        </p>
      </div>
    </ApRemote>
  </ApPanel>
</template>
