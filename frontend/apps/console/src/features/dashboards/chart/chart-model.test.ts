import { expect, test } from "vite-plus/test";
import { ChartModel } from "./chart-model.ts";
import type { ContactMarker, LimitDefinitionMarker, MissionEventMarker } from "./chart-markers.ts";
import { required } from "./required.test-support.ts";

const event = (id: string, timestamp_ms: number): MissionEventMarker => ({
  marker_type: "mission_event",
  marker_id: id,
  link_id: id,
  timestamp_ms,
  title: null,
  severity: null,
});
const contact = (id: string, starts_at_ms: number, ends_at_ms: number | null): ContactMarker => ({
  marker_type: "contact_interval",
  marker_id: id,
  link_id: id,
  starts_at_ms,
  ends_at_ms,
  label: null,
  status: null,
  station: null,
  kind: null,
  started: null,
  close_reason: null,
});
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
test("series appends and window trimming keep interval overlaps and drop points before the window", () => {
  const model = new ChartModel({
    ...input,
    time_mode: "live",
    backfill: [
      [1_000, 1],
      [60_000, 2],
    ],
    event_markers: [
      event("past", 1_000),
      contact("interval", 1_000, 80_000),
      event("late", 110_000),
    ],
  });
  expect(model.appendSeriesPayload([[120_000, 3]])).toBe(true);
  expect(model.advanceLiveWindow(120_000)).toBe(true);
  model.trimToWindow();
  expect(model.plotData()).toEqual([
    [60, 120],
    [2, 3],
  ]);
  expect(model.eventMarkers.map((marker) => marker.marker_id)).toEqual(["interval", "late"]);
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
});
test("an open interval's missing end never pulls the x range back to the epoch", () => {
  const definition: LimitDefinitionMarker = {
    marker_type: "limit_definition_interval",
    marker_id: "d",
    link_id: "d",
    starts_at_ms: 10_000,
    ends_at_ms: null,
    limit_definition_id: null,
    limit_set_name: null,
    limit_definition_version: null,
    red_low: null,
    yellow_low: null,
    yellow_high: null,
    red_high: null,
  };
  const model = new ChartModel({ ...input, limit_markers: [definition] });
  expect(
    model.markerXValues([definition, contact("c", 20_000, 30_000), event("e", 5_000)]),
  ).toEqual([10, 20, 30, 5]);
  expect(model.chartXRange(12, 14)).toEqual([10, 14]);
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
