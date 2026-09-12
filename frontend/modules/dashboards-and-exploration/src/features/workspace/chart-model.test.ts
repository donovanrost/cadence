import { expect, test } from "vite-plus/test";
import { ChartModel } from "./chart-model";
import { readMarkers, readSelection } from "./chart-input";
import { required } from "../../../../../test-support/required";

const input = {
  chart_id: "chart",
  widget_id: "battery",
  placement_id: "p",
  correlation_group: "power",
  window_seconds: 60,
};
test("aligns series and explicit gaps, preserves point evidence, and pairs envelope bounds", () => {
  const model = new ChartModel({
    ...input,
    backfill: {
      series: [
        {
          id: "voltage",
          points: [
            [1_000, 28, { link_id: "sample-1" }],
            [3_000, null],
          ],
          envelope: { points: [[1_000, 27, 29]] },
        },
        {
          id: "temperature",
          points: [
            [2_000, 20],
            [3_000, 21],
          ],
        },
      ],
    },
  });
  expect(model.plotData()).toEqual([
    [1, 2, 3],
    [28, null, null],
    [27, null, null],
    [29, null, null],
    [null, 20, 21],
  ]);
  expect(required(model.seriesPointMeta[0])[0]).toMatchObject({
    link_id: "sample-1",
    series_id: "voltage",
    series_role: "primary",
  });
  expect(model.seriesList.map((series) => series.id)).toEqual(["voltage", "temperature"]);
});
test("append and window trimming retain interval overlaps and the latest watermark per source", () => {
  const model = new ChartModel({
    ...input,
    time_mode: "live",
    backfill: [
      [1_000, 1],
      [60_000, 2],
    ],
    event_markers: [
      { marker_id: "past", marker_type: "mission_event", timestamp_ms: 1_000 },
      {
        marker_id: "interval",
        marker_type: "source_binding_interval",
        starts_at_ms: 1_000,
        ends_at_ms: 80_000,
      },
      {
        marker_id: "cursor-a",
        marker_type: "source_watermark_cursor",
        data_source_id: "source",
        timestamp_ms: 60_000,
      },
    ],
  });
  expect(model.appendSeriesPayload([[120_000, 3]])).toBe(true);
  expect(
    model.appendMarkerPayload({
      event_markers: [
        {
          marker_id: "cursor-b",
          marker_type: "source_watermark_cursor",
          data_source_id: "source",
          timestamp_ms: 110_000,
        },
        {
          marker_id: "other",
          marker_type: "source_watermark_cursor",
          data_source_id: "other",
          timestamp_ms: 100_000,
        },
      ],
    }),
  ).toBe(true);
  expect(model.advanceLiveWindow(120_000)).toBe(true);
  model.trimToWindow();
  expect(model.plotData()).toEqual([
    [60, 120],
    [2, 3],
  ]);
  expect(model.eventMarkers.map((marker) => marker.marker_id)).toEqual([
    "interval",
    "cursor-b",
    "other",
  ]);
  expect(model.chartXRange(60, 120)).toEqual([60, 120]);
});
test("normalizers reject malformed coordinates and keep absent marker timestamps absent", () => {
  const model = new ChartModel({
    ...input,
    backfill: {
      series: [
        null,
        {
          id: "x",
          points: [
            ["bad", 0],
            [1_000, Infinity],
            [2_000, null],
          ],
        },
      ],
    },
  });
  expect(model.plotData()).toEqual([[2], [null]]);
  expect(
    readMarkers([null, "bad", { timestamp_ms: null }, { timestamp_ms: Symbol("bad") }]),
  ).toEqual([{ timestamp_ms: null }, { timestamp_ms: null }]);
  expect(readSelection({ timestamp_ms: "3000", placement_id: "p" })).toEqual({
    timestamp_ms: 3_000,
    placement_id: "p",
  });
  expect(readSelection(null)).toBeNull();
});
test("inferred gaps use observed cadence and coalesce pixel ranges without filling explicit gaps", () => {
  const model = new ChartModel(input);
  expect(model.inferredGapThreshold([1, 2, 3])).toBeNull();
  expect(model.inferredGapThreshold([1, 2, 3, 4, 30])).toBe(5);
  expect(
    model.mergePixelGaps([
      [30, 10],
      [20, 40],
      [50, 60],
      [NaN, 1],
    ]),
  ).toEqual([
    [10, 40],
    [50, 60],
  ]);
});
