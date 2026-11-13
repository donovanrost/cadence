import type { ChartMarker } from "./chart-input.ts";
import type { ChartSurface } from "./chart-surface.ts";

/** Telemetry revision ranges, backfill lifecycle and revision decisions (split from ChartEvents). */
export class ChartRevisions {
  constructor(
    private readonly surface: ChartSurface,
    private readonly layer: HTMLDivElement,
  ) {}
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

    this.layer.appendChild(button);
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

    this.layer.appendChild(button);
  }

  markerInspectionTitle(marker: ChartMarker, fallbackLabel: string) {
    const label = marker.label || fallbackLabel;
    return marker.summary ? `Inspect ${label} - ${marker.summary}` : `Inspect ${label}`;
  }
}
