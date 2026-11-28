import { describe, expect, it } from "vite-plus/test";
import { costOf, endpointOf, type ApiCall, type Recorder } from "./requests.ts";
import { findingsOf } from "./request-table.ts";

/** Synthetic request timings (#1037), not captured from a browser. */
const call = (url: string, start: number, end: number, bytes = 100): ApiCall => ({
  method: "GET",
  url,
  endpoint: endpointOf(url),
  start,
  end,
  bytes,
  status: 200,
});
const recorder = (calls: ApiCall[]): Recorder => ({
  calls,
  joins: [],
  join: () => undefined,
  settle: async () => {},
});

describe("request cost (#1037)", () => {
  it("names endpoints without their ids", () => {
    expect(endpointOf("/api/v1/missions/mission-earendil-demo/spacecraft/sc-12/values?x=1")).toBe(
      "/missions/:id/spacecraft/:id/values",
    );
    expect(endpointOf("/api/v1/session")).toBe("/session");
  });

  it("counts what started before ready, the longest waterfall, bytes and per-row reads", () => {
    const calls = [
      call("/api/v1/session", 0, 10),
      call("/api/v1/missions/m-1/fleet", 12, 40, 5_000),
      call("/api/v1/missions/m-1/alarms", 12, 30),
      ...[1, 2, 3, 4, 5].map((n) => call(`/api/v1/missions/m-1/spacecraft/sc-${n}/values`, 45, 50)),
      call("/api/v1/missions/m-1/passes?from=a", 51, 55),
      ...[2, 3, 4, 5, 6].map((n) => call(`/api/v1/missions/m-1/passes?from=a&cursor=${n}`, 56, 60)),
      call("/api/v1/missions/m-1/late", 500, 510),
    ];
    const cost = costOf(recorder(calls), 100);
    expect([cost.requests, cost.serialDepth, cost.bytes]).toEqual([14, 5, 5_000 + 13 * 100]);
    expect(cost.chain).toEqual([
      "GET /session",
      "GET /missions/:id/fleet",
      "GET /missions/:id/spacecraft/:id/values",
      "GET /missions/:id/passes",
      "GET /missions/:id/passes",
    ]);
    // Cursor pages of one read are one read: noted as pages, never per-row reads.
    expect(cost.repeated).toEqual([
      { endpoint: "GET /missions/:id/spacecraft/:id/values", count: 5 },
    ]);
    expect(cost.pages).toEqual([{ endpoint: "GET /missions/:id/passes", count: 5 }]);
  });

  it("lists only the egregious: per-row reads, growth with the fleet, or over ~1 s at 500", () => {
    const row = (screen: string, size: number, readyMs: number, requests: number) => ({
      screen,
      size,
      readyMs,
      cost: { requests, joins: 1, serialDepth: 4, chain: [], bytes: 0, repeated: [], pages: [] },
    });
    expect(
      findingsOf([
        row("Fleet", 500, 450, 6),
        row("Fleet", 1_000, 470, 6),
        row("Now", 500, 1_200, 9),
      ]),
    ).toEqual(["Now: 1200 ms to usable at 500 craft (over ~1 s)"]);
    expect(findingsOf([row("Now", 500, 400, 9), row("Now", 1_000, 420, 12)])).toEqual([
      "Now: 9 requests at 500 craft, 12 at 1,000 (grows with the fleet)",
    ]);
  });
});
