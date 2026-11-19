import { describe, expect, it } from "vite-plus/test";
import { generateRows } from "./batch.ts";
import { noradList } from "./draft.ts";
import { parsePattern } from "./naming.ts";
import { routingSummary } from "./routing.ts";

describe("NORAD ids on the profile path (AddSpacecraft.md step 02)", () => {
  it("reads empty as add later, else one per spacecraft in order", () => {
    expect(noradList("", 3)).toEqual({ ok: true, ids: [null, null, null] });
    expect(noradList("58001, 58002 58003", 3)).toEqual({ ok: true, ids: [58001, 58002, 58003] });
  });
  it("says what's wrong", () => {
    const short = noradList("58001,58002", 3);
    expect(!short.ok && short.message).toBe(
      "Enter 3 NORAD ids, one per spacecraft (you entered 2), or leave it empty.",
    );
    expect(noradList("58001,x,58003", 3)).toMatchObject({
      ok: false,
      message: "“x” isn't a NORAD id.",
    });
    expect(noradList("58001,58001", 2)).toMatchObject({
      ok: false,
      message: "NORAD id 58001 is listed twice.",
    });
  });
  it("puts them on the generated rows", () => {
    const p = parsePattern("EARENDIL-{scid}");
    if (!p.ok) throw new Error("fixture");
    expect(generateRows(p.pattern, 2, 10, null, [58001, null]).map((r) => r.norad)).toEqual([
      58001,
      null,
    ]);
  });
});

describe("step 03 routing summary", () => {
  const rule = (label: string, stations: number, legs: number, enabled = true) => ({
    id: label,
    label,
    name_template: "{sc}",
    enabled,
    stations: Array.from({ length: stations }, (_, i) => ({
      id: `gs${i}`,
      code: null,
      name: `S${i}`,
      transport_id: null,
    })),
    legs: Array.from({ length: legs }, () => ({
      direction: "downlink" as const,
      role: "primary" as const,
    })),
    route_count: 0,
    samples: [],
  });
  const detail = (
    rules: ReturnType<typeof rule>[],
    model: "profile" | "per_spacecraft" = "profile",
  ) => ({ rules, routing_model: model });
  it("counts stations × legs per enabled rule, and the batch total", () => {
    const s = routingSummary(
      detail([rule("Block 2 · all stations", 3, 2), rule("Off", 5, 1, false)]),
      50,
    );
    expect(s.lines).toEqual(["Rule Block 2 · all stations generates 6 routes per spacecraft"]);
    expect(s.total).toBe("300 routes for 50 spacecraft");
  });
  it("says when the profile gives no routes", () => {
    expect(routingSummary(detail([]), 5).kind).toBe("none");
    expect(routingSummary(detail([rule("x", 1, 1)], "per_spacecraft"), 5).kind).toBe(
      "per_spacecraft",
    );
  });
});
