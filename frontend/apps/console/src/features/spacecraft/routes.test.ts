import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { detailReader, type RoutingRule } from "./detail.ts";
import {
  actionRows,
  removeRouteOp,
  routeChangeSummary,
  routeSummary,
  routeTag,
  stationWord,
} from "./routes.ts";

const base = {
  id: "r-1",
  name: "INU · EARENDIL-389",
  purpose: null,
  direction: "inbound",
  role: "primary",
  enabled: true,
  active: true,
  transport: { id: "t-1", name: "INU S-band" },
};
function rules(rows: Record<string, unknown>[]): readonly RoutingRule[] {
  const result = decode(detailReader, {
    spacecraft: {
      id: "sc-1",
      name: "EARENDIL-389",
      scid: 389,
      norad_id: null,
      plane: null,
      slot: null,
      last_received_at: null,
    },
    profile: null,
    configuration: null,
    telemetry: { status: "never", last_received_at: null },
    routing_rules: rows.map((r) => ({ ...base, ...r })),
    readiness: { ready: true, checks: [] },
  });
  if (!result.ok) throw new Error(result.error.message);
  return result.value.routing_rules;
}
const inu = { id: "gs-1", code: "INU", name: "Inuvik" };

describe("U79 route tags", () => {
  it("tags by origin: profile, the spacecraft's own, and legacy with its note and reason", () => {
    const [profile, own, legacy] = rules([
      { id: "a", origin: "profile", route_id: null, station: inu },
      { id: "b", origin: "spacecraft", route_id: "spacecraft_route_1", station: inu },
      { id: "c", origin: "legacy", route_id: null, station: null },
    ]);
    expect(profile && routeTag(profile)).toEqual({
      label: "From profile",
      note: null,
      reason: null,
    });
    expect(own && routeTag(own)).toEqual({
      label: "This spacecraft only",
      note: null,
      reason: null,
    });
    expect(legacy && routeTag(legacy)).toEqual({
      label: "This spacecraft only",
      note: "Set up on the old routing page.",
      reason: "Older routes can't be edited here until they're converted.",
    });
  });

  it("reads an older server (no origin) and a new origin without failing, untagged", () => {
    const [older, newer] = rules([{ id: "a" }, { id: "b", origin: "borrowed" }]);
    expect(older && routeTag(older)).toBeNull();
    expect(newer && routeTag(newer)).toBeNull();
  });
});

describe("U79 Edit / Remove… rows", () => {
  it("puts one pair of actions on each extra route's first leg, never on profile or legacy rows", () => {
    const rows = rules([
      { id: "leg-down", origin: "spacecraft", route_id: "route-1", direction: "inbound" },
      { id: "leg-up", origin: "spacecraft", route_id: "route-1", direction: "outbound" },
      { id: "prof", origin: "profile", route_id: null },
      { id: "old", origin: "legacy", route_id: null },
      { id: "other", origin: "spacecraft", route_id: "route-2" },
    ]);
    expect([...actionRows(rows)]).toEqual([
      ["leg-down", "route-1"],
      ["other", "route-2"],
    ]);
  });

  it("stages a removal as the kind's delete", () => {
    expect(removeRouteOp("route-1")).toEqual({
      kind: "spacecraft_route",
      action: "delete",
      entity_id: "route-1",
    });
  });
});

describe("U79 summary words (names, never ids)", () => {
  it("names the station by code, else name, and the spacecraft", () => {
    expect(routeSummary("Add", stationWord(inu), "EARENDIL-389")).toBe(
      "Add extra route INU · EARENDIL-389",
    );
    expect(
      routeSummary("Remove", stationWord({ code: null, name: "Inuvik" }), "EARENDIL-389"),
    ).toBe("Remove extra route Inuvik · EARENDIL-389");
    expect(stationWord(null)).toBe("a removed station");
    expect(stationWord({ code: "", name: null })).toBe("a removed station");
  });
});

describe("U79 Edit / Remove lines (ux: named routes quoted)", () => {
  it("quotes a named route and adds the spacecraft", () => {
    expect(routeChangeSummary("Edit", "Fairbanks (Demo) — uplink", "FBK", "EARENDIL-389")).toBe(
      "Edit extra route “Fairbanks (Demo) — uplink” · EARENDIL-389",
    );
  });
  it("reads the default name, or none, in the station form", () => {
    expect(routeChangeSummary("Remove", "FBK · EARENDIL-389", "FBK", "EARENDIL-389")).toBe(
      "Remove extra route FBK · EARENDIL-389",
    );
    expect(routeChangeSummary("Edit", null, "INU", "EARENDIL-389")).toBe(
      "Edit extra route INU · EARENDIL-389",
    );
  });
  it("doesn't repeat a spacecraft the name already holds", () => {
    expect(routeChangeSummary("Remove", "EARENDIL-389 recovery", "INU", "EARENDIL-389")).toBe(
      "Remove extra route “EARENDIL-389 recovery”",
    );
  });
});
