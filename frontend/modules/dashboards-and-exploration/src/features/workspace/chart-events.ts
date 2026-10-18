import { synchronizeCursor } from "./chart-uplot";
import type { ChartMarker } from "./chart-input";
import type { ChartSurface } from "./chart-surface";

/** Owns event and source watermark overlays, including synchronized cursor passthrough. */
export class ChartEvents {
  readonly eventLayer: HTMLDivElement;
  readonly watermarkOverlayLayer: HTMLDivElement;
  constructor(private readonly surface: ChartSurface) {
    this.eventLayer = this.buildEventLayer();
    this.watermarkOverlayLayer = this.buildWatermarkOverlayLayer();
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
        this.renderSourceWatermarkCursor(marker);
        return;
      }

      if (marker.marker_type === "telemetry_revision_range") {
        this.renderTelemetryRevisionRange(marker);
        return;
      }

      if (marker.marker_type === "telemetry_backfill_lifecycle") {
        this.renderTelemetryBackfillLifecycle(marker);
        return;
      }

      if (marker.marker_type === "telemetry_revision_decision") {
        this.renderTelemetryRevisionDecision(marker);
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
      const dataLinkPayload = this.sourceWatermarkDataLinkPayload(marker);
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

  renderSourceWatermarkCursor(marker: ChartMarker) {
    if (!marker.marker_id || !marker.timestamp_ms) return;

    const left = this.surface.markerLeft(marker);
    const boundaryVisible = marker.display_mode !== "status";

    if (boundaryVisible && left !== null && left !== undefined && !Number.isNaN(left)) {
      this.renderSourceWatermarkIncompleteRegion(marker, left);
      this.renderSourceWatermarkBoundary(marker, left);
    }

    this.renderSourceWatermarkStatus(marker, boundaryVisible);
  }

  renderSourceWatermarkBoundary(marker: ChartMarker, left: number) {
    const button = document.createElement("button");
    button.type = "button";
    button.title = `Inspect ${marker.label || "source watermark cursor"}`;
    button.setAttribute("aria-label", button.title);
    button.dataset.eventMarkerTarget = "source watermark";
    button.dataset.eventMarkerId =
      marker.source_watermark_event_id || marker.target_id || marker.data_source_id || "";
    button.dataset.eventMarkerRef = marker.marker_id || "";
    button.dataset.watermarkBoundary = marker.freshness_state || "unknown";
    Object.assign(button.style, {
      position: "absolute",
      left: `${left - (this.surface.chart.bbox.left || 0)}px`,
      top: "0",
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      width: "14px",
      transform: "translateX(-7px)",
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
      background: this.surface.sourceWatermarkCursorColor(marker),
      boxShadow: `0 0 6px ${this.surface.sourceWatermarkCursorColor(marker)}`,
    });
    button.appendChild(line);

    this.installSourceWatermarkAction(button, marker);
    this.watermarkOverlayLayer.appendChild(button);
  }

  renderSourceWatermarkIncompleteRegion(marker: ChartMarker, left: number) {
    const plotLeft = this.surface.chart.bbox.left || 0;
    const plotRight = plotLeft + (this.surface.chart.bbox.width || this.surface.el.clientWidth);
    const regionLeft = Math.max(plotLeft, Math.min(plotRight, left));
    const width = Math.max(0, plotRight - regionLeft);
    if (width <= 0) return;

    const region = document.createElement("div");
    region.dataset.sourceWatermarkIncompleteRegion = marker.freshness_state || "unknown";
    Object.assign(region.style, {
      position: "absolute",
      left: `${regionLeft - plotLeft}px`,
      top: "0",
      width: `${width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      borderLeft: `1px dashed ${this.surface.sourceWatermarkCursorColor(marker)}`,
      backgroundColor: this.sourceWatermarkRegionColor(marker),
      backgroundImage: `repeating-linear-gradient(135deg, transparent 0, transparent 8px, ${this.surface.themeColor("--chart-border-7")} 8px, ${this.surface.themeColor("--chart-border-7")} 9px)`,
      pointerEvents: "none",
    });
    this.watermarkOverlayLayer.appendChild(region);
  }

  renderSourceWatermarkStatus(marker: ChartMarker, boundaryVisible: boolean) {
    const lagMs = this.sourceWatermarkLagMs(marker);
    const state = boundaryVisible ? "incomplete" : "complete";
    const status = document.createElement("button");
    const statusText = this.sourceWatermarkStatusText(marker, lagMs, boundaryVisible);

    status.type = "button";
    status.title = this.sourceWatermarkStatusTitle(marker, lagMs, boundaryVisible);
    status.setAttribute("aria-label", status.title);
    status.dataset.eventMarkerTarget = "source watermark status";
    status.dataset.eventMarkerId =
      marker.source_watermark_event_id || marker.target_id || marker.data_source_id || "";
    status.dataset.eventMarkerRef = marker.marker_id || "";
    status.dataset.sourceWatermarkStatus = state;
    status.dataset.sourceWatermarkLagMs = `${lagMs}`;
    status.textContent = statusText;

    Object.assign(status.style, {
      position: "absolute",
      left: "10px",
      top: "8px",
      border: `1px solid ${this.sourceWatermarkStatusBorder(marker, boundaryVisible)}`,
      borderRadius: "3px",
      background: boundaryVisible
        ? `${this.surface.themeColor("--chart-warning-surface-90")}`
        : `${this.surface.themeColor("--chart-current-surface-86")}`,
      color: boundaryVisible
        ? `${this.surface.themeColor("--chart-warning-text-96")}`
        : `${this.surface.themeColor("--chart-current-text-94")}`,
      cursor: "pointer",
      font: "600 10px ui-monospace, SFMono-Regular, Menlo, monospace",
      letterSpacing: "0.06em",
      lineHeight: "1",
      padding: "4px 6px",
      pointerEvents: "auto",
      textTransform: "uppercase",
      whiteSpace: "nowrap",
    });

    this.surface.el.dataset.watermarkState = state;
    this.surface.el.dataset.watermarkLagMs = `${lagMs}`;
    this.surface.el.dataset.watermarkBoundaryVisible = `${boundaryVisible}`;

    this.installSourceWatermarkAction(status, marker);
    this.watermarkOverlayLayer.appendChild(status);
  }

  installSourceWatermarkAction(control: HTMLElement, marker: ChartMarker) {
    this.installSharedCursorPassthrough(control);

    control.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      const dataLinkPayload = this.sourceWatermarkDataLinkPayload(marker);
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
        "requested-dataset": marker.requested_dataset,
        "requested-validity-state": marker.requested_validity_state,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "placement-id": this.surface.model.placementId,
      });
    });
  }

  installSharedCursorPassthrough(control: HTMLElement) {
    control.dataset.chartCursorPassthrough = "true";

    const updateCursor = (event: MouseEvent) => {
      const overlay = this.surface.el.querySelector && this.surface.el.querySelector(".u-over");
      if (!overlay || !this.surface.chart || typeof this.surface.chart.setCursor !== "function")
        return;

      const rect = overlay.getBoundingClientRect();
      synchronizeCursor(this.surface.chart, {
        left: event.clientX - rect.left,
        top: event.clientY - rect.top,
      });
    };

    control.addEventListener("mouseenter", updateCursor);
    control.addEventListener("mousemove", updateCursor);
    control.addEventListener("mouseleave", () => {
      if (!this.surface.chart || typeof this.surface.chart.setCursor !== "function") return;
      synchronizeCursor(this.surface.chart, { left: -10, top: -10 });
    });
  }

  sourceWatermarkLagMs(marker: ChartMarker) {
    const windowEnd = this.surface.model.chartWindowEnd();
    if (windowEnd === null || !Number.isFinite(windowEnd)) return 0;
    return Math.max(0, Math.round(windowEnd * 1000 - Number(marker.timestamp_ms)));
  }

  sourceWatermarkStatusText(marker: ChartMarker, lagMs: number, boundaryVisible: boolean) {
    const prefix =
      marker.freshness_state === "retention_gap"
        ? "Retention gap"
        : boundaryVisible
          ? "Incomplete"
          : "Complete";
    return `${prefix} · ${this.formatSourceWatermarkLag(lagMs)}`;
  }

  sourceWatermarkStatusTitle(marker: ChartMarker, lagMs: number, boundaryVisible: boolean) {
    const timestamp = new Date(Number(marker.timestamp_ms)).toLocaleString();
    const prefix = boundaryVisible ? "Data is complete through" : "Data complete through";
    return `${prefix} ${timestamp} · ${this.formatSourceWatermarkLag(lagMs)}`;
  }

  formatSourceWatermarkLag(lagMs: number) {
    if (lagMs < 1_000) return "current";
    if (lagMs < 10_000) return `${(lagMs / 1_000).toFixed(1)}s behind`;
    if (lagMs < 60_000) return `${Math.round(lagMs / 1_000)}s behind`;
    if (lagMs < 3_600_000) return `${Math.round(lagMs / 60_000)}m behind`;
    return `${Math.round(lagMs / 3_600_000)}h behind`;
  }

  sourceWatermarkStatusBorder(marker: ChartMarker, boundaryVisible: boolean) {
    if (!boundaryVisible) return `${this.surface.themeColor("--chart-current-36")}`;
    return this.surface.sourceWatermarkCursorColor(marker);
  }

  sourceWatermarkRegionColor(marker: ChartMarker) {
    if (marker.freshness_state === "retention_gap")
      return `${this.surface.themeColor("--chart-retention-surface-10")}`;
    if (marker.freshness_state === "stale")
      return `${this.surface.themeColor("--chart-stale-surface-10")}`;
    return `${this.surface.themeColor("--chart-unknown-surface-10")}`;
  }

  sourceWatermarkDataLinkPayload(marker: ChartMarker) {
    if (marker.marker_type !== "source_watermark_event" || !marker.link_id) return null;

    return this.surface.markerDataLinkPayload(
      marker,
      marker.data_link_target || "source_watermark_event",
      marker.data_link_target_id || marker.source_watermark_event_id || marker.target_id,
      marker.timestamp_ms,
    );
  }

  renderTelemetryRevisionRange(marker: ChartMarker) {
    if (!marker.marker_id || !marker.starts_at_ms || !marker.ends_at_ms || !marker.observable_id)
      return;

    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const button = document.createElement("button");
    button.type = "button";
    button.title = this.markerInspectionTitle(marker, "telemetry revision range");
    button.setAttribute("aria-label", button.title);
    button.dataset.eventMarkerTarget = "telemetry revision";
    button.dataset.eventMarkerId = marker.target_id || marker.observable_id || "";
    button.dataset.eventMarkerRef = marker.marker_id || "";
    button.dataset.eventMarkerSummary = marker.summary || "";
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      border: "0",
      borderLeft: `1px solid ${this.surface.telemetryRevisionColor(marker)}`,
      borderRight: `1px solid ${this.surface.telemetryRevisionColor(marker)}`,
      padding: "0",
      background:
        marker.revision_state === "backfill"
          ? `${this.surface.themeColor("--chart-backfill-8")}`
          : `${this.surface.themeColor("--chart-warning-10")}`,
      cursor: "pointer",
      pointerEvents: "auto",
    });

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (marker.link_id) {
        this.surface.pushEvent(
          "open_data_link",
          this.surface.markerDataLinkPayload(
            marker,
            marker.data_link_target || marker.target,
            marker.data_link_target_id ||
              marker.target_id ||
              marker.telemetry_backfill_lifecycle_event_id ||
              marker.observable_id,
            marker.timestamp_ms || marker.starts_at_ms,
          ),
        );
        return;
      }

      this.surface.pushEvent("open_evidence", {
        kind: "frame",
        "placement-id": this.surface.model.placementId,
        "observable-id": marker.observable_id,
        "warning-code": marker.warning_code,
        "revision-state": marker.revision_state,
        "dependency-fingerprint": marker.dependency_fingerprint,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "replay-run-id": marker.replay_run_id,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "requested-dataset": marker.requested_dataset,
        "requested-validity-state": marker.requested_validity_state,
      });
    });

    this.eventLayer.appendChild(button);
  }

  renderTelemetryBackfillLifecycle(marker: ChartMarker) {
    if (marker.starts_at_ms && marker.ends_at_ms) {
      this.renderTelemetryRevisionRange(marker);
      return;
    }

    this.renderTelemetryRevisionDecision(marker);
  }

  renderTelemetryRevisionDecision(marker: ChartMarker) {
    if (!marker.marker_id || !marker.timestamp_ms || !marker.observable_id) return;

    const left = this.surface.markerLeft(marker);
    if (left === null || left === undefined || Number.isNaN(left)) return;

    const markerLabel =
      marker.marker_type === "telemetry_backfill_lifecycle"
        ? "telemetry backfill lifecycle"
        : "telemetry revision decision";

    const button = document.createElement("button");
    button.type = "button";
    button.title = this.markerInspectionTitle(marker, markerLabel);
    button.setAttribute("aria-label", button.title);
    button.dataset.eventMarkerTarget = markerLabel;
    button.dataset.eventMarkerId =
      marker.telemetry_revision_decision_event_id ||
      marker.telemetry_backfill_lifecycle_event_id ||
      marker.target_id ||
      "";
    button.dataset.eventMarkerRef = marker.marker_id || "";
    button.dataset.eventMarkerSummary = marker.summary || "";
    Object.assign(button.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      width: "14px",
      transform: "translateX(-7px)",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    });

    const line = document.createElement("span");
    Object.assign(line.style, {
      display: "block",
      width: "2px",
      height: "100%",
      margin: "0 auto",
      borderRadius: "999px",
      background: this.surface.telemetryRevisionColor(marker),
      boxShadow: `0 0 7px ${this.surface.telemetryRevisionColor(marker)}`,
    });
    button.appendChild(line);

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (marker.link_id) {
        this.surface.pushEvent(
          "open_data_link",
          this.surface.markerDataLinkPayload(
            marker,
            marker.data_link_target || marker.target,
            marker.data_link_target_id ||
              marker.target_id ||
              marker.telemetry_revision_decision_event_id ||
              marker.telemetry_backfill_lifecycle_event_id ||
              marker.observable_id,
            marker.timestamp_ms,
          ),
        );
        return;
      }

      this.surface.pushEvent("open_evidence", {
        kind: "frame",
        "placement-id": this.surface.model.placementId,
        "observable-id": marker.observable_id,
        "warning-code": marker.warning_code,
        "revision-state": marker.revision_state,
        "dependency-fingerprint": marker.dependency_fingerprint,
        "source-request-id": marker.source_request_id,
        "logical-source": marker.logical_source,
        realm: marker.realm,
        "data-source-id": marker.data_source_id,
        "source-binding-id": marker.source_binding_id,
        "time-mode": marker.time_mode,
        "time-axis": marker.time_axis,
        "replay-run-id": marker.replay_run_id,
        "requested-realm": marker.requested_realm,
        "requested-data-view": marker.requested_data_view,
        "requested-data-source-id": marker.requested_data_source_id,
        "requested-source-binding-id": marker.requested_source_binding_id,
        "requested-dataset": marker.requested_dataset,
        "requested-validity-state": marker.requested_validity_state,
      });
    });

    this.eventLayer.appendChild(button);
  }

  markerInspectionTitle(marker: ChartMarker, fallbackLabel: string) {
    const label = marker.label || fallbackLabel;
    return marker.summary ? `Inspect ${label} - ${marker.summary}` : `Inspect ${label}`;
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
