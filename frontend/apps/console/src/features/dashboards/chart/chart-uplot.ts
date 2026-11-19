import type uPlot from "uplot";

/** uPlot 1.6.32 implements a third setCursor argument to publish to its sync group,
 * but omits it from dist/uPlot.d.ts. Keep the version-specific call here; the real
 * browser chart story verifies cross-chart propagation from overlay controls. */
export function synchronizeCursor(plot: uPlot, position: { left: number; top: number }) {
  const setCursor: (
    position: { left: number; top: number },
    fireHook: boolean,
    publish: boolean,
  ) => void = plot.setCursor.bind(plot);
  setCursor(position, true, true);
}
