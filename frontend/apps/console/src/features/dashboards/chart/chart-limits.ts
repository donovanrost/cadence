import type { LimitDefinitionMarker, LimitEventMarker } from "./chart-markers.ts";
import type { ChartSurface } from "./chart-surface.ts";

type ThresholdName = "red_high" | "yellow_high" | "yellow_low" | "red_low";
type ThresholdBand = { name: ThresholdName; from: number | null; to: number | null };

/** Owns limit entries, definition intervals and their threshold overlays. */
export class ChartLimits {
  readonly markerLayer: HTMLDivElement;
  constructor(private readonly surface: ChartSurface) {
    this.markerLayer = this.buildMarkerLayer();
  }
  buildMarkerLayer() {
    const layer = document.createElement("div");
    layer.className = "telemetry-chart-limit-markers";
    layer.setAttribute("aria-hidden", "false");
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      bottom: `${this.surface.model.legendHeight()}px`,
      pointerEvents: "none",
      zIndex: "3",
    });
    return layer;
  }

  renderLimitMarkers() {
    if (!this.markerLayer || !this.surface.chart) return;

    this.markerLayer.replaceChildren();
    const entries: LimitEventMarker[] = [];
    for (const marker of this.surface.model.limitMarkers) {
      switch (marker.marker_type) {
        case "limit_definition_interval":
          this.renderLimitDefinitionInterval(marker);
          break;
        case "limit_event":
          entries.push(marker);
          break;
      }
    }
    this.renderLimitEntries(entries);
  }

  /**
   * Limit entries (ux Dashboards.md 'Overlays'): a mark where the series enters a red (crit
   * diamond) or yellow (caution triangle) state, along the plot's top edge. Marks closer than
   * 6px merge into one, worst state first, with the count and span in its title.
   */
  renderLimitEntries(entries: readonly LimitEventMarker[]) {
    const placed = entries
      .flatMap((marker) => {
        const left = this.surface.markerLeft(marker.timestamp_ms);
        return Number.isNaN(left) ? [] : [{ marker, left }];
      })
      .sort((a, b) => a.left - b.left);
    const clusters: { left: number; markers: LimitEventMarker[] }[] = [];
    for (const p of placed) {
      const last = clusters.at(-1);
      if (last && p.left - last.left < 6) last.markers.push(p.marker);
      else clusters.push({ left: p.left, markers: [p.marker] });
    }
    for (const cluster of clusters) this.renderLimitEntry(cluster.left, cluster.markers);
  }

  renderLimitEntry(left: number, markers: readonly LimitEventMarker[]) {
    const first = markers[0];
    if (!first) return;
    const crit = markers.some((m) => m.limit_state === "red");
    const at = (m: LimitEventMarker | undefined) =>
      m?.timestamp_ms ? `${new Date(m.timestamp_ms).toISOString().slice(11, 16)}Z` : "";
    const word = crit ? "crit" : "caution";
    const button = document.createElement("button");
    button.type = "button";
    button.title =
      markers.length === 1
        ? `${crit ? "Red" : "Yellow"} limit entered ${at(first)}`
        : `${markers.length} ${word} entries ${at(first)}–${at(markers.at(-1))}`;
    button.setAttribute("aria-label", button.title);
    button.dataset.limitMarkerTarget = "limit event";
    button.dataset.limitMarkerId = first.limit_event_id ?? "";
    button.dataset.limitMarkerRef = first.link_id;
    Object.assign(button.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${(this.surface.chart.bbox.top || 0) + 2}px`,
      width: "14px",
      height: "14px",
      transform: "translateX(-7px)",
      display: "grid",
      placeItems: "center",
      border: "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    });
    // The status grammar's shapes (ApStatusMark): crit diamond, caution triangle; never colour only.
    const mark = document.createElement("span");
    Object.assign(
      mark.style,
      crit
        ? {
            width: "8px",
            height: "8px",
            background: this.surface.themeColor("--chart-critical-95"),
            transform: "rotate(45deg)",
          }
        : {
            width: "10px",
            height: "9px",
            background: this.surface.themeColor("--chart-caution-95"),
            clipPath: "polygon(50% 0, 100% 100%, 0 100%)",
          },
    );
    button.appendChild(mark);
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.surface.pushEvent(
        "open_data_link",
        this.surface.markerDataLinkPayload(
          first.link_id,
          "limit_event",
          first.limit_event_id,
          first.timestamp_ms,
        ),
      );
    });
    this.markerLayer.appendChild(button);
  }

  renderLimitDefinitionInterval(marker: LimitDefinitionMarker) {
    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const button = document.createElement("button");
    button.type = "button";
    // A definition that starts inside the window is a change (ux): a 1px tick and its time.
    const changed = interval.left > 0.5;
    button.title = changed
      ? `Limits changed ${new Date(marker.starts_at_ms).toISOString().slice(11, 16)}Z`
      : `${marker.limit_set_name ?? "Active"} limits`;
    button.setAttribute("aria-label", button.title);
    button.dataset.limitMarkerTarget = "limit definition";
    button.dataset.limitMarkerId = marker.limit_definition_id ?? "";
    button.dataset.limitMarkerRef = marker.link_id;
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      border: "0",
      borderLeft: changed ? `1px solid ${this.surface.themeColor("--chart-muted-62")}` : "0",
      padding: "0",
      background: "transparent",
      cursor: "pointer",
      pointerEvents: "auto",
    });

    this.renderThresholdBands(button, marker);
    this.renderThresholdLines(button, marker);

    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.surface.pushEvent(
        "open_data_link",
        this.surface.markerDataLinkPayload(
          marker.link_id,
          "limit_definition",
          marker.limit_definition_id,
          marker.starts_at_ms,
        ),
      );
    });

    this.markerLayer.appendChild(button);
  }

  renderThresholdLines(parent: HTMLElement, marker: LimitDefinitionMarker) {
    const thresholdNames = ["red_high", "yellow_high", "yellow_low", "red_low"] as const;

    thresholdNames.forEach((name) => {
      // An unset threshold draws nothing (it used to read as a line at 0).
      const value = marker[name];
      if (value === null) return;

      const top = this.surface.chart.valToPos(value, "y", false);
      const height = this.surface.chart.bbox.height || this.surface.el.clientHeight;
      if (top < 0 || top > height) return;

      const line = document.createElement("span");
      Object.assign(line.style, {
        position: "absolute",
        left: "0",
        right: "0",
        top: `${top}px`,
        borderTop: `1px dashed ${this.limitThresholdColor(name)}`,
      });
      parent.appendChild(line);
    });
  }

  renderThresholdBands(parent: HTMLElement, marker: LimitDefinitionMarker) {
    // Only beyond red gets a wash (ux: crit wash, no caution wash).
    thresholdBands(marker)
      .filter((band) => band.name.startsWith("red"))
      .forEach((band) => {
        const bounds = this.thresholdBandBounds(band);
        if (!bounds) return;

        const fill = document.createElement("span");
        fill.dataset.limitThresholdBand = band.name;
        Object.assign(fill.style, {
          position: "absolute",
          left: "0",
          right: "0",
          top: `${bounds.top}px`,
          height: `${bounds.height}px`,
          background: this.limitThresholdBandColor(band.name),
          pointerEvents: "none",
        });
        parent.appendChild(fill);
      });
  }

  thresholdBandBounds(band: ThresholdBand) {
    const plotTop = this.surface.chart.bbox.top || 0;
    const plotHeight = this.surface.chart.bbox.height || this.surface.el.clientHeight;
    const plotBottom = plotTop + plotHeight;
    const top =
      band.to === null ? plotTop : plotTop + this.surface.chart.valToPos(band.to, "y", false);
    const bottom =
      band.from === null
        ? plotBottom
        : plotTop + this.surface.chart.valToPos(band.from, "y", false);
    const clippedTop = Math.max(plotTop, Math.min(plotBottom, top));
    const clippedBottom = Math.max(plotTop, Math.min(plotBottom, bottom));
    const height = clippedBottom - clippedTop;

    if (!Number.isFinite(height) || height <= 1) return null;
    return { top: clippedTop - plotTop, height };
  }

  limitThresholdColor(name: ThresholdName) {
    if (name.startsWith("red")) return `${this.surface.themeColor("--chart-critical-82")}`;
    return `${this.surface.themeColor("--chart-caution-82")}`;
  }

  limitThresholdBandColor(name: ThresholdName) {
    if (name.startsWith("red")) return this.surface.themeColor("--apogee-wash-crit");
    return "transparent";
  }
}

/** The wash bands a definition's thresholds bound, from the top down; unset thresholds bound none. */
export function thresholdBands(marker: LimitDefinitionMarker): ThresholdBand[] {
  const bands: ThresholdBand[] = [
    { name: "red_high", from: marker.red_high, to: null },
    { name: "yellow_high", from: marker.yellow_high, to: marker.red_high },
    { name: "yellow_low", from: marker.red_low, to: marker.yellow_low },
    { name: "red_low", from: null, to: marker.red_low },
  ];
  return bands.filter((band) => band.from !== null || band.to !== null);
}
