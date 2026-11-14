import type { ChartMarker } from "./chart-input.ts";
import type { ChartSurface } from "./chart-surface.ts";
/**
 * Owns event overlays. The browser snapshot (WorkspaceSnapshot) carries mission events only:
 * it deliberately excludes evidence, so the module's source-watermark, telemetry-revision,
 * backfill-lifecycle, retention-gap and source-binding renderers were removed (no producer).
 */
export class ChartEvents {
  readonly eventLayer: HTMLDivElement;
  /** Contact tints, behind the plot (attached first, so the series draws over them). */
  readonly fillLayer: HTMLDivElement;
  constructor(private readonly surface: ChartSurface) {
    this.eventLayer = this.buildEventLayer();
    this.fillLayer = this.buildFillLayer();
  }
  buildFillLayer() {
    const layer = document.createElement("div");
    layer.setAttribute("aria-hidden", "true");
    Object.assign(layer.style, {
      position: "absolute",
      inset: "0",
      bottom: `${this.surface.model.legendHeight()}px`,
      pointerEvents: "none",
      zIndex: "0",
    });
    return layer;
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
    this.fillLayer.replaceChildren();
    const contacts = this.surface.model.eventMarkers.filter(
      (m) => m.marker_type === "contact_interval",
    );
    this.renderContactBands(contacts);
    this.renderMissionEvents(
      this.surface.model.eventMarkers.filter(
        (m) => m.marker_type === "mission_event" && m.link_id && m.timestamp_ms,
      ),
    );
  }

  /**
   * Mission events: a thin line each. Events less than 6px apart (chained) merge into one line
   * with the count and span in its title, as limit entries do: a once-a-second event stream
   * otherwise packs hundreds of lines into an opaque block over the series (qa's overlay look).
   */
  renderMissionEvents(events: readonly ChartMarker[]) {
    const placed = events
      .flatMap((marker) => {
        const left = this.surface.markerLeft(marker);
        return left === null || left === undefined || Number.isNaN(left) ? [] : [{ marker, left }];
      })
      .sort((a, b) => a.left - b.left);
    for (const cluster of chained(placed, 6))
      this.renderMissionEvent(cluster.left, cluster.markers);
  }

  /**
   * Contacts behind the plot (ux Dashboards.md 'Overlays'): a realized pass is a 5% readout tint
   * with hairline edges, a booked one a dashed outline; the station code (or label) mono 11
   * top-left. Missed or partial is said in the title, never as a colour. Tints are merged per
   * overlapping run and drawn behind the series, so overlapping passes (or a booked + realized
   * pair) never stack into a heavier wash (qa's overlay look); labels go on top of every band.
   */
  renderContactBands(contacts: readonly ChartMarker[]) {
    const bands = contacts.flatMap((marker) => {
      const bounds = this.surface.intervalBounds(marker);
      return bounds ? [{ marker, ...bounds, realized: marker.kind === "realized_contact" }] : [];
    });
    const flown = mergedSpans(bands.filter((b) => b.realized));
    for (const span of flown) this.renderTint(span);
    // A booking a flown pass overlaps says nothing the pass doesn't: the flown pass's solid edges
    // win (qa: 003's pair read dashed); a booking with no pass keeps its dashed outline.
    const shown = bands.filter((b) => b.realized || !overlapsAny(b, flown));
    for (const band of shown) this.renderBandEdges(band);
    const labelled = new Set<string>();
    for (const band of shown) {
      const name = band.marker.station || band.marker.label || "Contact";
      const key = `${Math.round(band.left)}:${name}`;
      if (labelled.has(key)) continue;
      labelled.add(key);
      this.renderBandLabel(band.left, name);
    }
  }

