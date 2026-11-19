import { describe, expect, it } from "vite-plus/test";
import type { ContactMarker } from "./chart-markers.ts";
import { chained, contactTitle, mergedSpans, uncovered } from "./chart-events.ts";

describe("contact tints (qa's overlay look)", () => {
  it("merges overlapping or touching passes into one tint, so 5% washes never stack", () => {
    expect(
      mergedSpans([
        { left: 300, width: 50 },
        { left: 10, width: 40 },
        { left: 30, width: 40 },
        { left: 70, width: 10 },
      ]),
    ).toEqual([
      { left: 10, width: 70 },
      { left: 300, width: 50 },
    ]);
  });
  it("keeps a pass inside a longer one as the longer one", () => {
    expect(
      mergedSpans([
        { left: 0, width: 100 },
        { left: 20, width: 10 },
      ]),
    ).toEqual([{ left: 0, width: 100 }]);
  });
});

describe("mission event marks", () => {
  const at = (left: number, id: string) => ({
    left,
    marker: { marker_id: id },
  });
  it("chains a dense run (a once-a-second event stream) into one mark", () => {
    const runs = chained([at(10, "a"), at(14, "b"), at(18, "c"), at(22, "d"), at(40, "e")], 6);
    expect(runs.map((r) => [r.left, r.markers.length])).toEqual([
      [10, 4],
      [40, 1],
    ]);
  });
});

describe("booked vs flown (ux 88b7e6ae7)", () => {
  const flown = [{ left: 100, width: 50 }];
  it("leaves nothing of a booking the pass covers", () => {
    expect(uncovered({ left: 100, width: 50 }, flown)).toEqual([]);
  });
  it("keeps the late-start and early-LOS parts, dashed only on the booking's own ends", () => {
    expect(uncovered({ left: 90, width: 70 }, flown)).toEqual([
      { left: 90, width: 10, open: { left: true, right: false } },
      { left: 150, width: 10, open: { left: false, right: true } },
    ]);
  });
  it("keeps a booking with no pass whole", () => {
    expect(uncovered({ left: 300, width: 40 }, flown)).toEqual([
      { left: 300, width: 40, open: { left: true, right: true } },
    ]);
  });
});

describe("a contact that didn't start (ux, Overlays; domain's started/close_reason)", () => {
  const contact = (over: Partial<ContactMarker> = {}): ContactMarker => ({
    marker_type: "contact_interval",
    marker_id: "c-1",
    link_id: "c-1",
    starts_at_ms: 1_000,
    ends_at_ms: 2_000,
    label: "NL-ZKG",
    status: "stopped",
    station: "FAI",
    kind: "realized_contact",
    started: false,
    close_reason: "window_ended",
    ...over,
  });
  it("says why it didn't start, in pass or contact words", () => {
    expect(contactTitle(contact(), false)).toBe("FAI pass · didn't start: its window ended first");
    expect(contactTitle(contact({ close_reason: "hand_start_expired" }), false)).toBe(
      "FAI contact · didn't start: the hand start expired",
    );
    expect(contactTitle(contact({ close_reason: "unrecognized" }), false)).toBe(
      "FAI pass · didn't start",
    );
  });
  it("keeps the flown and booked words otherwise", () => {
    expect(contactTitle(contact({ started: true, status: "completed" }), true)).toBe(
      "Pass · FAI · completed",
    );
    expect(contactTitle(contact({ kind: "scheduled_contact", started: null }), false)).toBe(
      "Booked pass · FAI · stopped",
    );
  });
});
