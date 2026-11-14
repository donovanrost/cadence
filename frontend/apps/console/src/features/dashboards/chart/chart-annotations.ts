import type { ChartAnnotation } from "./chart-markers.ts";
import type { ChartSurface } from "./chart-surface.ts";
import { ChartAnnotationTooltip, type AnnotationGeometry } from "./chart-annotation-tooltip.ts";

/** Owns annotation controls and their accessible evidence popovers. */
export class ChartAnnotations {
  readonly annotationLayer: HTMLDivElement;
  private activeAnnotationPopover: { control: HTMLElement; tooltip: HTMLElement } | null = null;
  private readonly tooltips: ChartAnnotationTooltip;
  constructor(private readonly surface: ChartSurface) {
    this.annotationLayer = this.buildAnnotationLayer();
    this.tooltips = new ChartAnnotationTooltip(surface);
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

  renderIntervalAnnotation(annotation: ChartAnnotation) {
    const interval = this.surface.intervalBounds(annotation);
    if (!interval) return;

    const { top: plotTop, height: plotHeight } = this.surface.chartPlotBounds();
    const color = this.annotationColor(annotation);
    const region = document.createElement("div");
    region.dataset.chartAnnotation = "interval";
    region.dataset.chartAnnotationId = annotation.annotation_id;
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

  renderPointAnnotation(annotation: ChartAnnotation) {
    const left = this.annotationLeft(annotation);
    if (left === null || left === undefined || Number.isNaN(left)) return;

    const { top: plotTop, height: plotHeight } = this.surface.chartPlotBounds();
    const color = this.annotationColor(annotation);
    const line = document.createElement("div");
    line.dataset.chartAnnotation = "point";
    line.dataset.chartAnnotationId = annotation.annotation_id;
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
    annotation: ChartAnnotation,
    { geometry, left, width, top, color }: AnnotationGeometry,
  ) {
    const wrapper = document.createElement("div");
    const interval = geometry === "interval";
    const wrapperLeft = interval ? left : left - 8;
    const wrapperWidth = interval ? width : 16;
    const markerCenter = interval ? left + width / 2 : left;

    wrapper.dataset.chartAnnotationAnchor = geometry;
    wrapper.dataset.chartAnnotationId = annotation.annotation_id;
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
    const tooltip = this.tooltips.buildAnnotationTooltip(annotation, {
      color,
      markerCenter,
      wrapperLeft,
    });
    const tooltipId = this.annotationTooltipId(annotation);
    const label = this.tooltips.annotationLabel(annotation);

    control.type = "button";
    control.title = `Inspect annotation: ${label}`;
    control.setAttribute("aria-label", control.title);
    control.setAttribute("aria-describedby", tooltipId);
    control.setAttribute("aria-expanded", "false");
    control.dataset.chartAnnotationControl = "true";
    control.dataset.chartAnnotationGeometry = geometry;
    control.dataset.chartAnnotationId = annotation.annotation_id;

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

    wrapper.appendChild(control);
    wrapper.appendChild(tooltip);
    this.annotationLayer.appendChild(wrapper);
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

  annotationTooltipId(annotation: ChartAnnotation) {
    const raw = [
      "chart-annotation-tooltip",
      this.surface.model.placementId || "chart",
      annotation.annotation_id,
    ].join("-");

    return raw.replace(/[^a-zA-Z0-9_-]/g, "-");
  }

  annotationLeft(annotation: ChartAnnotation) {
    const xDomain = this.surface.chartXDomain();
    const seconds = annotation.starts_at_ms / 1000;
    if (seconds < xDomain.min || seconds > xDomain.max) return null;

    return this.surface.chartPlotBounds().left + this.surface.chart.valToPos(seconds, "x", false);
  }

  /** Severity sets the colour (annotations carry no colour of their own). */
  annotationColor(annotation: ChartAnnotation) {
    switch (annotation.severity) {
      case "critical":
      case "error":
        return this.surface.themeColor("--chart-critical-90");
      case "warning":
        return this.surface.themeColor("--chart-warning-90");
      case "info":
      case "unrecognized":
        return this.surface.themeColor("--chart-revision-88");
    }
  }
}
