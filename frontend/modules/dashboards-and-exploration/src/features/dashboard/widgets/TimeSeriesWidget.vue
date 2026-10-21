<script setup lang="ts">
import { computed } from "vue";
import TelemetryChart from "../../workspace/TelemetryChart.vue";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../../workspace/contracts";
import { snapshotSeries } from "../../workspace/snapshot-series";

const props = defineProps<{
  placement: WorkspacePlacement;
  context: WorkspaceSnapshot["context"];
  live: boolean;
  group: string;
  chartId: string;
}>();

const options = computed(
  () => props.placement.widget?.options ?? { precision: 2, window_seconds: 300 },
);
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
// The dashboard supplies complete server snapshots, including the moving window.
// Append-stream mode waits for a separate heartbeat this viewer does not emit.
const timeMode = computed(() =>
  props.context.time_mode === "live" ? "snapshot" : props.context.time_mode,
);
</script>

<template>
  <div
    class="cadence-time-series-panel-body cadence-time-series-stage flex h-full min-h-0 flex-col"
  >
    <TelemetryChart
      v-if="series"
      :chart_id="chartId"
      :widget_id="placement.authored_id"
      :placement_id="placement.id"
      :correlation_group="group"
      :window_seconds="context.window_seconds ?? options.window_seconds"
      :label="placement.widget?.title ?? ''"
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
      v-bind="{
        ...(options.show_min_max_band === undefined
          ? {}
          : { show_min_max_band: options.show_min_max_band }),
        ...(options.legend_mode === undefined ? {} : { legend_mode: options.legend_mode }),
        ...(options.line_width === undefined ? {} : { line_width: options.line_width }),
        ...(options.fill_opacity === undefined ? {} : { fill_opacity: options.fill_opacity }),
        ...(options.span_gaps === undefined ? {} : { span_gaps: options.span_gaps }),
        ...(options.show_points === undefined ? {} : { show_points: options.show_points }),
        ...(options.axis_mode === undefined ? {} : { axis_mode: options.axis_mode }),
        ...(options.shared_tooltip === undefined ? {} : { shared_tooltip: options.shared_tooltip }),
      }"
    />
    <p v-else class="m-auto text-xs text-base-content/70">This chart's data cannot be plotted.</p>
  </div>
</template>
