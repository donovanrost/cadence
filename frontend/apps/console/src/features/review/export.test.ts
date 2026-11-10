import { describe, expect, it } from "vite-plus/test";
import type { StationLine } from "./api.ts";
import { allLost, reviewCsv, reviewFileName, type LostLine } from "./export.ts";

const station = { ref: "KIR", id: null, code: "KIR", name: "Kiruna" };
const byStation: StationLine[] = [
  {
    station,
    provider: { id: "p", name: "Northlight, Inc" },
    planned: 4,
    realized: 3,
    partial: 0,
    missed: 1,
    failed: 0,
    canceled: 0,
    planned_seconds: 1920,
    flown_seconds: 1440,
  },
];
const summary = { by_station: byStation };
const lost: LostLine[] = [
  {
    station,
    provider: null,
    spacecraft: { id: "sc-4", name: "EARENDIL-004" },
    planned_aos: "2026-11-10T00:54:00Z",
    planned_los: "2026-11-10T01:02:00Z",
    actual_aos: null,
    actual_los: null,
    outcome: "missed",
    cause: "station_outage",
    owner: "provider",
    planned_seconds: 480,
    flown_seconds: null,
    provider_bytes: null,
    received_bytes: null,
  },
];

describe("reviewCsv", () => {
  it("writes station and pass records in one table, quoting where needed, minutes not seconds", () => {
    const lines = reviewCsv(summary, lost).trimEnd().split("\r\n");
    expect(lines).toHaveLength(3);
    expect(lines[0]?.startsWith("record,station,provider,spacecraft,")).toBe(true);
    expect(lines[1]).toContain('station,KIR,"Northlight, Inc",');
    expect(lines[1]).toContain(",32,24,,");
    expect(lines[2]).toContain("pass,KIR,,EARENDIL-004,2026-11-10T00:54:00Z");
  });
});

describe("reviewFileName", () => {
  it("names the day, or the inclusive range for week/month", () => {
    const day = { missionId: "m", day: "2026-11-09", span: "day" } as const;
    const week = { ...day, span: "week" } as const;
    expect(reviewFileName("earendil", day, "", "")).toBe("pass-review-earendil-2026-11-09.csv");
    expect(reviewFileName("earendil", week, "2026-11-03T00:00:00Z", "2026-11-10T00:00:00Z")).toBe(
      "pass-review-earendil-2026-11-03_2026-11-09.csv",
    );
  });
});

describe("allLost", () => {
  it("walks every page by cursor", async () => {
    const pages = [
      { rows: lost, total: 2, disputable: 0, next_cursor: "c1" },
      { rows: lost, total: 2, disputable: 0, next_cursor: null },
    ];
    let i = 0;
    const page = (n: number) => {
      const p = pages[n];
      if (!p) throw new Error(`no page ${n}`);
      return p;
    };
    const r = await allLost({ missionId: "m", day: "2026-11-09", span: "day" }, () =>
      Promise.resolve({ ok: true as const, value: page(i++) }),
    );
    expect(r.ok && r.value.length).toBe(2);
  });
});
