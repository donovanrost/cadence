import type { ChartAnnotation } from "./chart-markers.ts";
import type { ChartSurface } from "./chart-surface.ts";

export type AnnotationGeometry = {
  geometry: "interval" | "point";
  left: number;
  width: number;
  top: number;
  color: string;
};

/**
 * Annotation popovers and their labels (split from ChartAnnotations): time and title. Snapshot
 * annotations carry no text, tags, provider/layer or evidence link, so none are drawn.
 */
export class ChartAnnotationTooltip {
  constructor(private readonly surface: ChartSurface) {}
  buildAnnotationTooltip(
    annotation: ChartAnnotation,
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
    tooltip.dataset.chartAnnotationId = annotation.annotation_id;
    Object.assign(tooltip.style, {
      position: "absolute",
      left: `${absoluteLeft - wrapperLeft}px`,
      bottom: "10px",
      width: `${tooltipWidth}px`,
      border: `1px solid ${this.surface.themeColor("--chart-border-30")}`,
      borderTop: `2px solid ${color}`,
      borderRadius: "4px",
      background: `${this.surface.themeColor("--chart-panel-98")}`,
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
      marginBottom: "0",
    });
    title.textContent = this.annotationLabel(annotation);
    body.appendChild(title);

    tooltip.appendChild(body);
    return tooltip;
  }

  annotationLabel(annotation: ChartAnnotation) {
    return annotation.title || "Annotation";
  }

  annotationTimeLabel(annotation: ChartAnnotation) {
    const start = this.annotationTimestampLabel(annotation.starts_at_ms);

    if (annotation.geometry !== "interval") return start;

    return `${start} – ${this.annotationTimestampLabel(annotation.ends_at_ms)}`;
  }

  /** An open interval's missing end reads "Time unavailable" (it used to read as the epoch). */
  annotationTimestampLabel(timestampMs: number | null) {
    if (timestampMs === null) return "Time unavailable";

    return new Date(timestampMs).toLocaleString(undefined, {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }
}
