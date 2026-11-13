<script setup lang="ts">
import { computed } from "vue";
import TelemetryChart from "../chart/TelemetryChart.vue";
import type { ReadyPlacement, WorkspaceSnapshot } from "../model/snapshot.ts";
import { snapshotSeries } from "../model/snapshot-series.ts";

/** Time series on the ported uPlot engine, from the snapshot's decimated envelope frames. */
const props = defineProps<{
  placement: ReadyPlacement;
  context: WorkspaceSnapshot["context"];
  group: string;
  chartId: string;
}>();

const options = computed(() => props.placement.widget.options);
const series = computed(() => {
  const frames = (role: string) => props.placement.frames.filter((f) => f.role === role);
  try {
    return {
      primary: snapshotSeries(frames("primary"), props.placement.id),
      compare: snapshotSeries(frames("compare"), props.placement.id),
    };
  } catch {
    return null;
  }
});
const annotations = computed(() =>
  props.placement.annotations.map((a) => ({
    annotation_id: a.id,
    title: a.title,
    severity: a.severity,
    geometry: a.kind,
    starts_at_ms: a.starts_at_ms,
    ends_at_ms: a.ends_at_ms,
    ...(a.kind === "point" ? { timestamp_ms: a.starts_at_ms } : {}),
  })),
);
// Every refresh delivers a complete snapshot (moving window included). Append mode would wait
// for a stream heartbeat the console doesn't send yet (plan: live step 3).
const timeMode = computed(() =>
  props.context.time_mode === "live" ? "snapshot" : props.context.time_mode,
);
const optional = computed(() => {
  const o = options.value;
  return {
    ...(o.show_min_max_band === undefined ? {} : { show_min_max_band: o.show_min_max_band }),
    // An option value this console doesn't know falls back to the chart's default.
    ...(o.legend_mode === undefined || o.legend_mode === "unrecognized"
      ? {}
      : { legend_mode: o.legend_mode }),
    ...(o.line_width === undefined || o.line_width === "unrecognized"
      ? {}
      : { line_width: o.line_width }),
    ...(o.fill_opacity === undefined ? {} : { fill_opacity: o.fill_opacity }),
    ...(o.span_gaps === undefined ? {} : { span_gaps: o.span_gaps }),
    ...(o.show_points === undefined ? {} : { show_points: o.show_points }),
    ...(o.axis_mode === undefined || o.axis_mode === "unrecognized"
      ? {}
      : { axis_mode: o.axis_mode }),
    ...(o.shared_tooltip === undefined ? {} : { shared_tooltip: o.shared_tooltip }),
  };
});
</script>

<template>
  <div class="flex h-full min-h-0 flex-col overflow-hidden px-1 pb-1">
    <TelemetryChart
      v-if="series"
      :chart_id="chartId"
      :widget_id="placement.authored_id"
      :placement_id="placement.id"
      :correlation_group="group"
      :window_seconds="context.window_seconds ?? options.window_seconds"
      :label="placement.widget.title"
      :backfill="{ series: series.primary }"
      :compare_backfill="{ series: series.compare }"
      :annotations="annotations"
      :time_mode="timeMode"
      :time_axis="placement.frames[0]?.time_axis ?? context.time_axis"
      :time_from="context.from ?? ''"
      :time_to="context.to ?? ''"
      :data_realm="context.realm"
      :data_view="context.data_view"
      :engine_backed="true"
      v-bind="optional"
    />
    <p v-else class="m-auto text-sm text-text-3">This chart's data can't be plotted.</p>
  </div>
</template>
