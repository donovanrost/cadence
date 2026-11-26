import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { passesPageReader } from "@/features/contacts/passes-api.ts";
import { coveredLine, type CoveredPass } from "./covered.ts";

const covered: CoveredPass = {
  snapshot_id: "snap-1",
  spacecraft_id: "sc-4",
  station: { ref: "KIR", id: null, code: "KIR", name: null },
  starts_at: "2026-11-10T00:54:00Z",
  ends_at: "2026-11-10T01:02:00Z",
  covered_by: "provider_reservation_single",
};
const single = (starts_at: string) => {
  const r = decode(passesPageReader, {
    from: "2026-11-10T00:00:00Z",
    to: "2026-11-11T00:00:00Z",
    counts: { total: 0, booked: 0, hand_started: 0, in_contact: 0, upcoming: 0, synthetic: 0 },
    passes: [
      {
        id: "provider_reservation_single",
        kind: "contact",
        state: "confirmed",
        pass_phase: null,
        delivery_state: null,
        spacecraft_id: "sc-4",
        spacecraft: null,
        station: { ref: "KIR", id: null, code: "KIR", name: null },
        antenna: null,
        starts_at,
        ends_at: starts_at,
        uplink_capable: null,
        source: { provider: "p", provider_name: "Simulator", synthetic: true },
        max_elevation_deg: null,
        plan: null,
      },
    ],
  });
  if (!r.ok) throw r.error;
  return r.value.passes;
};

describe("coveredLine (domain #56, ux)", () => {
  it("names the covering separate booking, with the date only when it isn't today", () => {
    expect(coveredLine(covered, single("2026-11-10T01:10:00Z"), "EARENDIL-004", "2026-11-10")).toBe(
      "EARENDIL-004 · KIR 00:54Z · covered by a separate booking · KIR 01:10Z",
    );
    expect(coveredLine(covered, single("2026-11-10T01:10:00Z"), "EARENDIL-004", "2026-11-09")).toBe(
      "EARENDIL-004 · KIR 11-10 00:54Z · covered by a separate booking · KIR 11-10 01:10Z",
    );
  });
  it("doesn't invent the covering booking when the read doesn't have it (U20)", () => {
    expect(coveredLine(covered, [], "EARENDIL-004", "2026-11-10")).toBe(
      "EARENDIL-004 · KIR 00:54Z · covered by a separate booking",
    );
  });
});
