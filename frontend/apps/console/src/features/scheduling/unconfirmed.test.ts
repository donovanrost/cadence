import { describe, expect, it } from "vite-plus/test";
import type { PlanDetail } from "./api.ts";
import { planHeaderTail } from "./plan-primary.ts";
import { shortWhen, unconfirmedView } from "./unconfirmed.ts";
import { station } from "./fixtures.ts";

const pass = (id: string, sc: string, start: string) => ({
  snapshot_id: id,
  spacecraft_id: sc,
  station: station({ ref: "KIR", id: "gs-kir", code: "KIR", name: "Kiruna" }),
  starts_at: start,
  ends_at: start,
  synthetic: true,
  locked: false,
  expires_at: null,
  booking: null,
  listener_overlap: undefined,
});
const plan = (state: PlanDetail["state"], providers: readonly string[]): PlanDetail => ({
  id: "plan_1",
  version: 41,
  state,
  window: { from: null, to: null },
  author: null,
  counts: { passes: 40, minutes: 320, conflicts: 0, unsatisfied: 0 },
  ready_to_approve: false,
  updated_at: "2026-11-10T10:00:00Z",
  created_at: null,
  superseded: null,
  repair_of: null,
  superseded_by: null,
  latest_version: undefined,
  repair: undefined,
  approval_setting: undefined,
  expired: undefined,
  expired_digest: undefined,
  next_expiry_at: undefined,
  passes: [
    pass("a", "sc-1", "2026-11-10T09:00:00Z"),
    pass("b", "sc-2", "2026-11-10T03:00:00Z"),
    pass("c", "sc-3", "2026-11-10T05:00:00Z"),
  ],
  demand: { rule_met: 3, rule_total: 3, spacecraft: [], rules: [] },
  unmet: [],
  conflicts: [],
  at_risk: [],
  chain: null,
  execution: null,
  provider_freeze: null,
  approval: null,
  submission: null,
  previous_round: null,
  chain_head: null,
  unconfirmed: {
    window_ms: 600_000,
    booked: 36,
    passes: providers.map((name, i) => ({
      snapshot_id: ["a", "b"][i] ?? "a",
      provider: { id: `prov-${name}`, name },
      sent_at: "2026-11-10T00:00:00Z",
    })),
  },
});
const names = (id: string | null) => (id ? { name: `EARENDIL-${id.slice(3)}`, scid: 1 } : null);

describe("U30 unconfirmed", () => {
  it("words a pass with no provider recorded yet (api drift sweep 11-13)", () => {
    const p = plan("unconfirmed", ["Northlight"]);
    const first = p.unconfirmed?.passes[0];
    if (!p.unconfirmed || !first) throw new Error("fixture");
    const withNull: PlanDetail = {
      ...p,
      unconfirmed: { ...p.unconfirmed, passes: [{ ...first, provider: null }] },
    };
    expect(unconfirmedView(withNull, names, "2026-11-10")?.headline).toContain(
      "an unnamed provider hasn't confirmed",
    );
  });

  it("names the one provider, the window, and lists passes soonest first", () => {
    const v = unconfirmedView(
      plan("unconfirmed", ["Northlight", "Northlight"]),
      names,
      "2026-11-10",
    );
    expect(v?.headline).toBe(
      "Northlight hasn't confirmed 2 bookings after 10 min. They may or may not be booked, so Cadence won't send them again. Check them with Northlight.",
    );
    expect(v?.passes.map((r) => r.text)).toEqual([
      "EARENDIL-2 · KIR · 03:00Z",
      "EARENDIL-1 · KIR · 09:00Z",
    ]);
  });
  it("names a craft it can't read as 'Unknown spacecraft', never its id (#237, U25)", () => {
    const v = unconfirmedView(plan("unconfirmed", ["Northlight"]), () => null, "2026-11-10");
    expect(v?.passes.map((r) => r.text)).toEqual(["Unknown spacecraft · KIR · 09:00Z"]);
  });

  it("splits by provider when there are several", () => {
    expect(
      unconfirmedView(plan("unconfirmed", ["Northlight", "KSAT"]), names, "2026-11-10")?.headline,
    ).toContain("Providers haven't confirmed 2 bookings (Northlight 1, KSAT 1) after 10 min.");
  });
  it("header: booked + unconfirmed on the state, a suffix on any other state", () => {
    expect(planHeaderTail(plan("unconfirmed", ["Northlight"]))).toBe("36 booked · 1 unconfirmed");
    expect(planHeaderTail(plan("partially_reserved", ["Northlight"]))).toBe(
      "36 of 40 booked · 1 unconfirmed",
    );
    expect(planHeaderTail({ ...plan("reserved", []), unconfirmed: null })).toBe("booked");
  });
});

describe("shortWhen (design language §4)", () => {
  it("drops the date today and keeps MM-DD otherwise", () => {
    expect(shortWhen("2026-11-15T03:00:00Z", "2026-11-15")).toBe("03:00Z");
    expect(shortWhen("2026-11-15T03:00:00Z", "2026-11-14")).toBe("11-15 03:00Z");
  });
});
