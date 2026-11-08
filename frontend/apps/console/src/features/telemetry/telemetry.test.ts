import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { History } from "@/features/investigate/index.ts";
import { latestRows, plotView } from "./plot.ts";
import { MAX_SERIES, parseSelection, selectionQuery, seriesOf, STYLES } from "./selection.ts";
import type { SeriesData } from "./useSeries.ts";

describe("telemetry selection", () => {
  it("round-trips through the URL, dropping junk and the default range", () => {
    const sel = parseSelection({
      sc: "1,x,312,1",
      p: "EPS.VBAT,,HK.mode",
      range: "bogus",
      tab: "a",
    });
    expect(sel).toEqual({ scids: [1, 312], points: ["EPS.VBAT", "HK.mode"], range: "6h" });
    expect(selectionQuery(sel, { tab: "a", range: "24h" })).toEqual({
      tab: "a",
      sc: "1,312",
      p: "EPS.VBAT,HK.mode",
    });
  });

  it("caps spacecraft × point series at six and reports the rest", () => {
    const sel = parseSelection({ sc: "1,2,3,4", p: "A,B" });
    const { series, dropped } = seriesOf(sel);
    expect(series).toHaveLength(MAX_SERIES);
    expect(dropped).toBe(2);
    expect(series[0]).toEqual({ scid: 1, pointId: "A" });
  });

  it("styles series with grays and dashes only", () => {
    expect(
      STYLES.map((s) => s.tone).every((t) => ["readout", "text-2", "text-3", "text-4"].includes(t)),
    ).toBe(true);
    expect(new Set(STYLES.map((s) => `${s.tone}/${s.dash}`)).size).toBe(STYLES.length);
  });
});

const history = (buckets: [string, number][]): History => ({
  point_id: "EPS.VBAT",
  spacecraft_id: "sc",
  from: "2026-11-08T00:00:00Z",
  to: "2026-11-08T06:00:00Z",
  bucket_width_ms: 60_000,
  truncated: false,
  buckets: buckets.map(([t, v]) => ({ t, t_end: t, min: v - 1, mean: v, max: v + 1, count: 1 })),
});
const data = (scid: number, buckets: [string, number][]): SeriesData => ({
  key: { scid, pointId: "EPS.VBAT" },
  sc: spacecraftRow(scid),
  history: history(buckets),
});

describe("plot view", () => {
  it("makes the first series primary and the rest styled comparisons, limits only for one series", () => {
    const one = plotView([data(1, [["2026-11-08T01:00:00Z", 24]])], null);
    expect(one?.comparison).toHaveLength(0);
    const two = plotView([data(1, []), data(2, [["2026-11-08T01:00:00Z", 25]])], null);
    expect(two?.comparison[0]).toMatchObject({ tone: "text-2", dash: "solid" });
    expect(two?.limits).toEqual([]);
    expect(two?.legend.map((l) => l.label)).toEqual([
      "EARENDIL-001 › EPS.VBAT",
      "EARENDIL-002 › EPS.VBAT",
    ]);
  });

  it("reports the newest bucket per series", () => {
    const rows = latestRows([
      data(1, [
        ["2026-11-08T01:00:00Z", 24],
        ["2026-11-08T02:00:00Z", 23],
      ]),
      data(2, []),
    ]);
    expect(rows.map((r) => r.last?.mean ?? null)).toEqual([23, null]);
  });
});
