import type { ChartMarker } from "./chart-input.ts";
import type { ChartSurface } from "./chart-surface.ts";

export type AnnotationGeometry = {
  geometry: "interval" | "point";
  left: number;
  width: number;
  top: number;
  color: string;
};

/** Annotation evidence popovers and their labels (split from ChartAnnotations). */
export class ChartAnnotationTooltip {
  constructor(private readonly surface: ChartSurface) {}
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
}
