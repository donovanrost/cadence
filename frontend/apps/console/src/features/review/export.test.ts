import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader, spacecraftId } from "@/api/index.ts";
import { allLost, reviewCsv, reviewFileName, type LostLine } from "./export.ts";

const station = { ref: "KIR", id: null, code: "KIR", name: "Kiruna" };
const lost: LostLine[] = [
  {
    station,
    provider: null,
    spacecraft: { id: spacecraftId("sc-4"), name: "EARENDIL-004", scid: null },
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

describe("reviewCsv (ux: pass rows only, ISO UTC, words)", () => {
  it("writes one row per pass with full ISO times and outcome / cause / owner as words", () => {
    const lines = reviewCsv(lost).trimEnd().split("\r\n");
    expect(lines).toHaveLength(2);
    expect(lines[0]?.startsWith("Station,Provider,Spacecraft,Planned AOS (UTC),")).toBe(true);
    expect(lines[1]).toBe(
      "KIR,,EARENDIL-004,2026-11-10T00:54:00Z,2026-11-10T01:02:00Z,,,Missed,Station outage,Provider,8,,,",
    );
  });
});

describe("reviewFileName", () => {
  it("names the day, or the inclusive range for week/month", () => {
    const day = { missionId: missionIdReader("m"), day: "2026-11-09", span: "day" } as const;
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
    const r = await allLost(
      { missionId: missionIdReader("m"), day: "2026-11-09", span: "day" },
      () => Promise.resolve({ ok: true as const, value: page(i++) }),
    );
    expect(r.ok && r.value.length).toBe(2);
  });
});