  private bandBox(left: number, width: number) {
    return {
      position: "absolute",
      left: `${left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      width: `${width}px`,
      height: `${this.surface.chart.bbox.height || this.surface.el.clientHeight}px`,
      boxSizing: "border-box",
    };
  }

  private renderTint(span: { left: number; width: number }) {
    const tint = document.createElement("div");
    Object.assign(tint.style, {
      ...this.bandBox(span.left, span.width),
      background: `rgba(${this.surface.themeColor("--chart-color-foreground")}, 0.05)`,
    });
    this.fillLayer.appendChild(tint);
  }

  private renderBandEdges(band: {
    marker: ChartMarker;
    left: number;
    width: number;
    realized: boolean;
  }) {
    const { marker, realized } = band;
    const status = marker.status ? marker.status.replaceAll("_", " ") : null;
    const name = marker.station || marker.label || "Contact";
    const edge = document.createElement("div");
    edge.title = [realized ? "Pass" : "Booked pass", name, status].filter(Boolean).join(" · ");
    edge.setAttribute("role", "img");
    edge.setAttribute("aria-label", edge.title);
    const line = this.surface.themeColor("--chart-border-30");
    Object.assign(edge.style, {
      ...this.bandBox(band.left, band.width),
      background: "transparent",
      border: realized ? "0" : `1px dashed ${line}`,
      borderLeft: `1px ${realized ? "solid" : "dashed"} ${line}`,
      borderRight: `1px ${realized ? "solid" : "dashed"} ${line}`,
      pointerEvents: "auto",
    });
    this.eventLayer.appendChild(edge);
  }

  private renderBandLabel(left: number, name: string) {
    const label = document.createElement("span");
    label.textContent = name;
    label.setAttribute("aria-hidden", "true");
    Object.assign(label.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${this.surface.chart.bbox.top || 0}px`,
      font: this.surface.themeColor("--chart-font"),
      color: this.surface.themeColor("--chart-label-90"),
      background: this.surface.themeColor("--chart-surface-96"),
      padding: "0 4px",
      whiteSpace: "nowrap",
      pointerEvents: "none",
    });
    this.eventLayer.appendChild(label);
  }

  renderMissionEvent(left: number, markers: readonly ChartMarker[]) {
    const marker = markers[0];
    if (!marker) return;
    const button = document.createElement("button");
    button.type = "button";
    button.title =
      markers.length === 1
        ? `Inspect ${marker.title || "mission event"}`
        : `${markers.length} events ${clock(marker.timestamp_ms)}–${clock(markers.at(-1)?.timestamp_ms)}`;
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

/** Whether a span overlaps any of `spans` (touching isn't overlapping). */
export function overlapsAny(
  span: { left: number; width: number },
  spans: readonly { left: number; width: number }[],
) {
  return spans.some((s) => span.left < s.left + s.width && s.left < span.left + span.width);
}

/** Pixel spans merged where they overlap or touch: one tint per run of passes. */
export function mergedSpans(spans: readonly { left: number; width: number }[]) {
  const sorted = [...spans].sort((a, b) => a.left - b.left);
  const merged: { left: number; width: number }[] = [];
  for (const span of sorted) {
    const last = merged.at(-1);
    if (last && span.left <= last.left + last.width)
      last.width = Math.max(last.width, span.left + span.width - last.left);
    else merged.push({ left: span.left, width: span.width });
  }
  return merged;
}

/** Marks merged while each is less than `px` from the previous one (a dense run is one mark). */
export function chained(placed: readonly { marker: ChartMarker; left: number }[], px: number) {
  const clusters: { left: number; last: number; markers: ChartMarker[] }[] = [];
  for (const p of placed) {
    const run = clusters.at(-1);
    if (run && p.left - run.last < px) {
      run.markers.push(p.marker);
      run.last = p.left;
    } else clusters.push({ left: p.left, last: p.left, markers: [p.marker] });
  }
  return clusters;
}

const clock = (ms: number | null | undefined) =>
  ms ? `${new Date(ms).toISOString().slice(11, 16)}Z` : "";
