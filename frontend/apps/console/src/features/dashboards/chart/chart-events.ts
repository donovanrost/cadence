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
    for (const marker of this.surface.model.eventMarkers) {
      if (marker.marker_type === "contact_interval") this.renderContactInterval(marker);
      else if (marker.marker_type === "mission_event") this.renderMissionEvent(marker);
    }
  }

  /**
   * A contact behind the plot (ux Dashboards.md 'Overlays'): raised fill, the station code (or
   * the contact's label) mono 11 top-left. Booked = dashed outline; realized = filled. Missed or
   * partial is said in the title, never as a colour.
   */
  renderContactInterval(marker: ChartMarker) {
    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;
    const realized = marker.kind === "realized_contact";
    const status = marker.status ? marker.status.replaceAll("_", " ") : null;
    const name = marker.station || marker.label || "Contact";
    const band = document.createElement("div");
    band.title = [realized ? "Pass" : "Booked pass", name, status].filter(Boolean).join(" · ");
    band.setAttribute("role", "img");
    band.setAttribute("aria-label", band.title);
    Object.assign(band.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      boxSizing: "border-box",
      // As ApTimeSeries' pass band: a 5% readout tint with hairline edges (the plot shows through).
      background: realized
        ? `rgba(${this.surface.themeColor("--chart-color-foreground")}, 0.05)`
        : "transparent",
      border: realized ? "0" : `1px dashed ${this.surface.themeColor("--chart-border-30")}`,
      borderLeft: `1px ${realized ? "solid" : "dashed"} ${this.surface.themeColor("--chart-border-30")}`,
      borderRight: `1px ${realized ? "solid" : "dashed"} ${this.surface.themeColor("--chart-border-30")}`,
      pointerEvents: "auto",
      zIndex: "0",
    });
    const label = document.createElement("span");
    label.textContent = name;
    Object.assign(label.style, {
      position: "absolute",
      top: "0",
      left: "0",
      font: this.surface.themeColor("--chart-font"),
      color: this.surface.themeColor("--chart-label-90"),
      background: this.surface.themeColor("--chart-surface-96"),
      padding: "0 4px",
      whiteSpace: "nowrap",
      pointerEvents: "none",
    });
    band.appendChild(label);
    this.eventLayer.appendChild(band);
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
      // ux: a thin text-4 line, no glow; the event's words are in the title.
      background: this.surface.themeColor("--chart-muted-62"),
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
