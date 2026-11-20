import { describe, expect, it } from "vite-plus/test";
import type { PlanPass } from "./api.ts";
import { booking, station } from "./fixtures.ts";
import { expiredRows, offerClock, unsentPasses } from "./offer-clock.ts";

const now = new Date("2026-11-13T01:00:00Z");
const svb = station({ ref: "svb-1", id: "gs_svb", code: "SVB-1", name: "Svalbard" });
const pass = (
  id: string,
  start: string,
  expires: string | null,
  b: PlanPass["booking"] = null,
): PlanPass => ({
  snapshot_id: id,
  spacecraft_id: "sc12",
  station: svb,
  starts_at: `2026-11-13T${start}:00Z`,
  ends_at: `2026-11-13T${start}:00Z`,
  synthetic: false,
  locked: false,
  expires_at: expires === null ? null : `2026-11-13T${expires}:00Z`,
  booking: b,
});
const ksat = { id: "p-ksat", name: "KSAT" };
type Plan = Parameters<typeof offerClock>[0];
const plan = (passes: PlanPass[], at: string, extra: Partial<Plan> = {}): Plan => ({
  state: "draft",
  passes,
  provider_freeze: {
    at: `2026-11-13T${at}:00Z`,
    provider: ksat,
    snapshot_id: passes[0]?.snapshot_id ?? null,
    by_provider: [],
  },
  ...extra,
});
const nameOf = () => ({ name: "EARENDIL-012", scid: 12 });

describe("K1 offer clock (ux)", () => {
  it("counts down to the next offer, names the provider and the pass", () => {
    const c = offerClock(
      plan([pass("s1", "17:00", "16:15"), pass("s2", "20:00", "19:00")], "16:15"),
      nameOf,
      now,
    );
    expect(c?.label).toBe("Next offer expires T−15:15:00 · KSAT");
    expect(c?.tone).toBe("readout");
    expect(c?.detail).toBe(
      "KSAT's offer for EARENDIL-012 · SVB-1 · 17:00Z expires at 16:15Z. Send before then, or that pass can't be booked.",
    );
    expect(c?.snapshotId).toBe("s1");
  });

  it("names a craft it can't read as 'Unknown spacecraft', never its id (#237, U25)", () => {
    const c = offerClock(plan([pass("s1", "17:00", "16:15")], "16:15"), () => null, now);
    expect(c?.passText).toBe("Unknown spacecraft · SVB-1 · 17:00Z");
  });

  it("never counts up from an expired offer: moves to the next live one and counts the lapsed", () => {
    const c = offerClock(
      plan(
        [pass("s1", "03:00", "00:30"), pass("s2", "03:20", "01:40"), pass("s3", "03:40", "01:50")],
        "00:30",
      ),
      nameOf,
      now,
    );
    expect(c?.label).toBe("Next offer expires T−00:40:00 · 1 expired");
    expect(c?.tone).toBe("caution");
    expect(c?.snapshotId).toBe("s2");
    expect(c?.more).toBe("1 more offer expires in the next hour.");
  });

  it("says how many lapsed, with no clock, when every unsent offer has", () => {
    const c = offerClock(
      plan([pass("s1", "03:00", "00:30"), pass("s2", "03:20", "00:40")], "00:30"),
      nameOf,
      now,
    );
    expect(c?.label).toBe("2 offers expired");
    expect(c?.tone).toBe("caution");
    expect(c?.tail).toBe(" expired at 00:30Z. That pass can't be booked; re-plan to replace it.");
  });

  it("is absent with nothing to send, and counts only unsent passes once executing", () => {
    expect(offerClock({ ...plan([], "01:00"), provider_freeze: null }, nameOf, now)).toBeNull();
    const executing = plan(
      [
        pass("s1", "03:00", "00:30", booking("confirmed", null)),
        pass("s2", "03:20", "02:00", booking("never_sent", null)),
      ],
      "02:00",
      { state: "executing" },
    );
    expect(unsentPasses(executing)?.map((p) => p.snapshot_id)).toEqual(["s2"]);
    expect(offerClock(executing, nameOf, now)?.label).toBe("Next offer expires T−01:00:00");
    expect(unsentPasses({ state: "executing", passes: [pass("s1", "03:00", "00:30")] })).toBeNull();
  });

  it("puts expired unsent offers in Demand in ux's words", () => {
    expect(
      expiredRows(
        { state: "draft", passes: [pass("s1", "03:00", "00:30"), pass("s2", "05:00", "04:00")] },
        now,
      ).map((r) => r.sentence),
    ).toEqual(["Expired · SVB-1 03:00Z: the offer lapsed at 00:30Z before it was sent."]);
  });
});
