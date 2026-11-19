import { describe, expect, it } from "vite-plus/test";
import { stripCell, stripDays, type PlanDay } from "./day-strip.ts";

const now = new Date("2026-11-16T12:00:00Z");
const day = (over: Partial<PlanDay>): PlanDay => ({
  day: "2026-11-17",
  plan: null,
  sent_back: false,
  requirements_count: 1512,
  booked_count: null,
  unconfirmed_count: null,
  requested_count: null,
  first_window_at: null,
  ...over,
});
const plan = (state: NonNullable<PlanDay["plan"]>["state"]) => ({ id: "p", version: 41, state });

describe("K1 day strip (DECISIONS #100)", () => {
  it("covers the next 7 UTC days, today first", () => {
    expect(stripDays(now)).toEqual([
      "2026-11-16",
      "2026-11-17",
      "2026-11-18",
      "2026-11-19",
      "2026-11-20",
      "2026-11-21",
      "2026-11-22",
    ]);
  });

  it("words each state as ux's table does, booked counted against what the plan books", () => {
    expect(stripCell(day({ plan: plan("reserved") }), now)).toMatchObject({
      label: "Tue 17",
      word: "Booked",
      mark: { glyph: "■", state: "nominal" },
    });
    expect(
      stripCell(
        day({ plan: plan("partially_reserved"), booked_count: 1490, requested_count: 1500 }),
        now,
      ).word,
    ).toBe("1,490 of 1,500 booked");
    expect(stripCell(day({ plan: plan("unconfirmed"), unconfirmed_count: 4 }), now).word).toBe(
      "4 unconfirmed",
    );
    expect(stripCell(day({ plan: plan("executing") }), now).word).toBe("Booking…");
    expect(stripCell(day({ plan: plan("approved") }), now).word).toBe("Approved");
    expect(
      stripCell(day({ plan: plan("interrupted"), booked_count: 12, requested_count: 41 }), now),
    ).toMatchObject({ word: "Booking stopped · 12 of 41", mark: { glyph: "▲", state: "caution" } });
    expect(stripCell(day({ plan: plan("draft"), sent_back: true }), now).word).toBe("Sent back");
    expect(stripCell(day({ plan: plan("superseded") }), now).word).toBe("Draft");
    expect(stripCell(day({}), now).word).toBe("No plan");
    expect(stripCell(day({ requirements_count: 0 }), now).word).toBe("Nothing to plan");
  });

  it("takes U61's thresholds on unbooked days, and names the cell with its first window", () => {
    const pending = day({
      plan: plan("pending_approval"),
      first_window_at: "2026-11-17T00:00:00Z",
    });
    expect(stripCell(pending, now)).toMatchObject({
      word: "Awaiting approval",
      mark: { glyph: "▲", state: "caution" },
      name: "Tue 17 Nov: awaiting approval, first window 00:00Z",
    });
    const approved = day({ plan: plan("approved"), first_window_at: "2026-11-17T00:00:00Z" });
    expect(stripCell(approved, now).mark).toEqual({ glyph: "▲", state: "caution" });
    expect(stripCell(pending, new Date("2026-11-17T01:00:00Z"))).toMatchObject({
      word: "Started unplanned",
      mark: { glyph: "◆", state: "crit" },
    });
    expect(stripCell(day({ plan: plan("pending_approval") }), now).mark).toBeNull();
  });
});
