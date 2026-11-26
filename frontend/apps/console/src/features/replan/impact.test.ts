import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { passesPageReader as passesReaderForTests } from "@/features/contacts/passes-api.ts";
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
  const read = (rows: unknown[]) => {
    const decoded = decode(passesReaderForTests, {
      from: "2026-11-10T00:00:00Z",
      to: "2026-11-11T00:00:00Z",
      counts: { total: 0, booked: 0, hand_started: 0, in_contact: 0, upcoming: 0, synthetic: 0 },
      passes: rows,
    });
    if (!decoded.ok) throw decoded.error;
    return decoded.value.passes;
  };
  it("follows the repair chain and skips lost bookings an applied repair replaced (qa #30)", () => {
    const rows = read([
      {
        ...pass("hbk", "canceled", "r1", "sc-2", "HBK"),
        replaced_by: { plan_id: "rep", reservation_id: "x" },
      },
      {
        ...pass("kir", "canceled", "r1", "sc-4", "KIR"),
        ended_by: { kind: "user", id: "u1", name: "QA Org Admin" },
      },
      {
        ...pass("haw", "failed", "rep", "sc-2", "HAW"),
        ended_by: { kind: "user", id: "u1", name: "Mira K." },
      },
      pass("other", "rejected", "plan-other-day", "sc-9", "SVL"),
    ]);
    const impact = impactOf(rows, { id: "r1", repair_of: null });
    expect(impact.rows.map((r) => [r.id, r.why])).toEqual([
      ["kir", "Canceled by QA Org Admin · at Simulator"],
      ["haw", "Marked not booked by Mira K."],
    ]);
  });
  it("drops a lost booking a single booking covered (domain #56: replaced_by.plan_id null)", () => {
    const rows = read([
      {
        ...pass("single", "canceled", "r1", "sc-4", "KIR"),
        replaced_by: { kind: "single_booking", plan_id: null, reservation_id: "res-9" },
      },
      pass("still", "canceled", "r1", "sc-5", "KIR"),
    ]);
    expect(impactOf(rows, { id: "r1", repair_of: null }).rows.map((r) => r.id)).toEqual(["still"]);
  });
  it("uses the server's chain when the plan carries one (api 22d83acd)", () => {
    const rows = read([
      pass("root", "canceled", "r0", "sc-1", "FAI"),
      pass("mid", "canceled", "r1", "sc-2", "FAI"),
      pass("off", "canceled", "elsewhere", "sc-3", "FAI"),
    ]);
    const plan = {
      id: "rep2",
      repair_of: { plan: { id: "r1" } },
      chain: [{ id: "r0" }, { id: "r1" }, { id: "rep2" }],
    };
    expect(impactOf(rows, plan).rows.map((r) => r.id)).toEqual(["root", "mid"]);
  });
  it("starts from the parent when opened on a repair, and names the provider only when it ended it", () => {
    const rows = read([
      {
        ...pass("a", "canceled", "r1", "sc-1", "FAI"),
        ended_by: { kind: "provider", id: "p1", name: "Northlight" },
      },
      pass("b", "canceled", "r1", "sc-3", "FAI"),
    ]);
    const impact = impactOf(rows, { id: "rep", repair_of: { plan: { id: "r1" } } });
    expect(impact.rows.map((r) => r.why)).toEqual([
      "Canceled by Northlight",
      "Canceled at Simulator",
    ]);
  });
  it("lists only this plan's lost bookings with a reason in words", () => {
    const decoded = decode(passesReaderForTests, {
      from: "2026-11-09T00:00:00Z",
      to: "2026-11-10T00:00:00Z",
      counts: { total: 0, booked: 0, hand_started: 0, in_contact: 0, upcoming: 0, synthetic: 0 },
      passes: [
        pass("a", "rejected", "plan-41", "sc-1", "SVL"),
        pass("b", "confirmed", "plan-41", "sc-2", "FAI"),
        pass("c", "failed", "plan-41", "sc-1", "FAI"),
        pass("d", "rejected", "plan-40", "sc-3", "SVL"),
      ],
    });
    if (!decoded.ok) throw decoded.error;
    const impact = impactOf(decoded.value.passes, { id: "plan-41", repair_of: null });
    expect(impact.passes).toBe(2);
    expect(impact.spacecraft).toBe(1);
    expect(impact.stations).toEqual(["FAI", "SVL"]);
    expect(impact.rows.map((r) => r.why)).toEqual([
      "Rejected by Simulator",
      "Booking with Simulator failed",
    ]);
  });

  it("reads a lost pass with no spacecraft name as Unknown spacecraft, never its id (#237)", () => {
    const rows = read([
      {
        ...pass("kir", "canceled", "r1", "sc-4", "KIR"),
        spacecraft: { id: "sc-4", name: null, scid: 1 },
      },
    ]);
    expect(impactOf(rows, { id: "r1", repair_of: null }).rows.map((r) => r.spacecraft)).toEqual([
      "Unknown spacecraft",
    ]);
  });
});
