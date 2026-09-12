export type LiveStreamState =
  | "degraded"
  | "delayed"
  | "connecting"
  | "paused"
  | "receiving"
  | "following";
export type LiveActivity = {
  appendedPointCount: number;
  advancedLiveWindow: boolean;
  refreshIntervalMs: unknown;
  seriesPayload: unknown;
  windowEndMs: unknown;
};
import type { ChartSurface } from "./chart-surface";

/** Owns heartbeat and arrival timers plus the live status indicator. */
export class ChartLive {
  readonly liveEdge: HTMLDivElement;
  private liveEdgeLabel: HTMLSpanElement | null = null;
  private liveHeartbeatObserved = false;
  private liveHeartbeatCurrent = false;
  private liveReceivingSamples = false;
  private liveArrivalSequence = 0;
  private liveHeartbeatTimer: ReturnType<typeof setTimeout> | undefined;
  private liveArrivalTimer: ReturnType<typeof setTimeout> | undefined;
  constructor(private readonly surface: ChartSurface) {
    this.liveEdge = this.buildLiveEdge();
  }
  destroy() {
    clearTimeout(this.liveHeartbeatTimer);
    clearTimeout(this.liveArrivalTimer);
    this.liveEdge.remove();
  }
  buildLiveEdge() {
    const edge = document.createElement("div");
    edge.className = "telemetry-chart-live-edge";
    edge.dataset.liveStreamEdge = "";
    edge.setAttribute("role", "status");

    const wash = document.createElement("span");
    wash.className = "telemetry-chart-live-edge-wash";
    edge.appendChild(wash);

    const line = document.createElement("span");
    line.className = "telemetry-chart-live-edge-line";
    edge.appendChild(line);

    const beacon = document.createElement("span");
    beacon.className = "telemetry-chart-live-edge-beacon";
    edge.appendChild(beacon);

    const label = document.createElement("span");
    label.className = "telemetry-chart-live-edge-label";
    edge.appendChild(label);

    this.liveEdgeLabel = label;
    return edge;
  }

  recordLiveActivity({
    appendedPointCount,
    advancedLiveWindow,
    refreshIntervalMs,
    seriesPayload,
    windowEndMs,
  }: LiveActivity) {
    if (!this.surface.model.liveMode()) return;

    const intervalMs = Number(refreshIntervalMs);

    if (advancedLiveWindow) {
      this.liveHeartbeatObserved = true;
      this.liveHeartbeatCurrent = true;
      this.surface.el.dataset.liveHeartbeatAtMs = `${Math.round(Number(windowEndMs))}`;

      if (Number.isFinite(intervalMs) && intervalMs > 0) {
        this.surface.el.dataset.liveRefreshIntervalMs = `${Math.round(intervalMs)}`;
      }

      if (this.liveHeartbeatTimer) clearTimeout(this.liveHeartbeatTimer);
      const heartbeatTimeoutMs = Math.max(
        (Number.isFinite(intervalMs) && intervalMs > 0 ? intervalMs : 1_000) * 3,
        5_000,
      );

      this.liveHeartbeatTimer = setTimeout(() => {
        this.liveHeartbeatCurrent = false;
        this.renderLiveEdge();
      }, heartbeatTimeoutMs);
    }

    if (appendedPointCount > 0) {
      this.liveReceivingSamples = true;
      this.liveArrivalSequence += 1;
      this.surface.el.dataset.liveArrivalCount = `${appendedPointCount}`;
      this.surface.el.dataset.liveArrivalSequence = `${this.liveArrivalSequence}`;

      const latestTimestampMs = this.surface.model.seriesPayloadLatestTimestampMs(seriesPayload);
      if (latestTimestampMs !== null && Number.isFinite(latestTimestampMs)) {
        this.surface.el.dataset.liveLastSampleAtMs = `${Math.round(latestTimestampMs)}`;
      }

      this.restartLiveArrivalAnimation();
      if (this.liveArrivalTimer) clearTimeout(this.liveArrivalTimer);
      this.liveArrivalTimer = setTimeout(() => {
        this.liveReceivingSamples = false;
        if (this.liveEdge) this.liveEdge.classList.remove("is-receiving");
        this.renderLiveEdge();
      }, 720);
    }

    this.renderLiveEdge();
  }

  restartLiveArrivalAnimation() {
    if (!this.liveEdge) return;

    this.liveEdge.classList.remove("is-receiving");
    void this.liveEdge.offsetWidth;
    this.liveEdge.classList.add("is-receiving");
  }

