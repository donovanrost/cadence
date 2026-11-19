import { describe, expect, it } from "vite-plus/test";
import { stationId as stationIdReader } from "@/api/index.ts";
import type { Availability } from "@/features/scheduling/index.ts";
import { replanDays, replanSources } from "./sources.ts";

const availability = {
  at: "2026-11-12T23:00:00Z",
  stations: [
    {
      ground_station_id: stationIdReader("gs-sval"),
      state: "down",
      since: "2026-11-12T22:10:00Z",
      eta: null,
      basis: null,
      windows: [],
    },
    {
      ground_station_id: stationIdReader("gs-ksat"),
      state: "up",
      since: null,
      eta: null,
      basis: null,
      windows: [],
    },
  ],
} satisfies Availability;

describe("Re-plan landing sources (ux §7 #6)", () => {
  it("lists plans with failed or lost bookings, then stations that are down", () => {
    const sources = replanSources(
      [
        {
          day: "2026-11-12",
          plans: [
            { id: "p1", version: 2, state: "failed" },
            { id: "p2", version: 1, state: "reserved" },
          ],
        },
        { day: "2026-11-13", plans: [{ id: "p3", version: 1, state: "partially_reserved" }] },
      ],
      availability,
      () => "Svalbard",
    );
    expect(sources.map((s) => s.label)).toEqual([
      "11-12 plan v2 · booking failed",
      "11-13 plan v1 · partly booked",
      "Svalbard is down since 11-12 22:10Z",
    ]);
    expect(sources[2]?.to).toEqual({
      name: "ops.contacts.replan.station",
      params: { stationId: "gs-sval" },
    });
  });
  it("is empty when nothing needs a re-plan", () => {
    expect(replanSources([{ day: "2026-11-12", plans: [] }], null, () => "")).toEqual([]);
  });
  it("checks today and tomorrow in UTC", () => {
    expect(replanDays(new Date("2026-11-12T23:59:00Z"))).toEqual(["2026-11-12", "2026-11-13"]);
  });
});
