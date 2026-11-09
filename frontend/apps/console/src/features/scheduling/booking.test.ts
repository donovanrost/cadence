import { describe, expect, it } from "vite-plus/test";
import { bookingStoppedText, bookingWindow } from "./booking.ts";

const pass = (id: string, start: string, locked = false) => ({
  snapshot_id: id,
  spacecraft_id: "sc",
  station: { ref: "KIR", id: null, code: null, name: null },
  starts_at: start,
  ends_at: start,
  synthetic: true,
  locked,
});
const plan = {
  id: "plan_1",
  passes: [
    pass("a", "2026-11-10T01:00:00Z"),
    pass("b", "2026-11-10T05:00:00Z"),
    pass("c", "2026-11-10T09:00:00Z", true),
  ],
};
const read = (ids: number, over: Partial<{ to: string; truncated: boolean }> = {}) => ({
  from: "2026-11-10T00:00:00Z",
  to: "2026-11-11T00:00:00Z",
  truncated: false,
  passes: Array.from({ length: ids }, () => ({ plan: { id: "plan_1" } })),
  ...over,
});

describe("bookingStoppedText (U20)", () => {
  it("counts requests out against the unlocked passes", () => {
    expect(bookingStoppedText(plan, read(1))).toBe(
      "Booking stopped. 1 request went out; 1 didn't.",
    );
  });
  it("says what is known when the read can't cover it", () => {
    const unknown = "Booking stopped before every request went out.";
    expect(bookingStoppedText(plan, null)).toBe(unknown);
    expect(bookingStoppedText(plan, read(1, { truncated: true }))).toBe(unknown);
    expect(bookingStoppedText(plan, read(1, { to: "2026-11-10T02:00:00Z" }))).toBe(unknown);
  });
  it("windows the read over the unlocked passes", () => {
    expect(bookingWindow(plan)).toEqual({
      from: "2026-11-10T01:00:00.000Z",
      to: "2026-11-10T05:00:00.001Z",
    });
  });
});
