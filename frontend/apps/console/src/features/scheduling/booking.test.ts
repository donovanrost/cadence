import { describe, expect, it } from "vite-plus/test";
import { bookingStopped } from "./booking.ts";

const counts = (sent: number, never_sent: number, provider_names: readonly string[] = []) => ({
  execution: {
    requested: sent + never_sent,
    sent,
    never_sent,
    confirmed: sent,
    uncertain: 0,
    rejected: 0,
    failed: 0,
    provider_names,
  },
});

describe("bookingStopped from the plan's execution counts (U20, #793)", () => {
  it("counts the requests that went out and those that didn't, at fleet size", () => {
    expect(bookingStopped(counts(812, 700))).toEqual({
      text: "Booking stopped. 812 requests went out; 700 didn't.",
      tone: "stale",
      left: 700,
    });
    expect(bookingStopped(counts(1, 1)).text).toBe(
      "Booking stopped. 1 request went out; 1 didn't.",
    );
  });

  it("nothing left reads as waiting on the provider, never '0 didn't' (ux 1a906155)", () => {
    expect(bookingStopped(counts(2, 0, ["Northlight"]))).toEqual({
      text: "All 2 requests went out · waiting for Northlight to confirm.",
      tone: "info",
      left: 0,
    });
    expect(bookingStopped(counts(2, 0, ["Kestrel", "Northlight"])).text).toBe(
      "All 2 requests went out · waiting for the providers to confirm.",
    );
    expect(bookingStopped(counts(1, 0, ["Northlight"])).text).toBe(
      "The request went out · waiting for Northlight to confirm.",
    );
    expect(bookingStopped(counts(3, 0)).text).toBe(
      "All 3 requests went out · waiting for the provider to confirm.",
    );
  });

  it("says only what is known without counts", () => {
    expect(bookingStopped({ execution: null })).toEqual({
      text: "Booking stopped before every request went out.",
      tone: "stale",
      left: null,
    });
  });
});
