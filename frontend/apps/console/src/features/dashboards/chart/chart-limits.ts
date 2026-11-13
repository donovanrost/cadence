import type { ChartMarker } from "./chart-input.ts";
type ThresholdBand = { name: string; from: number | null; to: number | null };
import type { ChartSurface } from "./chart-surface.ts";

/** Owns limit events, analysis buckets and threshold overlays. */
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
    const entries: ChartMarker[] = [];
    this.surface.model.limitMarkers.forEach((marker) => {
      if (marker.marker_type === "limit_definition_interval")
        this.renderLimitDefinitionInterval(marker);
      else if (marker.marker_type === "limit_analysis_bucket")
        this.renderLimitAnalysisBucket(marker);
      else entries.push(marker);
    });
    this.renderLimitEntries(entries);
  }

  /**
   * Limit entries (ux Dashboards.md 'Overlays'): a mark where the series enters a red (crit
   * diamond) or yellow (caution triangle) state, along the plot's top edge. Marks closer than
   * 6px merge into one, worst state first, with the count and span in its title.
   */
  renderLimitEntries(entries: readonly ChartMarker[]) {
    const placed = entries
      .flatMap((marker) => {
        const left = this.surface.markerLeft(marker);
        return left === null || left === undefined || Number.isNaN(left) ? [] : [{ marker, left }];
      })
      .sort((a, b) => a.left - b.left);
    const clusters: { left: number; markers: ChartMarker[] }[] = [];
    for (const p of placed) {
      const last = clusters.at(-1);
      if (last && p.left - last.left < 6) last.markers.push(p.marker);
      else clusters.push({ left: p.left, markers: [p.marker] });
    }
    for (const cluster of clusters) this.renderLimitEntry(cluster.left, cluster.markers);
  }

  renderLimitAnalysisBucket(marker: ChartMarker) {
    if (!marker.starts_at_ms || !marker.ends_at_ms) return;

    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const button = document.createElement("button");
    button.type = "button";
    button.title = this.limitAnalysisBucketTitle(marker);
    button.setAttribute("aria-label", button.title);
    button.dataset.limitMarkerTarget = "limit analysis bucket";
    button.dataset.limitMarkerId =
      marker.limit_event_id || marker.sample_id || marker.marker_id || "";
    button.dataset.limitMarkerRef = marker.link_id || marker.marker_id || "";
    button.dataset.limitBucketState = marker.normalized_state || "";
    button.dataset.limitBucketEventCount = String(marker.event_count || "");
    button.dataset.limitBucketDivergenceCount = String(marker.limit_divergence_count || "");
    button.dataset.limitDefinitionId = marker.limit_definition_id || "";
    button.dataset.limitDefinitionVersion = String(marker.limit_definition_version || "");
    button.dataset.limitSetName = marker.limit_set_name || "";
    button.dataset.limitSelectedClock = this.limitMarkerMetadata(marker.selected_limit_clock);
    button.dataset.limitSelectedDefinitionIntervals = this.limitMarkerMetadata(
      marker.selected_limit_definition_intervals,
    );
    Object.assign(button.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${interval.width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      border: "0",
      borderLeft: `1px solid ${this.surface.markerColor(marker)}`,
      borderRight: `1px solid ${this.surface.markerColor(marker)}`,
      padding: "0",
      background: this.limitAnalysisBucketFill(marker),
      outline: `1px solid ${this.limitAnalysisBucketEdge(marker)}`,
      outlineOffset: "-1px",
      cursor: marker.link_id ? "pointer" : "default",
      pointerEvents: marker.link_id ? "auto" : "none",
    });

    if (marker.limit_divergence_count) {
      button.dataset.limitBucketDiverged = "true";
    }

    button.addEventListener("click", (event) => {
      if (!marker.link_id) return;

      event.preventDefault();
      event.stopPropagation();
      const target = marker.synthetic_limit_analysis ? "telemetry_sample" : "limit_event";
      const targetId =
        target === "telemetry_sample"
          ? marker.sample_id
          : marker.limit_event_id || marker.sample_id;
      this.surface.pushEvent(
        "open_data_link",
        this.surface.markerDataLinkPayload(marker, target, targetId, marker.timestamp_ms),
      );
    });

    this.markerLayer.appendChild(button);
  }

  renderLimitEntry(left: number, markers: readonly ChartMarker[]) {
    const first = markers[0];
    if (!first) return;
    const crit = markers.some((m) => m.limit_state === "red");
    const at = (m: ChartMarker | undefined) =>
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
    button.dataset.limitMarkerId = first.limit_event_id || "";
    button.dataset.limitMarkerRef = first.link_id || "";
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
          first,
          "limit_event",
          first.limit_event_id,
          first.timestamp_ms,
        ),
      );
    });
    this.markerLayer.appendChild(button);
  }

  renderLimitDefinitionInterval(marker: ChartMarker) {
    if (!marker.link_id || !marker.starts_at_ms) return;

    const interval = this.surface.intervalBounds(marker);
    if (!interval) return;

    const button = document.createElement("button");
    button.type = "button";
    // A definition that starts inside the window is a change (ux): a 1px tick and its time.
    const changed = interval.left > 0.5;
    button.title = changed
      ? `Limits changed ${marker.starts_at_ms ? new Date(marker.starts_at_ms).toISOString().slice(11, 16) : ""}Z`
      : `${marker.limit_set_name || "Active"} limits`;
    button.setAttribute("aria-label", button.title);
    button.dataset.limitMarkerTarget = "limit definition";
    button.dataset.limitMarkerId = marker.limit_definition_id || marker.target_id || "";
    button.dataset.limitMarkerRef = marker.link_id || "";
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
          marker,
          "limit_definition",
          marker.target_id || marker.limit_definition_id,
          marker.starts_at_ms,
        ),
      );
    });

    this.markerLayer.appendChild(button);
  }

  renderThresholdLines(parent: HTMLElement, marker: ChartMarker) {
    const thresholdNames = ["red_high", "yellow_high", "yellow_low", "red_low"] as const;

    thresholdNames.forEach((name) => {
      const value = Number(marker[name]);
      if (!Number.isFinite(value)) return;

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

  renderThresholdBands(parent: HTMLElement, marker: ChartMarker) {
    // Only beyond red gets a wash (ux: crit wash, no caution wash).
    this.thresholdBandSpecs(marker)
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

  thresholdBandSpecs(marker: ChartMarker) {
    return [
      { name: "red_high", from: this.numberOrNull(marker.red_high), to: null },
      {
        name: "yellow_high",
        from: this.numberOrNull(marker.yellow_high),
        to: this.numberOrNull(marker.red_high),
      },
      {
        name: "yellow_low",
        from: this.numberOrNull(marker.red_low),
        to: this.numberOrNull(marker.yellow_low),
      },
      { name: "red_low", from: null, to: this.numberOrNull(marker.red_low) },
    ].filter((band) => band.from !== null || band.to !== null);
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

  numberOrNull(value: unknown) {
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  }

  limitAnalysisBucketTitle(marker: ChartMarker) {
    const state = marker.normalized_state || "limit";
    const count = marker.event_count
      ? ` / ${marker.event_count} event${marker.event_count === 1 ? "" : "s"}`
      : "";
    const divergence = marker.limit_divergence_count
      ? ` / ${marker.limit_divergence_count} divergent`
      : "";
    return `Inspect ${state} limit analysis bucket${count}${divergence}`;
  }

  limitMarkerMetadata(value: unknown) {
    if (value === null || value === undefined || value === "") return "";
    if (typeof value === "string") return value;

    try {
      return JSON.stringify(value);
    } catch {
      return "";
    }
  }

  limitAnalysisBucketFill(marker: ChartMarker) {
    if (marker.normalized_state === "red")
      return `${this.surface.themeColor("--chart-critical-14")}`;
    return `${this.surface.themeColor("--chart-caution-12")}`;
  }

  limitAnalysisBucketEdge(marker: ChartMarker) {
    if (marker.normalized_state === "red")
      return `${this.surface.themeColor("--chart-critical-28")}`;
    return `${this.surface.themeColor("--chart-caution-24")}`;
  }

  limitThresholdColor(name: string) {
    if (name.startsWith("red")) return `${this.surface.themeColor("--chart-critical-82")}`;
    return `${this.surface.themeColor("--chart-caution-82")}`;
  }

  limitThresholdBandColor(name: string) {
    if (name.startsWith("red")) return this.surface.themeColor("--apogee-wash-crit");
    return "transparent";
  }
}
