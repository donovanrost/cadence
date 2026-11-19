<script setup lang="ts">
import { computed } from "vue";
import TelemetryChart from "../chart/TelemetryChart.vue";
import type { ChartAnnotation } from "../chart/chart-markers.ts";
import type { ReadyPlacement, WorkspaceSnapshot } from "../model/snapshot.ts";
import { overlayMarkers } from "../model/overlay-markers.ts";
import { hasData } from "../model/widget-data.ts";
import { snapshotSeries } from "../model/snapshot-series.ts";
import { chartSentence } from "../model/chart-sentence.ts";

/** Time series on the ported uPlot engine, from the snapshot's decimated envelope frames. */
const props = defineProps<{
  placement: ReadyPlacement;
  context: WorkspaceSnapshot["context"];
  group: string;
  chartId: string;
  /** The board's clock (ms): rolls an empty live range. */
  now: number;
}>();

const options = computed(() => props.placement.widget.options);
const series = computed(() => {
  // No samples: nothing to parse (a past range's empty frames needn't be parseable; qa's fixed
  // 11-10 range threw here and drew no frame), but the frame, bands and marks still draw.
  if (!hasData(props.placement)) return { primary: [], compare: [] };
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
/**
 * No samples in range (ux, Overlays): the chart still draws its frame (x axis from the range, the
 * stale hatch, bands and marks) under a caption that never says why, since dropped and never sent
 * look the same. A live range draws now−window…now, rolling with the board's clock, with the
 * now-line (the chart's own live mode).
 */
const empty = computed(() => !hasData(props.placement));
const liveEmpty = computed(() => empty.value && props.context.time_mode === "live");
const frameable = computed(
  () => liveEmpty.value || Boolean(props.context.from && props.context.to),
);
/** The chart reads as an image with a sentence (a11y B5). */
const sentence = computed(() =>
  chartSentence(props.placement.widget.title, series.value?.primary ?? [], {
    live: props.context.time_mode === "live",
    from: props.context.from,
    to: props.context.to,
    windowSeconds: props.context.window_seconds ?? options.value.window_seconds,
  }),
);
/** Limits and contacts from the placement's overlay frames (ux Dashboards.md 'Overlays'). */
const overlay = computed(() => overlayMarkers(props.placement));
/** An unrecognized annotation kind draws as a point, as the chart always did. */
const annotations = computed(() =>
  props.placement.annotations.map((a): ChartAnnotation => ({
    annotation_id: a.id,
    title: a.title,
    severity: a.severity,
    geometry: a.kind === "interval" ? "interval" : "point",
    starts_at_ms: a.starts_at_ms,
    ends_at_ms: a.ends_at_ms,
  })),
);
// Every refresh delivers a complete snapshot (moving window included). Append mode would wait
// for a stream heartbeat the console doesn't send yet (plan: live step 3).
const timeMode = computed(() =>
  liveEmpty.value
    ? "live"
    : props.context.time_mode === "live"
      ? "snapshot"
      : props.context.time_mode,
);
/** An empty live range's window end; a new value each tick rolls the frame (no rebuild). */
const timeTo = computed(() =>
  liveEmpty.value ? new Date(props.now).toISOString() : (props.context.to ?? ""),
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
  <div class="relative flex h-full min-h-0 flex-col overflow-hidden px-1 pb-1">
    <!-- Beside the canvas, not on it: the chart holds focusable annotation controls. -->
    <span role="img" :aria-label="sentence" class="sr-only" />
    <TelemetryChart
      v-if="series && (!empty || frameable)"
      :chart_id="chartId"
      :widget_id="placement.authored_id"
      :placement_id="placement.id"
      :correlation_group="group"
      :window_seconds="context.window_seconds ?? options.window_seconds"
      :label="placement.widget.title"
      :backfill="{ series: series.primary }"
      :compare_backfill="{ series: series.compare }"
      :annotations="annotations"
      :limit_markers="overlay.limitMarkers"
      :event_markers="overlay.eventMarkers"
      :time_mode="timeMode"
      :time_axis="placement.frames[0]?.time_axis ?? context.time_axis"
      :time_from="context.from ?? ''"
      :time_to="timeTo"
      :data_realm="context.realm"
      :data_view="context.data_view"
      :engine_backed="true"
      v-bind="optional"
    />
    <p v-else-if="!empty" class="m-auto text-sm text-text-3">This chart's data can't be plotted.</p>
    <p
      v-if="empty"
      class="pointer-events-none absolute inset-0 m-0 grid place-items-center text-sm text-text-3"
    >
      <!-- Backed so it reads over the stale hatch (qa). -->
      <span class="border border-hairline bg-panel px-2 py-0.5">No samples in this range.</span>
    </p>
  </div>
</template>
