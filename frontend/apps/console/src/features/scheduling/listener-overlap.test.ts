import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { passReader } from "@/features/contacts/api.ts";
import { searchReader } from "@/features/contacts/singleBookings.ts";
import { planDetailReader } from "./api.ts";
import SelectedPanel from "./SelectedPanel.vue";

/** U58 (b), #361: every read takes #640's listener_overlap, and reads as today without it. */
const overlap = {
  with: {
    spacecraft: { id: "sc-6", name: "EARENDIL-006" },
    station: { code: "SNTG", name: "Santiago" },
    starts_at: "2026-11-21T00:05:00Z",
    state: "planned",
  },
  seconds: 26,
  loses: "this",
  direction: "downlink",
  listener: { host: "0.0.0.0", port: 52001 },
  count: 1,
};
const planPass = (listener_overlap?: unknown) => ({
  snapshot_id: "snap-1",
  spacecraft_id: "sc-1",
  station: { ref: "sntg", id: "gs-1", code: "SNTG", name: "Santiago" },
  starts_at: "2026-11-21T00:13:00Z",
  ends_at: "2026-11-21T00:21:00Z",
  synthetic: false,
  locked: false,
  ...(listener_overlap === undefined ? {} : { listener_overlap }),
});
const detail = (pass: unknown) =>
  planDetailReader({
    id: "p",
    version: 1,
    state: "draft",
    window: { from: null, to: null },
    author: null,
    counts: { passes: 1, minutes: 8, conflicts: 0, unsatisfied: 0 },
    ready_to_approve: false,
    updated_at: "2026-11-20T10:00:00Z",
    passes: [pass],
    demand: { rule_met: 0, rule_total: 0, spacecraft: [], rules: [] },
    unmet: [],
    conflicts: [],
  });
const bookedPass = (listener_overlap?: unknown) =>
  decode(passReader, {
    id: "pass-1",
    kind: "contact",
    state: "confirmed",
    pass_phase: "scheduled",
    delivery_state: "pending",
    spacecraft_id: "spacecraft-earendil-001",
    spacecraft: { id: "spacecraft-earendil-001", name: "EARENDIL-001", scid: 1 },
    station: { ref: "sntg", id: null, code: "SNTG", name: "Santiago" },
    antenna: null,
    starts_at: "2026-11-21T00:13:00Z",
    ends_at: "2026-11-21T00:21:00Z",
    uplink_capable: true,
    source: { provider: "p-1", provider_name: "Northlight", synthetic: false },
    max_elevation_deg: null,
    plan: null,
    ...(listener_overlap === undefined ? {} : { listener_overlap }),
  });
const offers = (listener_overlap?: unknown) =>
  decode(searchReader, {
    spacecraft: { id: "sc-1", name: "EARENDIL-001", scid: 1 },
    window: { from: "2026-11-21T00:00:00Z", to: "2026-11-21T06:00:00Z" },
    offers: [
      {
        id: "o-1",
        token: "t",
        expires_at: "2026-11-21T00:10:00Z",
        starts_at: "2026-11-21T00:13:00Z",
        ends_at: "2026-11-21T00:21:00Z",
        station: { ref: "sntg", id: null, code: "SNTG", name: "Santiago" },
        antenna: null,
        provider: { id: "p-1", name: "Northlight" },
        availability: "available",
        uplink_capable: false,
        synthetic: false,
        cost: null,
        overlaps: null,
        ...(listener_overlap === undefined ? {} : { listener_overlap }),
      },
    ],
    hidden: { no_uplink_route: 0 },
    not_ready: [],
    truncated: false,
  });

describe("listener_overlap on the three reads (#361)", () => {
  it("the plan's passes: read with it, and as today without it", () => {
    expect(detail(planPass(overlap)).passes[0]?.listener_overlap?.seconds).toBe(26);
    expect(detail(planPass()).passes[0]?.listener_overlap).toBeUndefined();
    expect(detail(planPass(null)).passes[0]?.listener_overlap).toBeNull();
  });

  it("booked passes on Contacts", () => {
    const r = bookedPass(overlap);
    expect(r.ok && r.value.listener_overlap?.loses).toBe("this");
    const today = bookedPass();
    expect(today.ok && today.value.listener_overlap).toBeUndefined();
  });

  it("Book a pass offers", () => {
    const r = offers(overlap);
    expect(r.ok && r.value.offers[0]?.listener_overlap?.with.state).toBe("planned");
    const today = offers();
    expect(today.ok && today.value.offers[0]?.listener_overlap).toBeUndefined();
  });

  it("the plan's selected pass shows the tag and sentence", () => {
    const w = mount(SelectedPanel, {
      props: {
        plan: detail(planPass(overlap)),
        selected: "snap-1",
        focused: null,
        alternatives: { status: "loading" },
        nameOf: () => ({ name: "EARENDIL-001", scid: 1 }),
        editable: false,
        busy: false,
        hits: { blocking: [], atRisk: [] },
      },
    });
    expect(w.get("[data-listener-overlap]").text()).toContain(
      "Overlaps EARENDIL-006's SNTG 00:05Z pass by 26 s.",
    );
    expect(w.text()).toContain("Listener overlap");
  });
});