  liveStreamState(): LiveStreamState {
    const page = this.surface.el.closest<HTMLElement>("#ops-dashboard-show-page");
    const degradedSources = Number(page && page.dataset.runtimeSourceExecutionDegraded);
    const refreshDegraded = page && page.dataset.runtimeRefreshStatus === "degraded";

    if (refreshDegraded || (Number.isFinite(degradedSources) && degradedSources > 0)) {
      return "degraded";
    }

    const delayedWatermark = (this.surface.model.eventMarkers || []).some(
      (marker) =>
        (marker.marker_type === "source_watermark_cursor" ||
          marker.marker_type === "source_watermark_event") &&
        (marker.display_mode !== "status" ||
          marker.freshness_state === "stale" ||
          marker.freshness_state === "retention_gap"),
    );

    if (this.surface.el.dataset.watermarkBoundaryVisible === "true" || delayedWatermark) {
      return "delayed";
    }

    if (!this.liveHeartbeatObserved) return "connecting";
    if (!this.liveHeartbeatCurrent) return "paused";
    if (this.liveReceivingSamples) return "receiving";
    return "following";
  }

  renderLiveEdge() {
    if (!this.liveEdge) return;

    if (!this.surface.model.liveMode()) {
      this.liveEdge.hidden = true;
      delete this.surface.el.dataset.liveStreamState;
      this.publishDashboardLiveState();
      return;
    }

    const bbox = this.surface.chart && this.surface.chart.bbox;
    if (!bbox) return;

    const state = this.liveStreamState();
    const plotRight = (bbox.left || 0) + (bbox.width || this.surface.el.clientWidth);
    const edgeWidth = 64;

    this.liveEdge.hidden = false;
    this.liveEdge.dataset.liveStreamState = state;
    this.surface.el.dataset.liveStreamState = state;
    Object.assign(this.liveEdge.style, {
      left: `${Math.max(0, plotRight - edgeWidth)}px`,
      top: `${bbox.top || 0}px`,
      width: `${edgeWidth}px`,
      height: `${bbox.height || this.surface.el.clientHeight}px`,
    });

    const label = this.liveStreamLabel(state);
    const description = this.liveStreamDescription(state);
    if (this.liveEdgeLabel) this.liveEdgeLabel.textContent = label;
    this.liveEdge.title = description;
    this.liveEdge.setAttribute("aria-label", description);
    this.publishDashboardLiveState();
  }

  liveStreamLabel(state: LiveStreamState) {
    if (state === "connecting") return "SYNC";
    if (state === "paused") return "PAUSED";
    if (state === "delayed") return "DELAYED";
    if (state === "degraded") return "DEGRADED";
    return "LIVE";
  }

  liveStreamDescription(state: LiveStreamState) {
    if (state === "connecting") return "Connecting the live telemetry window";
    if (state === "paused") return "Live telemetry heartbeat has paused";
    if (state === "delayed") return "Live telemetry is following a delayed source watermark";
    if (state === "degraded") return "Live telemetry source execution is degraded";

    if (state === "receiving") {
      const count = Number(this.surface.el.dataset.liveArrivalCount) || 0;
      return `Live telemetry received ${count} new ${count === 1 ? "sample" : "samples"}`;
    }

    return "Live telemetry window is current";
  }

  publishDashboardLiveState() {
    const page = this.surface.el.closest<HTMLElement>("#ops-dashboard-show-page");
    if (!page || !page.querySelectorAll) return;

    const charts = Array.from(
      page.querySelectorAll<HTMLElement>("[data-telemetry-chart][data-time-mode='live']"),
    );

    if (charts.length === 0) {
      delete page.dataset.dashboardLiveStreamState;
      delete page.dataset.dashboardLiveStreamChartCount;
      return;
    }

    const states = charts.map((chart) => chart.dataset.liveStreamState || "connecting");
    const priority = ["degraded", "paused", "delayed", "connecting", "receiving", "following"];
    const state = priority.find((candidate) => states.includes(candidate)) || "connecting";

    page.dataset.dashboardLiveStreamState = state;
    page.dataset.dashboardLiveStreamChartCount = `${charts.length}`;

    const timeRange = page.querySelector<HTMLElement>("#dashboard-active-time-range");
    if (timeRange) timeRange.dataset.liveStreamState = state;
  }
}
