import { record } from "@cadence/plugin-sdk/admission";
import type { TelemetryChartProps } from "./chart-props";
import type { ChartAction } from "./chart-runtime";
import { ChartModel } from "./chart-model";
import { ChartSurface } from "./chart-surface";
import { ChartPlot } from "./chart-plot";
import { ChartLegend } from "./chart-legend";
import { ChartAnnotations } from "./chart-annotations";
import { ChartEvents } from "./chart-events";
import { ChartLimits } from "./chart-limits";
import { ChartSelection } from "./chart-selection";
import { ChartLive } from "./chart-live";
import { readSelection } from "./chart-input";

/** Owns the mounted lifetime. Data and renderers never install global observers themselves. */
export class TelemetryChartController {
  private get model() {
    return this.surface.model;
  }
  private snapshotSignature: string;
  private readonly surface: ChartSurface;
  private readonly plot: ChartPlot;
  private readonly legend: ChartLegend;
  private readonly annotations: ChartAnnotations;
  private readonly events: ChartEvents;
  private readonly limits: ChartLimits;
  private readonly selection: ChartSelection;
  private readonly live: ChartLive;
  private readonly resizeObserver: ResizeObserver;
  private readonly themeObserver: MutationObserver;
  private disposed = false;
  private readonly handleClick = (event: MouseEvent) => this.selection.openPointInspector(event);
  constructor(
    el: HTMLElement,
    input: TelemetryChartProps,
    pushEvent: (action: ChartAction, payload: Record<string, unknown>) => void,
  ) {
    this.snapshotSignature = snapshotSignature(input);
    this.surface = new ChartSurface(el, new ChartModel({ ...input }), pushEvent, () =>
      this.rebuild(),
    );
    this.legend = new ChartLegend(this.surface);
    this.annotations = new ChartAnnotations(this.surface);
    this.events = new ChartEvents(this.surface);
    this.limits = new ChartLimits(this.surface);
    this.selection = new ChartSelection(this.surface);
    this.live = new ChartLive(this.surface);
    this.plot = new ChartPlot(this.surface, (plot) => {
      if (this.surface.plot) this.legend.renderSharedTooltip(plot);
    });
    el.style.position = "relative";
    this.plot.mount();
    this.attachLayers();
    this.render();
    el.addEventListener("click", this.handleClick);
    this.resizeObserver = new ResizeObserver(() => {
      if (this.disposed) return;
      this.legend.renderLegend();
      this.surface.chart.setSize(this.surface.chartSize());
      this.render();
    });
    this.resizeObserver.observe(el);
    this.themeObserver = new MutationObserver(() => {
      if (this.disposed) return;
      this.surface.themeStyles = getComputedStyle(el);
      this.rebuild();
    });
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme", "data-skin", "style", "class"],
    });
  }
  handleAppend(payload: Record<string, unknown>) {
    if (this.disposed) return;
    const { series, markers, window_end_ms, refresh_interval_ms } = payload;
    const points = record(series)
      ? series[this.model.widgetId] || series[this.model.placementId]
      : undefined;
    const appendedPointCount = this.model.seriesPayloadPointCount(points);
    const previousLength = this.model.plotSeries.length;
    const appendedSeries = this.model.appendSeriesPayload(points);
    const markerAppends = record(markers)
      ? markers[this.model.widgetId] || markers[this.model.placementId]
      : undefined;
    const appendedMarkers = this.model.appendMarkerPayload(markerAppends);
    const advancedLiveWindow = this.model.advanceLiveWindow(window_end_ms);
    this.live.recordLiveActivity({
      appendedPointCount,
      advancedLiveWindow,
      refreshIntervalMs: refresh_interval_ms,
      seriesPayload: points,
      windowEndMs: window_end_ms,
    });
    if (!appendedSeries && !appendedMarkers && !advancedLiveWindow) return;
    this.model.trimToWindow();
    if (this.model.plotSeries.length !== previousLength) this.rebuild();
    else {
      this.surface.chart.setData(this.model.plotData());
      this.render();
    }
  }
  handleSelection(payload: Record<string, unknown>) {
    this.updated(payload.selection);
  }
  updateSnapshot(input: TelemetryChartProps) {
    if (this.disposed) return;
    const signature = snapshotSignature(input);
    // Equal server projections must not discard samples received through the append channel.
    if (signature === this.snapshotSignature) return;
    const previous = this.model;
    const next = new ChartModel({ ...input });
    if (chartIdentity(previous.input) === chartIdentity(input)) {
      next.hiddenSeriesIds = new Set(
        next.seriesList
          .filter((series) => previous.hiddenSeriesIds.has(series.id))
          .map((series) => series.id),
      );
      next.selectedRef = previous.selectedRef;
      if (previous.input.axis_mode === input.axis_mode) next.axisMode = previous.axisMode;
    }
    const rebuild = plotSignature(previous) !== plotSignature(next);
    this.snapshotSignature = signature;
    this.surface.model = next;
    this.live.reset();
    if (rebuild) this.rebuild();
    else {
      this.surface.chart.setData(next.plotData());
      this.render();
    }
  }
  updated(selection: unknown) {
    if (this.disposed) return;
    this.model.selectedRef = readSelection(selection);
    this.selection.renderSelection();
  }
  private attachLayers() {
    this.events.attachWatermarkOverlayLayer();
    this.surface.el.append(
      this.events.eventLayer,
      this.annotations.annotationLayer,
      this.limits.markerLayer,
      this.selection.selectionLayer,
      this.live.liveEdge,
      this.legend.legendLayer,
      this.legend.tooltipLayer,
    );
  }
  private render() {
    const { el, model } = this.surface;
    el.dataset.compareSeriesCount = `${model.seriesList.filter((series) => series.role === "compare").length}`;
    el.dataset.chartPointCount = `${model.pointCount}`;
    el.dataset.chartLatestTimestampMs =
      model.latestTimestampMs === null ? "" : `${model.latestTimestampMs}`;
    if (model.liveWindowEnd !== null) {
      el.dataset.liveWindowStartMs = `${Math.round((model.liveWindowEnd - model.windowSeconds) * 1000)}`;
      el.dataset.liveWindowEndMs = `${Math.round(model.liveWindowEnd * 1000)}`;
    } else {
      delete el.dataset.liveWindowStartMs;
      delete el.dataset.liveWindowEndMs;
    }
    this.events.renderEventMarkers();
    this.annotations.renderAnnotations();
    this.limits.renderLimitMarkers();
    this.legend.renderLegend();
    this.selection.renderSelection();
    this.live.renderLiveEdge();
  }
  private rebuild() {
    if (this.disposed) return;
    this.plot.destroy();
    this.plot.mount();
    this.attachLayers();
    this.render();
  }
  destroyed() {
    if (this.disposed) return;
    this.disposed = true;
    this.surface.el.removeEventListener("click", this.handleClick);
    this.resizeObserver.disconnect();
    this.themeObserver.disconnect();
    this.live.destroy();
    this.plot.destroy();
    for (const layer of [
      this.events.eventLayer,
      this.events.watermarkOverlayLayer,
      this.annotations.annotationLayer,
      this.limits.markerLayer,
      this.selection.selectionLayer,
      this.legend.legendLayer,
      this.legend.tooltipLayer,
    ])
      layer.remove();
  }
}

function snapshotSignature(input: TelemetryChartProps) {
  const snapshot = { ...input };
  delete snapshot.selected_ref;
  return JSON.stringify(snapshot);
}

function chartIdentity(input: Readonly<TelemetryChartProps>) {
  return JSON.stringify([
    input.widget_id,
    input.placement_id,
    input.data_realm,
    input.data_view,
    input.time_axis,
    input.replay_run_id,
    input.data_source_id,
    input.source_binding_id,
  ]);
}

function plotSignature(model: ChartModel) {
  const options = { ...model.input };
  delete options.backfill;
  delete options.compare_backfill;
  delete options.limit_markers;
  delete options.event_markers;
  delete options.annotations;
  delete options.selected_ref;
  return JSON.stringify({
    options,
    axisMode: model.axisMode,
    hidden: [...model.hiddenSeriesIds],
    series: model.seriesList.map(({ id, label, unit, role, compare_of }) => ({
      id,
      label,
      unit,
      role,
      compare_of,
    })),
    plots: model.plotSeries.map(({ kind, seriesIndex }) => ({ kind, seriesIndex })),
  });
}
