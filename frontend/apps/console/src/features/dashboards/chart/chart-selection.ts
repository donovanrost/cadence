import type { PointMetadata } from "./chart-points.ts";
import type { ChartSurface } from "./chart-surface.ts";

/**
 * Owns point hit testing: a click on a sample opens its data link. (The selected-evidence overlay
 * it once drew had no producer in the console: nothing passes a selection to the chart.)
 */
export class ChartSelection {
  constructor(private readonly surface: ChartSurface) {}
  openPointInspector(event: MouseEvent) {
    if (this.surface.rangeSelectionInFlight) return;
    const index = this.pointIndexFromEvent(event);
    if (index === null || index === undefined) return;

    const metadata = this.pointMetadataAt(index, event);
    if (!metadata.link_id) return;

    const timestamp = this.surface.model.xs[index];
    if (timestamp === undefined) return;
    this.surface.pushEvent(
      "open_data_link",
      this.surface.pointDataLinkPayload(metadata, Math.round(timestamp * 1000)),
    );
  }

  pointMetadataAt(index: number, event: MouseEvent): PointMetadata {
    const seriesMeta = this.surface.model.seriesPointMeta;
    const pointerTop = this.pointerTop(event);
    const candidates = [];

    for (let seriesIndex = 0; seriesIndex < seriesMeta.length; seriesIndex += 1) {
      const series = this.surface.model.seriesList[seriesIndex];
      if (!series || !this.surface.model.seriesVisible(series)) continue;

      const metadataByTime = seriesMeta[seriesIndex];
      const metadata = metadataByTime?.[index] ?? {};
      if (!metadata.link_id) continue;

      const value = this.surface.model.seriesYs[seriesIndex]?.[index];
      if (value === null || value === undefined) continue;

      const top =
        (this.surface.chart.bbox.top || 0) +
        this.surface.chart.valToPos(value, this.surface.model.unitScaleKey(series.unit), false);

      candidates.push({
        metadata,
        distance: pointerTop === null || Number.isNaN(top) ? 0 : Math.abs(top - pointerTop),
      });
    }

    candidates.sort((left, right) => left.distance - right.distance);
    return (candidates[0] && candidates[0].metadata) || {};
  }

  pointerTop(event: MouseEvent) {
    const overlay = this.surface.el.querySelector(".u-over");
    if (!overlay || !event) return null;

    const rect = overlay.getBoundingClientRect();
    const top = event.clientY - rect.top;
    if (top < 0 || top > rect.height) return null;

    return top;
  }

  pointIndexFromEvent(event: MouseEvent) {
    if (!this.surface.chart || this.surface.model.xs.length === 0) return null;

    const overlay = this.surface.el.querySelector(".u-over");
    if (!overlay) return this.surface.chart.cursor && this.surface.chart.cursor.idx;

    const rect = overlay.getBoundingClientRect();
    const left = event.clientX - rect.left;
    if (left < 0 || left > rect.width) return null;

    return this.surface.chart.posToIdx(left);
  }
}
