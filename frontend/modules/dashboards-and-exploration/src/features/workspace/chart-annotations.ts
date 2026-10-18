import type { ChartMarker } from "./chart-input";
type AnnotationGeometry = {
  geometry: "interval" | "point";
  left: number;
  width: number;
  top: number;
  color: string;
};
import type { ChartSurface } from "./chart-surface";

/** Owns annotation controls and their accessible evidence popovers. */
export class ChartAnnotations {
  readonly annotationLayer: HTMLDivElement;
  private activeAnnotationPopover: { control: HTMLElement; tooltip: HTMLElement } | null = null;
  constructor(private readonly surface: ChartSurface) {
    this.annotationLayer = this.buildAnnotationLayer();
  }
  buildAnnotationLayer() {
    const layer = document.createElement("div");
    layer.className = "telemetry-chart-annotations";
    layer.dataset.chartAnnotationLayer = "true";
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

  renderAnnotations() {
    if (!this.annotationLayer || !this.surface.chart) return;

    this.activeAnnotationPopover = null;
    this.annotationLayer.replaceChildren();

    this.surface.model.annotations.forEach((annotation) => {
      if (annotation.geometry === "interval") {
        this.renderIntervalAnnotation(annotation);
        return;
      }

      this.renderPointAnnotation(annotation);
    });
  }

  renderIntervalAnnotation(annotation: ChartMarker) {
    const interval = this.surface.intervalBounds(annotation);
    if (!interval) return;

    const { top: plotTop, height: plotHeight } = this.surface.chartPlotBounds();
    const color = this.annotationColor(annotation);
    const region = document.createElement("div");
    region.dataset.chartAnnotation = "interval";
    region.dataset.chartAnnotationId = annotation.annotation_id || "";
    region.dataset.chartAnnotationProvider = annotation.provider_id || "";
    region.dataset.chartAnnotationLayer = annotation.layer_id || "";
    region.setAttribute("aria-hidden", "true");
    Object.assign(region.style, {
      position: "absolute",
      left: `${interval.left}px`,
      top: `${plotTop}px`,
      width: `${interval.width}px`,
      height: `${plotHeight}px`,
      boxSizing: "border-box",
      borderLeft: `2px dashed ${color}`,
      borderRight: `2px dashed ${color}`,
      background: `color-mix(in srgb, ${color} 10%, transparent)`,
      pointerEvents: "none",
    });
    this.annotationLayer.appendChild(region);
    this.renderAnnotationControl(annotation, {
      geometry: "interval",
      left: interval.left,
      width: interval.width,
      top: plotTop + plotHeight,
      color,
    });
  }

  renderPointAnnotation(annotation: ChartMarker) {
    const left = this.annotationLeft(annotation);
    if (left === null || left === undefined || Number.isNaN(left)) return;

    const { top: plotTop, height: plotHeight } = this.surface.chartPlotBounds();
    const color = this.annotationColor(annotation);
    const line = document.createElement("div");
    line.dataset.chartAnnotation = "point";
    line.dataset.chartAnnotationId = annotation.annotation_id || "";
    line.dataset.chartAnnotationProvider = annotation.provider_id || "";
    line.dataset.chartAnnotationLayer = annotation.layer_id || "";
    line.setAttribute("aria-hidden", "true");
    Object.assign(line.style, {
      position: "absolute",
      left: `${left}px`,
      top: `${plotTop}px`,
      width: "0",
      height: `${plotHeight}px`,
      borderLeft: `2px dashed ${color}`,
      pointerEvents: "none",
    });
    this.annotationLayer.appendChild(line);
    this.renderAnnotationControl(annotation, {
      geometry: "point",
      left,
      width: 0,
      top: plotTop + plotHeight,
      color,
    });
  }

  renderAnnotationControl(
    annotation: ChartMarker,
    { geometry, left, width, top, color }: AnnotationGeometry,
  ) {
    const wrapper = document.createElement("div");
    const interval = geometry === "interval";
    const wrapperLeft = interval ? left : left - 8;
    const wrapperWidth = interval ? width : 16;
    const markerCenter = interval ? left + width / 2 : left;

    wrapper.dataset.chartAnnotationAnchor = geometry;
    wrapper.dataset.chartAnnotationId = annotation.annotation_id || "";
    wrapper.dataset.chartAnnotationProvider = annotation.provider_id || "";
    wrapper.dataset.chartAnnotationLayer = annotation.layer_id || "";
    Object.assign(wrapper.style, {
      position: "absolute",
      left: `${wrapperLeft}px`,
      top: `${top}px`,
      width: `${wrapperWidth}px`,
      height: interval ? "5px" : "10px",
      pointerEvents: "none",
      zIndex: "4",
    });

    const control = document.createElement("button");
    const tooltip = this.buildAnnotationTooltip(annotation, {
      color,
      markerCenter,
      wrapperLeft,
    });
    const tooltipId = this.annotationTooltipId(annotation);
    const label = this.annotationLabel(annotation);

    control.type = "button";
    control.title = `Inspect annotation: ${label}`;
    control.setAttribute("aria-label", control.title);
    control.setAttribute("aria-describedby", tooltipId);
    control.setAttribute("aria-expanded", "false");
    control.dataset.chartAnnotationControl = "true";
    control.dataset.chartAnnotationGeometry = geometry;
    control.dataset.chartAnnotationId = annotation.annotation_id || "";
    control.dataset.chartAnnotationProvider = annotation.provider_id || "";
    control.dataset.chartAnnotationLayer = annotation.layer_id || "";

    if (interval) {
      Object.assign(control.style, {
        position: "absolute",
        inset: "0",
        minWidth: "10px",
        height: "5px",
        border: "0",
        borderRadius: "0",
        padding: "0",
        background: color,
        cursor: "pointer",
        pointerEvents: "auto",
      });
    } else {
      Object.assign(control.style, {
        position: "absolute",
        inset: "0",
        width: "16px",
        height: "10px",
        border: "0",
        padding: "0",
        background: "transparent",
        cursor: "pointer",
        pointerEvents: "auto",
      });

      const triangle = document.createElement("span");
      triangle.dataset.chartAnnotationPointGlyph = "true";
      triangle.setAttribute("aria-hidden", "true");
      Object.assign(triangle.style, {
        position: "absolute",
        left: "3px",
        top: "0",
        width: "0",
        height: "0",
        borderLeft: "5px solid transparent",
        borderRight: "5px solid transparent",
        borderBottom: `5px solid ${color}`,
        pointerEvents: "none",
      });
      control.appendChild(triangle);
    }

    tooltip.id = tooltipId;
    tooltip.hidden = true;

    const showTooltip = () => this.setAnnotationTooltipVisible(control, tooltip, true);
    const hideTooltip = () => this.setAnnotationTooltipVisible(control, tooltip, false);

    wrapper.addEventListener("mouseenter", showTooltip);
    wrapper.addEventListener("mouseleave", hideTooltip);
    wrapper.addEventListener("focusin", showTooltip);
    wrapper.addEventListener("focusout", (event) => {
      if (!(event.relatedTarget instanceof Node) || !wrapper.contains(event.relatedTarget))
        hideTooltip();
    });
    wrapper.addEventListener("keydown", (event) => {
      if (event.key === "Escape") hideTooltip();
    });
    control.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      showTooltip();
    });

