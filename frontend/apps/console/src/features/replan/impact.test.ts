import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { passesReader as passesReaderForTests } from "@/features/contacts/api.ts";
import { impactOf } from "./impact.ts";

const pass = (id: string, state: string, planId: string | null, sc: string, station: string) => ({
  id,
  kind: "contact",
  state,
  pass_phase: null,
  delivery_state: null,
  spacecraft_id: sc,
  spacecraft: { id: sc, name: sc.toUpperCase(), scid: 1 },
  station: { ref: station, id: null, code: station, name: null },
  antenna: null,
  starts_at: "2026-11-09T03:12:00Z",
  ends_at: "2026-11-09T03:22:00Z",
  uplink_capable: null,
  source: { provider: "p1", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  cost: null,
  plan: planId ? { id: planId, version: 41 } : null,
  reservation_id: id,
  scheduled_contact_id: null,
});

describe("impactOf", () => {
  it("lists only this plan's lost bookings with a reason in words", () => {
    const decoded = decode(passesReaderForTests, {
      from: "2026-11-09T00:00:00Z",
      to: "2026-11-10T00:00:00Z",
      truncated: false,
      passes: [
        pass("a", "rejected", "plan-41", "sc-1", "SVL"),
        pass("b", "confirmed", "plan-41", "sc-2", "FAI"),
        pass("c", "failed", "plan-41", "sc-1", "FAI"),
        pass("d", "rejected", "plan-40", "sc-3", "SVL"),
      ],
    });
    if (!decoded.ok) throw decoded.error;
    const impact = impactOf(decoded.value.passes, "plan-41", false);
    expect(impact.passes).toBe(2);
    expect(impact.spacecraft).toBe(1);
    expect(impact.stations).toEqual(["FAI", "SVL"]);
    expect(impact.rows.map((r) => r.why)).toEqual([
      "Rejected by Simulator",
      "Booking with Simulator failed",
    ]);
  });
});
