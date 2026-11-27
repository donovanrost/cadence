import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { unshownWords } from "@/features/now/unshown.ts";
import { passesPageReader } from "./passes-api.ts";

const pass = (id: string, o: Record<string, unknown> = {}) => ({
  id,
  kind: "contact",
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: "spacecraft-earendil-003",
  spacecraft: { id: "spacecraft-earendil-003", name: "EARENDIL-003", scid: 3 },
  station: { ref: "brs", id: null, code: "BRS", name: "Brisbane" },
  antenna: null,
  starts_at: "2026-11-17T14:00:00Z",
  ends_at: "2026-11-17T14:10:00Z",
  uplink_capable: true,
  source: { provider: "p-1", provider_name: "Northlight", synthetic: false },
  max_elevation_deg: null,
  elevation_source: null,
  predicted_pass_id: null,
  plan: null,
  attention: null,
  ...o,
});
const read = (passes: unknown[]) =>
  decode(passesPageReader, {
    from: "2026-11-17T00:00:00Z",
    to: "2026-11-18T00:00:00Z",
    counts: { total: 0, booked: 0, hand_started: 0, in_contact: 0, upcoming: 0, synthetic: 0 },
    passes,
  });

beforeEach(() => vi.spyOn(console, "warn").mockImplementation(() => {}));
afterEach(() => vi.restoreAllMocks());

/** ux U86 follow-up: one pass the console can't read no longer blanks the schedule. */
describe("the passes list, read pass by pass (U86)", () => {
  it("keeps the readable passes and counts the rest by kind and id", () => {
    const r = read([pass("pass-1"), pass("pass-2", { state: 7 }), pass("pass-3")]);
    expect(r.ok && r.value.passes.map((p) => p.id)).toEqual(["pass-1", "pass-3"]);
    expect(r.ok && r.value.unshown).toEqual([{ kind: ["contact"], id: "pass-2" }]);
  });

  it("the list itself stays strict, and nothing dropped reads empty", () => {
    expect(
      decode(passesPageReader, {
        from: "x",
        to: "y",
        counts: { total: 0, booked: 0, hand_started: 0, in_contact: 0, upcoming: 0, synthetic: 0 },
        passes: [],
      }).ok,
    ).toBe(false);
    const r = read([pass("pass-1")]);
    expect(r.ok && r.value.unshown).toEqual([]);
  });

  it("the line names passes", () => {
    expect(unshownWords(1, "pass")).toBe(
      "This console can't show 1 pass. Reload to try again. If it's still missing, tell the team that runs Cadence for you.",
    );
    expect(unshownWords(3, "pass")).toContain("This console can't show 3 passes.");
    expect(unshownWords(2)).toContain("2 items");
  });
});
