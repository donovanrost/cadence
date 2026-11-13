import { describe, expect, it } from "vite-plus/test";
import { bookingStopped, bookingWindow } from "./booking.ts";

const pass = (id: string, start: string, locked = false) => ({
  snapshot_id: id,
  spacecraft_id: "sc",
  station: { ref: "KIR", id: null, code: null, name: null },
  starts_at: start,
  ends_at: start,
  synthetic: true,
  locked,
  expires_at: null,
  booking: null,
});
const plan = {
  id: "plan_1",
  passes: [
    pass("a", "2026-11-10T01:00:00Z"),
    pass("b", "2026-11-10T05:00:00Z"),
    pass("c", "2026-11-10T09:00:00Z", true),
  ],
};
const read = (
  ids: number,
  over: Partial<{ to: string; truncated: boolean }> = {},
  providers: readonly (string | null)[] = ["Northlight"],
) => ({
  from: "2026-11-10T00:00:00Z",
  to: "2026-11-11T00:00:00Z",
  truncated: false,
  passes: Array.from({ length: ids }, (_, i) => ({
    plan: { id: "plan_1" },
    source: { provider_name: providers[i % providers.length] ?? null },
  })),
  ...over,
});
const text = (r: ReturnType<typeof read> | null) => bookingStopped(plan, r).text;

describe("bookingStopped (U20)", () => {
  it("counts requests out against the unlocked passes", () => {
    expect(bookingStopped(plan, read(1))).toEqual({
      text: "Booking stopped. 1 request went out; 1 didn't.",
      tone: "stale",
      left: 1,
    });
  });
  it("nothing left reads as waiting on the provider, never '0 didn't' (ux 1a906155)", () => {
    expect(bookingStopped(plan, read(2))).toEqual({
      text: "All 2 requests went out · waiting for Northlight to confirm.",
      tone: "info",
      left: 0,
    });
    expect(text(read(2, {}, ["Northlight", "Kestrel"]))).toBe(
      "All 2 requests went out · waiting for the providers to confirm.",
    );
    const one = { id: "plan_1", passes: [pass("a", "2026-11-10T01:00:00Z")] };
    expect(bookingStopped(one, read(1)).text).toBe(
      "The request went out · waiting for Northlight to confirm.",
    );
  });
  it("says what is known when the read can't cover it", () => {
    const unknown = "Booking stopped before every request went out.";
    expect(text(null)).toBe(unknown);
    expect(text(read(1, { truncated: true }))).toBe(unknown);
    expect(text(read(1, { to: "2026-11-10T02:00:00Z" }))).toBe(unknown);
    expect(bookingStopped(plan, null).left).toBeNull();
  });
  it("windows the read over the unlocked passes", () => {
    expect(bookingWindow(plan)).toEqual({
      from: "2026-11-10T01:00:00.000Z",
      to: "2026-11-10T05:00:00.001Z",
    });
  });
});

describe("bookingStopped from execution counts (api cf3cd37a)", () => {
  const counts = (sent: number, never_sent: number) => ({
    requested: sent + never_sent,
    sent,
    never_sent,
    confirmed: sent,
    uncertain: 0,
    rejected: 0,
    failed: 0,
  });
  it("uses the exact counts even without a passes read", () => {
    expect(bookingStopped({ ...plan, execution: counts(812, 700) }, null)).toEqual({
      text: "Booking stopped. 812 requests went out; 700 didn't.",
      tone: "stale",
      left: 700,
    });
    expect(bookingStopped({ ...plan, execution: counts(4, 0) }, read(2)).text).toBe(
      "All 4 requests went out · waiting for Northlight to confirm.",
    );
  });
});
