import { describe, expect, it } from "vite-plus/test";
import { moveLine } from "./moves.ts";

const at = (code: string, starts_at: string) => ({
  snapshot_id: `${code}-${starts_at}`,
  spacecraft_id: "sc-4",
  station: { ref: code, id: null, code, name: null },
  starts_at,
  ends_at: starts_at,
});

describe("moveLine (ux)", () => {
  it("calls a same-station, same-start pass a re-booking, with no offset", () => {
    const same = at("KIR", "2026-11-10T00:54:00Z");
    expect(moveLine({ spacecraft_id: "sc-4", from: same, to: same, offset_s: 0 })).toEqual({
      route: "· KIR 00:54Z · same window, re-booked",
      offset: null,
    });
  });
  it("shows the route, and the offset only when it isn't zero", () => {
    const from = at("HBK", "2026-11-10T00:53:00Z");
    expect(
      moveLine({
        spacecraft_id: "sc-2",
        from,
        to: at("HAW", "2026-11-10T02:30:00Z"),
        offset_s: 5820,
      }),
    ).toEqual({ route: "HBK 00:53Z → HAW 02:30Z", offset: "+1h 37m" });
    expect(
      moveLine({ spacecraft_id: "sc-2", from, to: at("SVA", "2026-11-10T00:53:00Z"), offset_s: 0 })
        .offset,
    ).toBeNull();
  });
});
