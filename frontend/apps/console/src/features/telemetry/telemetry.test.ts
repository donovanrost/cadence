import { describe, expect, it } from "vite-plus/test";
import { spacecraftId as spacecraftIdReader, scid as scidReader, decode } from "@/api/index.ts";
import { latestMark, pointsReader } from "./api.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import type { History } from "@/features/investigate/index.ts";
import { cappedLine, latestRows, plotView } from "./plot.ts";
import { MAX_SERIES, parseSelection, selectionQuery, seriesOf, STYLES } from "./selection.ts";
import type { SeriesData } from "./useSeries.ts";
import { parseWindow, resolveWindow, windowFromRange, windowQuery } from "./window.ts";

describe("telemetry selection", () => {
  it("round-trips through the URL, dropping junk and the default range", () => {
    const sel = parseSelection({
      sc: "1,x,312,1",
      p: "EPS.VBAT,,HK.mode",
      range: "bogus",
      tab: "a",
    });
    expect(sel).toEqual({
      scids: [1, 312],
      points: ["EPS.VBAT", "HK.mode"],
      window: { kind: "preset", key: "6h" },
    });
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
  unit: "V",
  description: null,
  spacecraft_id: spacecraftIdReader("sc"),
  from: "2026-11-08T00:00:00Z",
  to: "2026-11-08T06:00:00Z",
  bucket_width_ms: 60_000,
  truncated: false,
  buckets: buckets.map(([t, v]) => ({ t, t_end: t, min: v - 1, mean: v, max: v + 1, count: 1 })),
});
const data = (scid: number, buckets: [string, number][]): SeriesData => ({
  key: { scid: scidReader(scid), pointId: "EPS.VBAT" },
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
      "EARENDIL-001 › EPS.VBAT (V)",
      "EARENDIL-002 › EPS.VBAT (V)",
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

describe("plot window", () => {
  const now = new Date("2026-11-08T12:00:00Z");
  it("keeps presets sliding and custom ranges fixed in the URL", () => {
    expect(parseWindow({ range: "24h" }, "6h")).toEqual({ kind: "preset", key: "24h" });
    const custom = parseWindow({ from: "2026-11-08T01:00:00Z", to: "2026-11-08T02:00:00Z" }, "6h");
    expect(custom.kind).toBe("custom");
    expect(windowQuery(custom, { sc: "1", range: "1h" }, "6h")).toEqual({
      sc: "1",
      from: "2026-11-08T01:00:00.000Z",
      to: "2026-11-08T02:00:00.000Z",
    });
    expect(windowQuery({ kind: "preset", key: "6h" }, { from: "x", to: "y" }, "6h")).toEqual({});
  });

  it("maps a picked range back to a preset when it matches one", () => {
    const sixHours = resolveWindow({ kind: "preset", key: "6h" }, now);
    expect(windowFromRange(sixHours, now)).toEqual({ kind: "preset", key: "6h" });
    expect(windowFromRange({ from: sixHours.from + 3_600_000, to: sixHours.to }, now).kind).toBe(
      "custom",
    );
  });
});

describe("M23 points reader", () => {
  it("reads a null limit_state on a latest as no_data (unknown, never nominal)", () => {
    const r = decode(pointsReader, {
      points: [
        {
          id: "p",
          name: "MODE",
          description: null,
          unit: null,
          subsystem: null,
          type: "numeric",
          latest: { value: 1, received_at: "2026-11-10T21:00:00Z", limit_state: null },
        },
      ],
    });
    expect(r.ok && r.value.points[0]?.latest?.limit_state).toBe("no_data");
  });
  it("reads a point type it doesn't know as unrecognized, not a failed read (lead)", () => {
    const r = decode(pointsReader, {
      points: [
        { id: "p", name: "Q", description: null, unit: null, subsystem: null, type: "quaternion" },
      ],
    });
    expect(r.ok && r.value.points[0]?.type).toBe("unrecognized");
  });
});

describe("M23 latest.source (551cb796, b8181eb9)", () => {
  const latest = (
    limit_state: "critical" | "nominal" | "no_data",
    source?: "live" | "history",
  ) => ({
    value: 1,
    received_at: "2026-11-10T21:00:00Z",
    limit_state,
    source,
  });
  it("marks a history value stale unless its limits are out now", () => {
    expect(latestMark(latest("nominal", "history"))).toBe("stale");
    expect(latestMark(latest("critical", "history"))).toBe("crit");
    expect(latestMark(latest("nominal", "live"))).toBe("nominal");
    expect(latestMark(latest("nominal"))).toBe("nominal");
    expect(latestMark(null)).toBe("stale");
  });
});

describe("capped history line (D11, ux)", () => {
  const cut = (buckets: [string, number][], from = "2026-11-08T09:00:00Z"): SeriesData => {
    const d = data(1, buckets);
    return { ...d, history: { ...d.history, from, truncated: true } };
  };
  it("names the part shown: the read's start to its last bucket's end, earliest cut wins", () => {
    expect(cappedLine([data(1, [["2026-11-08T09:00:00Z", 1]])])).toBeNull();
    expect(
      cappedLine([cut([["2026-11-08T10:12:00Z", 1]]), cut([["2026-11-08T11:00:00Z", 1]])]),
    ).toBe(
      "This range has more samples than one read returns (20,000). The plot shows 09:00Z to 10:12Z; samples after 10:12Z weren't read. Pick a shorter or later range to see the rest.",
    );
  });
  it("adds dates when the shown span crosses days", () => {
    expect(cappedLine([cut([["2026-11-16T03:12:00Z", 1]], "2026-11-15T22:00:00Z")])).toBe(
      "This range has more samples than one read returns (20,000). The plot shows 11-15 22:00Z to 11-16 03:12Z; samples after 11-16 03:12Z weren't read. Pick a shorter or later range to see the rest.",
    );
  });
});
