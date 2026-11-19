import { describe, expect, it } from "vite-plus/test";
import { replanLink } from "./replanLink.ts";

const now = Date.parse("2026-11-16T08:00:00Z");
const pass = (
  state: "rejected" | "failed" | "confirmed",
  day: string | undefined,
  ends: string,
) => ({
  state,
  ends_at: ends,
  plan: { id: "plan-1", version: 2, day },
});

describe("Re-plan on the pass drawer (K2, gated for History)", () => {
  it("offers Re-plan while the plan's day hasn't ended", () => {
    expect(
      replanLink(pass("rejected", "2026-11-16T00:00:00Z", "2026-11-16T03:00:00Z"), now),
    ).toEqual({ name: "ops.contacts.replan", query: { plan: "plan-1" } });
  });

  it("hides it once the plan's day is over, and falls back to the pass's end without a day", () => {
    expect(replanLink(pass("failed", "2026-11-12T00:00:00Z", "2026-11-12T03:00:00Z"), now)).toBe(
      null,
    );
    expect(replanLink(pass("failed", undefined, "2026-11-16T09:00:00Z"), now)).not.toBe(null);
    expect(replanLink(pass("failed", undefined, "2026-11-16T07:00:00Z"), now)).toBe(null);
  });

  it("never offers it for a booked pass or one without a plan", () => {
    expect(replanLink(pass("confirmed", "2026-11-16T00:00:00Z", "2026-11-16T09:00:00Z"), now)).toBe(
      null,
    );
    expect(
      replanLink({ state: "rejected", ends_at: "2026-11-16T09:00:00Z", plan: null }, now),
    ).toBe(null);
    expect(replanLink(null, now)).toBe(null);
  });
});
