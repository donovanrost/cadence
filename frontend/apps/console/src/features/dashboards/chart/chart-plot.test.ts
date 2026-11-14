import type uPlot from "uplot";
import { describe, expect, it } from "vite-plus/test";
import { utcTimeLabels } from "./chart-plot.ts";

const u = {} as uPlot;
const at = (iso: string) => Date.parse(iso) / 1000;

describe("x axis labels (UTC, §4)", () => {
  it("labels minutes in 24-hour UTC, not local 12-hour", () => {
    expect(
      utcTimeLabels(u, [at("2026-11-14T07:00:00Z"), at("2026-11-14T07:15:00Z")], 0, 50, 300),
    ).toEqual(["07:00", "07:15"]);
  });
  it("adds seconds below a minute's spacing and shows the date at a day's", () => {
    expect(utcTimeLabels(u, [at("2026-11-14T07:20:02Z")], 0, 50, 10)).toEqual(["07:20:02"]);
    expect(utcTimeLabels(u, [at("2026-11-13T00:00:00Z")], 0, 50, 86_400)).toEqual(["11-13"]);
  });
});
