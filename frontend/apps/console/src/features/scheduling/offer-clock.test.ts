import { describe, expect, it } from "vite-plus/test";
import { offerClock } from "./offer-clock.ts";

const now = new Date("2026-11-13T01:00:00Z");
const station = { ref: "svb-1", id: "gs_svb", code: "SVB-1", name: "Svalbard" };
const pass = (id: string, start: string, expires: string | null) => ({
  snapshot_id: id,
  spacecraft_id: "sc12",
  station,
  starts_at: `2026-11-13T${start}:00Z`,
  ends_at: `2026-11-13T${start}:00Z`,
  synthetic: false,
  locked: false,
  expires_at: expires === null ? null : `2026-11-13T${expires}:00Z`,
});
const ksat = { id: "p-ksat", name: "KSAT" };
const plan = (
  at: string,
  extra: Partial<Parameters<typeof offerClock>[0]> = {},
): Parameters<typeof offerClock>[0] => ({
  state: "draft",
  passes: [
    pass("s1", "03:00", "02:30"),
    pass("s2", "03:20", "01:20"),
    pass("s3", "03:40", "01:50"),
    pass("s4", "09:00", "08:30"),
  ],
  provider_freeze: { at, provider: ksat, snapshot_id: "s1", by_provider: [] },
  ...extra,
});
const nameOf = () => ({ name: "EARENDIL-012", scid: 12 });

describe("K1 offer clock (ux)", () => {
  it("names the provider, counts down, and says which pass and what happens", () => {
    const c = offerClock(plan("2026-11-13T16:15:51Z"), nameOf, now);
    expect(c?.label).toBe("Next offer expires T−15:15:51 · KSAT");
    expect(c?.tone).toBe("readout");
    expect(c?.detail).toBe(
      "KSAT's offer for EARENDIL-012 · SVB-1 · 03:00Z expires at 16:15Z. Send before then, or that pass can't be booked.",
    );
    expect(c?.lead + (c?.passText ?? "") + c?.tail).toBe(c?.detail);
    expect(c?.snapshotId).toBe("s1");
  });

  it("turns caution under an hour, counts the other offers expiring within it, and is absent with nothing to send", () => {
    const c = offerClock(plan("2026-11-13T01:10:00Z"), nameOf, now);
    expect(c?.tone).toBe("caution");
    expect(c?.more).toBe("2 more offers expire in the next hour.");
    expect(
      offerClock(plan("2026-11-13T01:10:00Z", { state: "executing" }), nameOf, now)?.more,
    ).toBeNull();
    expect(offerClock(plan("x", { provider_freeze: null }), nameOf, now)).toBeNull();
  });

  it("lists providers earliest first, and says an expired offer plainly", () => {
    const c = offerClock(
      plan("2026-11-13T00:57:00Z", {
        provider_freeze: {
          at: "2026-11-13T00:57:00Z",
          provider: ksat,
          snapshot_id: "s1",
          by_provider: [
            { provider: { id: "p-nl", name: "Northlight" }, at: "2026-11-13T19:02:10Z" },
            { provider: ksat, at: "2026-11-13T16:15:51Z" },
          ],
        },
      }),
      nameOf,
      now,
    );
    expect(c?.providers).toBe("KSAT T−15:15:51 · Northlight T−18:02:10");
    expect(c?.label).toBe("Offer expired T+00:03:00 · KSAT");
    expect(c?.tail).toBe(" expired at 00:57Z. That pass can't be booked.");
  });
});
