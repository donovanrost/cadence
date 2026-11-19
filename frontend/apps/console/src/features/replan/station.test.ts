import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { availabilityReader, outageWindow, stationTag } from "./station.ts";

const w = (
  id: string,
  kind: string,
  from: string,
  to: string | null,
  cleared: string | null = null,
) => ({
  id,
  ground_station_id: "gs-1",
  kind,
  from,
  to,
  eta: null,
  source: "simulator",
  reported_by: null,
  reason: null,
  cleared_at: cleared,
});
const body = (windows: unknown[]) => ({
  status: {
    ground_station_id: "gs-1",
    state: "down",
    since: null,
    eta: null,
    source: "simulator",
    basis: null,
    windows: [],
  },
  from: "2026-11-09T00:00:00Z",
  to: "2026-11-16T00:00:00Z",
  windows,
});

describe("station availability (S7)", () => {
  it("re-plans around the active outage, else the next one, never a degraded or cleared window", () => {
    const now = new Date("2026-11-09T12:00:00Z");
    const r = decode(
      availabilityReader,
      body([
        w("deg", "degraded", "2026-11-09T11:00:00Z", null),
        w("old", "outage", "2026-11-09T10:00:00Z", "2026-11-09T13:00:00Z", "2026-11-09T11:30:00Z"),
        w("next", "maintenance", "2026-11-10T02:00:00Z", "2026-11-10T04:00:00Z"),
        w("now", "outage", "2026-11-09T11:50:00Z", null),
      ]),
    );
    if (!r.ok) throw r.error;
    expect(outageWindow(r.value, now)?.id).toBe("now");
    const later = decode(
      availabilityReader,
      body([w("next", "maintenance", "2026-11-10T02:00:00Z", "2026-11-10T04:00:00Z")]),
    );
    if (!later.ok) throw later.error;
    expect(outageWindow(later.value, now)?.id).toBe("next");
  });

  it("never calls 'up' live: it means nothing is reported", () => {
    expect(stationTag("up")).toEqual({ state: "neutral", label: "Nothing reported" });
    expect(stationTag("up", true)).toEqual({ state: "neutral", label: "Up now" });
  });
});
