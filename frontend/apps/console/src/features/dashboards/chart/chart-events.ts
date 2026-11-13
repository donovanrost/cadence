import type { ChartMarker } from "./chart-input.ts";
import type { ChartSurface } from "./chart-surface.ts";
import { ChartRevisions } from "./chart-revisions.ts";
import { ChartWatermarks } from "./chart-watermarks.ts";

/** Owns event overlays; watermarks and revisions render through their own classes. */
export class ChartEvents {
  readonly eventLayer: HTMLDivElement;
  readonly watermarkOverlayLayer: HTMLDivElement;
  private readonly watermarks: ChartWatermarks;
  private readonly revisions: ChartRevisions;
  constructor(private readonly surface: ChartSurface) {
    this.eventLayer = this.buildEventLayer();
    this.watermarkOverlayLayer = this.buildWatermarkOverlayLayer();
    this.watermarks = new ChartWatermarks(surface, this.watermarkOverlayLayer);
    this.revisions = new ChartRevisions(surface, this.eventLayer);
  }
  buildEventLayer() {
    const layer = document.createElement("div");
    layer.className = "telemetry-chart-event-overlays";
    layer.setAttribute("aria-hidden", "false");
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      bottom: `${this.surface.model.legendHeight()}px`,
      pointerEvents: "none",
      zIndex: "2",
    });
    return layer;
  }

  buildWatermarkOverlayLayer() {
    const layer = document.createElement("div");
    layer.className = "telemetry-chart-watermark-overlays";
    layer.dataset.chartWatermarkOverlayLayer = "true";
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      pointerEvents: "none",
    });
    return layer;
  }

  attachWatermarkOverlayLayer() {
    const plotOverlay = this.surface.chart.over || this.surface.el.querySelector(".u-over");
    if (!plotOverlay || !this.watermarkOverlayLayer) return;

    // uPlot appends its native cursor after this layer. Keeping the watermark
    // wash inside `.u-over` but before the cursor lets it tint the plot without
    // covering the synchronized crosshair.
    plotOverlay.insertBefore(this.watermarkOverlayLayer, plotOverlay.firstChild);
  }

  renderEventMarkers() {
    if (!this.eventLayer || !this.surface.chart) return;

    this.eventLayer.replaceChildren();
    if (this.watermarkOverlayLayer) this.watermarkOverlayLayer.replaceChildren();
    delete this.surface.el.dataset.watermarkState;
    delete this.surface.el.dataset.watermarkLagMs;
    delete this.surface.el.dataset.watermarkBoundaryVisible;

    this.surface.model.eventMarkers.forEach((marker) => {
      if (marker.marker_type === "source_binding_interval") {
        this.renderSourceBindingInterval(marker);
        return;
      }

      if (marker.marker_type === "retention_gap") {
        this.renderRetentionGap(marker);
        return;
      }

      if (
        marker.marker_type === "source_watermark_cursor" ||
        marker.marker_type === "source_watermark_event"
      ) {
        this.watermarks.renderSourceWatermarkCursor(marker);
        return;
      }

      if (marker.marker_type === "telemetry_revision_range") {
        this.revisions.renderTelemetryRevisionRange(marker);
        return;
      }

      if (marker.marker_type === "telemetry_backfill_lifecycle") {
        this.revisions.renderTelemetryBackfillLifecycle(marker);
        return;
      }

      if (marker.marker_type === "telemetry_revision_decision") {
        this.revisions.renderTelemetryRevisionDecision(marker);
        return;
      }

      if (marker.marker_type === "mission_event") {
        this.renderMissionEvent(marker);
      }
    });
  }

  renderSourceBindingInterval(marker: ChartMarker) {
    if (!marker.marker_id || !marker.starts_at_ms) return;

    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const button = document.createElement("button");
    button.type = "button";
    button.title = `Inspect ${marker.label || "source binding interval"}`;
    button.setAttribute("aria-label", button.title);
    button.dataset.eventMarkerTarget = "source binding";
    button.dataset.eventMarkerId = marker.source_binding_id || marker.target_id || "";
    button.dataset.eventMarkerRef = marker.marker_id || "";
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      border: "0",
      borderLeft: `1px solid ${this.surface.sourceBindingIntervalColor(marker)}`,
      borderRight: `1px solid ${this.surface.sourceBindingIntervalColor(marker)}`,
      padding: "0",
      background: `${this.surface.themeColor("--chart-revision-7")}`,
      cursor: "pointer",
      pointerEvents: "auto",
    });

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      const dataLinkPayload = this.watermarks.sourceWatermarkDataLinkPayload(marker);
      if (dataLinkPayload) {
        this.surface.pushEvent("open_data_link", dataLinkPayload);
        return;
      }

      this.surface.pushEvent("open_evidence", {
        kind: "source",
        "source-evidence-mode": "health",
        "source-evidence-state": marker.freshness_state,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "replay-run-id": marker.replay_run_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id || marker.target_id,
        "placement-id": this.surface.model.placementId,
      });
    });

    this.eventLayer.appendChild(button);
  }

  renderRetentionGap(marker: ChartMarker) {
    if (!marker.marker_id || !marker.starts_at_ms || !marker.ends_at_ms) return;

    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const button = document.createElement("button");
    button.type = "button";
    button.title = `Inspect ${marker.label || "retention gap"}`;
    button.setAttribute("aria-label", button.title);
    button.dataset.eventMarkerTarget = "retention gap";
    button.dataset.eventMarkerId = marker.target_id || marker.data_source_id || "";
    button.dataset.eventMarkerRef = marker.marker_id || "";
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      border: "0",
      borderRight: `1px solid ${this.surface.retentionGapColor(marker)}`,
      padding: "0",
      background: `${this.surface.themeColor("--chart-critical-9")}`,
      cursor: "pointer",
      pointerEvents: "auto",
    });

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.surface.pushEvent("open_evidence", {
        kind: "source",
        "source-evidence-mode": "health",
        "source-evidence-state": marker.freshness_state,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "replay-run-id": marker.replay_run_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "placement-id": this.surface.model.placementId,
      });
    });

    this.eventLayer.appendChild(button);
  }

  renderMissionEvent(marker: ChartMarker) {
    if (!marker.link_id || !marker.timestamp_ms) return;

    const left = this.surface.markerLeft(marker);
    if (left === null || left === undefined || Number.isNaN(left)) return;

    const button = document.createElement("button");
    button.type = "button";
    button.title = `Inspect ${marker.title || "mission event"}`;
    button.setAttribute("aria-label", button.title);
    button.dataset.eventMarkerTarget = "mission event";
    button.dataset.eventMarkerId = marker.mission_event_id || marker.target_id || "";
    button.dataset.eventMarkerRef = marker.link_id || "";
    Object.assign(button.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      width: "12px",
      transform: "translateX(-6px)",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    });

    const line = document.createElement("span");
    Object.assign(line.style, {
      display: "block",
      width: "1px",
      height: "100%",
      margin: "0 auto",
      background: this.surface.eventColor(marker),
      boxShadow: `0 0 6px ${this.surface.eventColor(marker)}`,
    });
    button.appendChild(line);

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.surface.pushEvent(
        "open_data_link",
        this.surface.markerDataLinkPayload(
          marker,
          "mission_event",
          marker.target_id || marker.mission_event_id,
          marker.timestamp_ms,
        ),
      );
    });

    this.eventLayer.appendChild(button);
  }
}
