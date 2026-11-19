import type {
  ContactMarker,
  EventMarker,
  MissionEventMarker,
  NotStartedReason,
} from "./chart-markers.ts";
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
    if (this.surface.model.xs.length === 0) this.renderEmptyHatch();
    const markers = this.surface.model.eventMarkers;
    this.renderContactBands(markers.filter(isContact));
    this.renderMissionEvents(markers.filter(isMissionEvent));
  }

  /**
   * Mission events: a thin line each. Events less than 6px apart (chained) merge into one line
   * with the count and span in its title, as limit entries do: a once-a-second event stream
   * otherwise packs hundreds of lines into an opaque block over the series (qa's overlay look).
   */
  renderMissionEvents(events: readonly MissionEventMarker[]) {
    const placed = events
      .flatMap((marker) => {
        const left = this.surface.markerLeft(marker.timestamp_ms);
        return Number.isNaN(left) ? [] : [{ marker, left }];
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
  renderContactBands(contacts: readonly ContactMarker[]) {
    const bands = contacts.flatMap((marker) => {
      const bounds = this.surface.intervalBounds(marker);
      return bounds ? [{ marker, ...bounds, realized: flew(marker) }] : [];
    });
    const flown = mergedSpans(bands.filter((b) => b.realized));
    // Over the empty-range hatch, a band's own area knocks the hatch out, so its dashed or solid
    // edges read against plain surface, not against stripes of the same weight (qa: ZKgUX).
    if (this.surface.model.xs.length === 0)
      for (const span of mergedSpans(bands)) this.renderKnockout(span);
    for (const span of flown) this.renderTint(span);
    // A contact that closed without starting is drawn as its booking (dashed, at the scheduled
    // window) and replaces the booking's own outline there: one outline, one tooltip (ux).
    const notStarted = bands.filter((b) => b.marker.started === false);
    const covers = mergedSpans([...flown, ...notStarted]);
    // ux 88b7e6ae7: where a flown pass covers its booking, only the pass's solid edges; where the
    // booking reaches past it (a late start, an early LOS), the dashed outline on that part only;
    // a booking with no pass stays dashed.
    const shown = bands.flatMap((band) =>
      band.realized
        ? [{ ...band, open: { left: true, right: true } }]
        : band.marker.started === false
          ? [{ ...band, open: { left: true, right: true } }]
          : uncovered(band, covers).map((part) => ({ ...band, ...part })),
    );
    for (const band of shown) this.renderBandEdges(band);
    const labelled = new Set<string>();
    for (const band of shown) {
      if (!band.open.left) continue; // a part after a flown pass: the pass is already labelled
      const name = band.marker.station || band.marker.label || "Contact";
      const key = `${Math.round(band.left)}:${name}`;
      if (labelled.has(key)) continue;
      labelled.add(key);
      this.renderBandLabel(band.left, name);
    }
  }

  /** No samples in range (ux, Overlays): the stale hatch across the plot, under bands and marks. */
  private renderEmptyHatch() {
    const plot = this.surface.chartPlotBounds();
    const hatch = document.createElement("div");
    Object.assign(hatch.style, {
      ...this.bandBox(plot.left, plot.width),
      backgroundImage: "var(--apogee-hatch-stale-cell)",
    });
    this.fillLayer.appendChild(hatch);
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

  private renderKnockout(span: { left: number; width: number }) {
    const plain = document.createElement("div");
    Object.assign(plain.style, {
      ...this.bandBox(span.left, span.width),
      background: this.surface.themeColor("--chart-surface-96"),
    });
    this.fillLayer.appendChild(plain);
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
    marker: ContactMarker;
    left: number;
    width: number;
    realized: boolean;
    /** Whether each side is the contact's own start or end (a cut side borders a flown pass). */
    open: { left: boolean; right: boolean };
  }) {
    const { marker, realized } = band;
    const edge = document.createElement("div");
    edge.title = contactTitle(marker, realized);
    edge.setAttribute("role", "img");
    edge.setAttribute("aria-label", edge.title);
    const line = this.surface.themeColor("--chart-border-30");
    Object.assign(edge.style, {
      ...this.bandBox(band.left, band.width),
      background: "transparent",
      border: realized ? "0" : `1px dashed ${line}`,
      borderLeft: band.open.left ? `1px ${realized ? "solid" : "dashed"} ${line}` : "0",
      borderRight: band.open.right ? `1px ${realized ? "solid" : "dashed"} ${line}` : "0",
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

  renderMissionEvent(left: number, markers: readonly MissionEventMarker[]) {
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
    button.dataset.eventMarkerRef = marker.link_id;
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
          marker.link_id,
          "mission_event",
          null,
          marker.timestamp_ms,
        ),
      );
    });

    this.eventLayer.appendChild(button);
  }
}

/**
 * The parts of `span` no span in `covers` (sorted, merged) covers, each saying whether its sides
 * are the span's own ends. A booking fully under a flown pass leaves nothing.
 */
export function uncovered(
  span: { left: number; width: number },
  covers: readonly { left: number; width: number }[],
) {
  const end = span.left + span.width;
  const parts: { left: number; width: number; open: { left: boolean; right: boolean } }[] = [];
  let at = span.left;
  for (const c of covers) {
    const cEnd = c.left + c.width;
    if (cEnd <= at || c.left >= end) continue;
    if (c.left > at) parts.push(part(at, c.left, span.left, end));
    at = Math.max(at, cEnd);
  }
  if (at < end) parts.push(part(at, end, span.left, end));
  return parts;
}
const part = (from: number, to: number, start: number, end: number) => ({
  left: from,
  width: to - from,
  open: { left: from === start, right: to === end },
});

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
export function chained<M>(placed: readonly { marker: M; left: number }[], px: number) {
  const clusters: { left: number; last: number; markers: M[] }[] = [];
  for (const p of placed) {
    const run = clusters.at(-1);
    if (run && p.left - run.last < px) {
      run.markers.push(p.marker);
      run.last = p.left;
    } else clusters.push({ left: p.left, last: p.left, markers: [p.marker] });
  }
  return clusters;
}

const clock = (ms: number | undefined) =>
  ms ? `${new Date(ms).toISOString().slice(11, 16)}Z` : "";

const isContact = (m: EventMarker): m is ContactMarker => m.marker_type === "contact_interval";
const isMissionEvent = (m: EventMarker): m is MissionEventMarker =>
  m.marker_type === "mission_event";

/** A realized contact that started; one that closed without starting draws as its booking. */
const flew = (m: ContactMarker) => m.kind === "realized_contact" && m.started !== false;

const NOT_STARTED: Readonly<Record<NotStartedReason, string>> = {
  window_ended: "pass · didn't start: its window ended first",
  hand_start_expired: "contact · didn't start: the hand start expired",
  unrecognized: "pass · didn't start",
};

/** A band's tooltip (ux Dashboards.md › Overlays; U45's words for a contact that didn't start). */
export function contactTitle(marker: ContactMarker, flown: boolean): string {
  const name = marker.station || marker.label || "Contact";
  if (marker.started === false)
    return `${name} ${NOT_STARTED[marker.close_reason ?? "unrecognized"]}`;
  const status = marker.status ? marker.status.replaceAll("_", " ") : null;
  return [flown ? "Pass" : "Booked pass", name, status].filter(Boolean).join(" · ");
}