    const evidenceControl = tooltip.querySelector?.("[data-chart-annotation-open-evidence='true']");
    if (evidenceControl) {
      evidenceControl.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        hideTooltip();
        this.surface.pushEvent(
          "open_data_link",
          this.annotationDataLinkPayload(
            annotation,
            annotation.target,
            annotation.target_id,
            annotation.timestamp_ms || annotation.starts_at_ms,
          ),
        );
      });
    }

    wrapper.appendChild(control);
    wrapper.appendChild(tooltip);
    this.annotationLayer.appendChild(wrapper);
  }

  buildAnnotationTooltip(
    annotation: ChartMarker,
    {
      color,
      markerCenter,
      wrapperLeft,
    }: { color: string; markerCenter: number; wrapperLeft: number },
  ) {
    const tooltip = document.createElement("div");
    const chartWidth = this.surface.el.clientWidth || 320;
    const tooltipWidth = Math.max(160, Math.min(300, chartWidth - 16));
    const maxLeft = Math.max(8, chartWidth - tooltipWidth - 8);
    const absoluteLeft = Math.min(Math.max(markerCenter - tooltipWidth / 2, 8), maxLeft);

    tooltip.setAttribute("role", "tooltip");
    tooltip.dataset.chartAnnotationTooltip = "true";
    tooltip.dataset.chartAnnotationId = annotation.annotation_id || "";
    Object.assign(tooltip.style, {
      position: "absolute",
      left: `${absoluteLeft - wrapperLeft}px`,
      bottom: "10px",
      width: `${tooltipWidth}px`,
      border: `1px solid ${this.surface.themeColor("--chart-border-30")}`,
      borderTop: `2px solid ${color}`,
      borderRadius: "4px",
      background: `${this.surface.themeColor("--chart-panel-98")}`,
      boxShadow: `0 14px 34px ${this.surface.themeColor("--chart-shadow-38")}`,
      color: `${this.surface.themeColor("--chart-text-96")}`,
      font: "400 12px ui-sans-serif, system-ui, sans-serif",
      lineHeight: "1.4",
      pointerEvents: "auto",
      textAlign: "left",
      zIndex: "5",
    });

    const header = document.createElement("div");
    Object.assign(header.style, {
      padding: "7px 9px",
      borderBottom: `1px solid ${this.surface.themeColor("--chart-border-18")}`,
      color: `${this.surface.themeColor("--chart-text-90")}`,
      font: "500 11px ui-monospace, SFMono-Regular, Menlo, monospace",
      letterSpacing: "0.01em",
    });
    header.textContent = this.annotationTimeLabel(annotation);
    tooltip.appendChild(header);

    const body = document.createElement("div");
    Object.assign(body.style, { padding: "9px" });

    const title = document.createElement("div");
    Object.assign(title.style, {
      color: `${this.surface.themeColor("--chart-text-strong-98")}`,
      fontWeight: "650",
      marginBottom: annotation.text ? "4px" : "0",
    });
    title.textContent = this.annotationLabel(annotation);
    body.appendChild(title);

    if (annotation.text && annotation.text !== annotation.title) {
      const description = document.createElement("div");
      Object.assign(description.style, {
        color: `${this.surface.themeColor("--chart-text-secondary-86")}`,
        marginBottom: "8px",
      });
      description.textContent = annotation.text;
      body.appendChild(description);
    }

    const tags = Array.isArray(annotation.tags) ? annotation.tags.filter(Boolean) : [];
    if (tags.length > 0) {
      const tagList = document.createElement("div");
      tagList.dataset.chartAnnotationTags = "true";
      Object.assign(tagList.style, {
        display: "flex",
        flexWrap: "wrap",
        gap: "4px",
        marginBottom: "8px",
      });

      tags.forEach((tag) => {
        const tagElement = document.createElement("span");
        Object.assign(tagElement.style, {
          border: `1px solid ${this.surface.themeColor("--chart-border-24")}`,
          borderRadius: "999px",
          padding: "1px 6px",
          color: `${this.surface.themeColor("--chart-text-secondary-88")}`,
          font: "500 10px ui-monospace, SFMono-Regular, Menlo, monospace",
        });
        tagElement.textContent = String(tag);
        tagList.appendChild(tagElement);
      });
      body.appendChild(tagList);
    }

    const provenance = document.createElement("div");
    provenance.dataset.chartAnnotationProvenance = "true";
    Object.assign(provenance.style, {
      color: `${this.surface.themeColor("--chart-border-78")}`,
      font: "500 10px ui-monospace, SFMono-Regular, Menlo, monospace",
      letterSpacing: "0.035em",
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap",
    });
    provenance.textContent = [annotation.provider_id, annotation.layer_id]
      .filter(Boolean)
      .join(" / ");
    body.appendChild(provenance);

    if (annotation.link_id) {
      const footer = document.createElement("div");
      Object.assign(footer.style, {
        display: "flex",
        justifyContent: "flex-end",
        marginTop: "9px",
        paddingTop: "8px",
        borderTop: `1px solid ${this.surface.themeColor("--chart-border-14")}`,
      });

      const evidenceControl = document.createElement("button");
      evidenceControl.type = "button";
      evidenceControl.dataset.chartAnnotationOpenEvidence = "true";
      evidenceControl.textContent = "OPEN EVIDENCE";
      Object.assign(evidenceControl.style, {
        height: "24px",
        border: `1px solid ${color}`,
        borderRadius: "3px",
        padding: "0 8px",
        background: `color-mix(in srgb, ${color}12%, ${this.surface.themeColor("--chart-surface-96")})`,
        color: `${this.surface.themeColor("--chart-text-strong-96")}`,
        cursor: "pointer",
        font: "650 10px ui-monospace, SFMono-Regular, Menlo, monospace",
        letterSpacing: "0.055em",
      });
      footer.appendChild(evidenceControl);
      body.appendChild(footer);
    }

    tooltip.appendChild(body);
    return tooltip;
  }

  setAnnotationTooltipVisible(control: HTMLElement, tooltip: HTMLElement, visible: boolean) {
    const active = this.activeAnnotationPopover;

    if (visible && active && active.tooltip !== tooltip) {
      active.tooltip.hidden = true;
      active.control.setAttribute("aria-expanded", "false");
    }

    tooltip.hidden = !visible;
    control.setAttribute("aria-expanded", visible ? "true" : "false");
    this.activeAnnotationPopover = visible ? { control, tooltip } : null;
  }

  annotationTooltipId(annotation: ChartMarker) {
    const raw = [
      "chart-annotation-tooltip",
      this.surface.model.placementId || "chart",
      annotation.annotation_id || annotation.starts_at_ms || "annotation",
    ].join("-");

    return raw.replace(/[^a-zA-Z0-9_-]/g, "-");
  }

  annotationLabel(annotation: ChartMarker) {
    return annotation.title || annotation.text || annotation.layer_id || "Annotation";
  }

  annotationTimeLabel(annotation: ChartMarker) {
    const start = this.annotationTimestampLabel(annotation.timestamp_ms || annotation.starts_at_ms);

    if (annotation.geometry !== "interval") return start;

    return `${start} – ${this.annotationTimestampLabel(annotation.ends_at_ms)}`;
  }

  annotationTimestampLabel(timestampMs: number | null | undefined) {
    const value = Number(timestampMs);
    if (!Number.isFinite(value)) return "Time unavailable";

    return new Date(value).toLocaleString(undefined, {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }

  annotationDataLinkPayload(
    annotation: ChartMarker,
    target: string | null | undefined,
    targetId: string | null | undefined,
    timestampMs: number | null | undefined,
  ) {
    const metadata = annotation.metadata || {};

    return this.surface.markerDataLinkPayload(
      {
        ...annotation,
        requested_realm: metadata.realm || annotation.requested_realm || null,
        requested_data_view: metadata.data_view || annotation.requested_data_view || null,
        requested_data_source_id:
          metadata.data_source_id || annotation.requested_data_source_id || null,
        requested_source_binding_id:
          metadata.source_binding_id || annotation.requested_source_binding_id || null,
        replay_run_id: metadata.replay_run_id || annotation.replay_run_id || null,
      },
      target,
      targetId,
      timestampMs,
    );
  }

  annotationLeft(annotation: ChartMarker) {
    const timestampMs = Number(annotation.timestamp_ms || annotation.starts_at_ms);
    if (!Number.isFinite(timestampMs)) return null;

    const xDomain = this.surface.chartXDomain();
    const seconds = timestampMs / 1000;
    if (seconds < xDomain.min || seconds > xDomain.max) return null;

    return this.surface.chartPlotBounds().left + this.surface.chart.valToPos(seconds, "x", false);
  }

  annotationColor(annotation: ChartMarker) {
    const namedColors = {
      amber: `${this.surface.themeColor("--chart-warning-90")}`,
      cyan: `${this.surface.themeColor("--chart-action-90")}`,
      green: `${this.surface.themeColor("--chart-success-86")}`,
      indigo: `${this.surface.themeColor("--chart-revision-88")}`,
      red: `${this.surface.themeColor("--chart-critical-90")}`,
      teal: `${this.surface.themeColor("--chart-current-88")}`,
      violet: `${this.surface.themeColor("--chart-compare-90")}`,
    };

    if (annotation.color && Object.hasOwn(namedColors, annotation.color)) {
      const color = Object.entries(namedColors).find(([name]) => name === annotation.color)?.[1];
      if (color) return color;
    }
    if (typeof annotation.color === "string" && /^(#|rgb|hsl)/.test(annotation.color)) {
      return annotation.color;
    }
    if (annotation.severity === "critical" || annotation.severity === "error") {
      return namedColors.red;
    }
    if (annotation.severity === "warning") return namedColors.amber;
    return namedColors.indigo;
  }
}
