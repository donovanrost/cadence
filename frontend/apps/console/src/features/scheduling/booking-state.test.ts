import { describe, expect, it } from "vite-plus/test";
import type { PlanPass } from "./api.ts";
import { bookingLook, rejectedRows } from "./booking-state.ts";

const pass = (id: string, booking: PlanPass["booking"]): PlanPass => ({
  snapshot_id: id,
  spacecraft_id: "sc1",
  station: { ref: "svb", id: "gs_svb", code: "SVB-1", name: "Svalbard" },
  starts_at: "2026-11-13T03:00:00Z",
  ends_at: "2026-11-13T03:08:00Z",
  synthetic: false,
  locked: false,
  booking,
});

describe("K1 per-contact booking (api 8e)", () => {
  it("draws each state with a word, and nothing special before execution or for an unknown state", () => {
    expect(bookingLook({ state: "confirmed", reason: null, at: null })).toEqual({
      kind: "own",
      word: "Confirmed",
    });
    expect(bookingLook({ state: "rejected", reason: "no_capacity", at: null })?.kind).toBe("clash");
    expect(bookingLook({ state: "uncertain", reason: null, at: null })?.kind).toBe("unconfirmed");
    expect(bookingLook({ state: "never_sent", reason: "sending", at: null })?.word).toBe(
      "Requested · sending",
    );
    expect(bookingLook(null)).toBeNull();
    expect(bookingLook({ state: "teleported", reason: null, at: null })).toBeNull();
  });

  it("turns rejected and failed bookings into Demand rows, with the server's reason when it has one", () => {
    const rows = rejectedRows([
      pass("a", { state: "confirmed", reason: null, at: null }),
      pass("b", { state: "rejected", reason: "antenna_fault", at: null }),
      pass("c", { state: "failed", reason: null, at: null }),
      pass("d", null),
    ]);
    expect(rows.map((r) => r.sentence)).toEqual([
      "Rejected · SVB-1 03:00Z: antenna fault",
      "Failed · SVB-1 03:00Z",
    ]);
  });
});
