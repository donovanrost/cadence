import type { ChartMarker } from "./chart-input.ts";
import type { ChartSurface } from "./chart-surface.ts";
/**
 * Owns event overlays. The browser snapshot (WorkspaceSnapshot) carries mission events only:
 * it deliberately excludes evidence, so the module's source-watermark, telemetry-revision,
 * backfill-lifecycle, retention-gap and source-binding renderers were removed (no producer).
 */
export class ChartEvents {
  readonly eventLayer: HTMLDivElement;
  constructor(private readonly surface: ChartSurface) {
    this.eventLayer = this.buildEventLayer();
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

  renderEventMarkers() {
    if (!this.eventLayer || !this.surface.chart) return;
    this.eventLayer.replaceChildren();
    for (const marker of this.surface.model.eventMarkers)
      if (marker.marker_type === "mission_event") this.renderMissionEvent(marker);
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
