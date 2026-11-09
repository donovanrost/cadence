import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { passesReader, type Pass } from "./api.ts";
import { passGantt, passStatus } from "./gantt.ts";

const now = Date.parse("2026-11-09T02:00:00Z");
const pass = (id: string, overrides: Partial<Pass> = {}): Pass => ({
  id,
  kind: "contact",
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: "sc-312",
  spacecraft: { id: "sc-312", name: "EARENDIL-312", scid: 312 },
  station: { ref: "SVL", id: "gs-svl", code: "SVB", name: "Svalbard" },
  antenna: null,
  starts_at: "2026-11-09T02:30:00Z",
  ends_at: "2026-11-09T02:38:00Z",
  uplink_capable: null,
  source: { provider: "p", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  plan: null,
  ...overrides,
});

describe("passes", () => {
  it("decodes the read and rejects unknown states", () => {
    const body = {
      from: "2026-11-09T02:00:00Z",
      to: "2026-11-09T04:00:00Z",
      truncated: false,
      passes: [pass("a"), pass("b", { plan: { id: "contact_plan_1", version: 42 } })],
    };
    expect(decode(passesReader, body).ok).toBe(true);
    expect(decode(passesReader, { ...body, passes: [{ ...pass("a"), state: "maybe" }] }).ok).toBe(
      false,
    );
  });

  it("reads status from state, phase and time", () => {
    expect(passStatus(pass("a"), now)).toBe("scheduled");
    expect(passStatus(pass("b", { state: "active" }), now)).toBe("live");
    expect(passStatus(pass("c", { pass_phase: "pass" }), now)).toBe("live");
    expect(passStatus(pass("d", { ends_at: "2026-11-09T01:50:00Z" }), now)).toBe("done");
    expect(
      passGantt([pass("d", { ends_at: "2026-11-09T01:50:00Z" })], () => null, now).bars[0]?.kind,
    ).toBe("done");
    expect(passStatus(pass("e", { state: "rejected" }), now)).toBe("problem");
    expect(passStatus(pass("f", { state: "canceled" }), now)).toBe("canceled");
  });

  it("maps to station rows and spacecraft-numbered bars, skipping canceled", () => {
    const { rows, bars } = passGantt(
      [
        pass("a"),
        pass("b", { station: { ref: "XYZ", id: null, code: null, name: null } }),
        pass("c", { state: "canceled" }),
      ],
      () => ({ name: "EARENDIL-312", scid: 312 }),
      now,
    );
    expect(rows.map((r) => r.label)).toEqual(["SVB", "XYZ"]);
    expect(bars.map((b) => [b.label, b.kind])).toEqual([
      ["312", "scheduled"],
      ["312", "scheduled"],
    ]);
    expect(bars[0]?.description).toBe("EARENDIL-312 at Svalbard, scheduled (synthetic window)");
    // Without a fleet match, the row's own identity names it.
    const own = passGantt([pass("x")], () => null, now, null, "spacecraft");
    expect(own.rows[0]?.label).toBe("EARENDIL-312");
  });
});
