<script setup lang="ts">
import { onBeforeUnmount, onMounted, onUpdated, ref, watch } from "vue";
import { useChartRuntime } from "./chart-runtime";
import { TelemetryChartController } from "./chart-controller";
import type { TelemetryChartProps } from "./chart-props";
import "../../charts.css";

const props = withDefaults(defineProps<TelemetryChartProps>(), {
  edit_mode: false,
  show_min_max_band: true,
  legend_mode: "auto",
  line_width: "normal",
  fill_opacity: 8,
  span_gaps: false,
  show_points: false,
  axis_mode: "unit",
  shared_tooltip: true,
  label: "",
  unit: "",
  backfill: () => [],
  compare_backfill: () => [],
  limit_markers: () => [],
  event_markers: () => [],
  annotations: () => [],
  selected_ref: null,
  time_mode: "",
  time_from: "",
  time_to: "",
  time_axis: "",
  replay_run_id: "",
  data_realm: "",
  data_view: "",
  compare_data_view: "",
  data_source_id: "",
  source_binding_id: "",
  data_management_badges: "",
  compare_data_management_badges: "",
  engine_backed: false,
});
const chartRoot = ref<HTMLElement | null>(null);
const live = useChartRuntime();
let controller: TelemetryChartController | null = null;
const serialize = (value: unknown) => JSON.stringify(value ?? null);
live.on("append", (payload) => controller?.handleAppend(payload));
live.on("selection", (payload) => controller?.handleSelection(payload));
onMounted(() => {
  if (chartRoot.value)
    controller = new TelemetryChartController(chartRoot.value, props, (event, payload) =>
      live.pushEvent(event, payload),
    );
});
onUpdated(() => controller?.updateSnapshot(props));
watch(
  () => props.selected_ref,
  (selection) => controller?.updated(selection),
  { deep: true, flush: "post" },
);
onBeforeUnmount(() => {
  controller?.destroyed();
  controller = null;
});
</script>

<template>
  <div
    ref="chartRoot"
    :id="props.chart_id"
    data-telemetry-chart
    data-dashboard-time-series-chart
    :data-widget-id="props.widget_id"
    :data-placement-id="props.placement_id"
    :data-window-seconds="String(props.window_seconds)"
    :data-correlation-group="props.correlation_group"
    :data-edit-mode="String(props.edit_mode)"
    :data-show-min-max-band="String(props.show_min_max_band)"
    :data-legend-mode="props.legend_mode"
    :data-line-width="props.line_width"
    :data-fill-opacity="String(props.fill_opacity)"
    :data-span-gaps="String(props.span_gaps)"
    :data-show-points="String(props.show_points)"
    :data-axis-mode="props.axis_mode"
    :data-shared-tooltip="String(props.shared_tooltip)"
    :data-label="props.label"
    :data-unit="props.unit"
    :data-backfill="serialize(props.backfill)"
    :data-compare-backfill="serialize(props.compare_backfill)"
    :data-limit-markers="serialize(props.limit_markers)"
    :data-event-markers="serialize(props.event_markers)"
    :data-annotations="serialize(props.annotations)"
    :data-selected-ref="serialize(props.selected_ref)"
    :data-time-mode="props.time_mode"
    :data-time-from="props.time_from"
    :data-time-to="props.time_to"
    :data-time-axis="props.time_axis"
    :data-replay-run-id="props.replay_run_id"
    :data-data-realm="props.data_realm"
    :data-data-view="props.data_view"
    :data-compare-data-view="props.compare_data_view"
    :data-data-source-id="props.data_source_id"
    :data-source-binding-id="props.source_binding_id"
    :data-data-management-badges="props.data_management_badges"
    :data-compare-data-management-badges="props.compare_data_management_badges"
    :data-engine-backed="props.engine_backed ? 'true' : undefined"
    data-panel-presentation="grafana"
    class="cadence-time-series-chart h-full min-h-0 w-full flex-1 overflow-hidden"
  ></div>
</template>
