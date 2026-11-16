import { describe, expect, it } from "vite-plus/test";
import { olderRules } from "./older-route.fixtures.ts";
import {
  olderRouteSummary,
  removeOlderRouteOp,
  removeOlderRouteSentence,
  stagedRemovals,
} from "./older-route.ts";

const [old] = olderRules();
const unnamed = olderRules([
  { id: "old-2", name: "", origin: "legacy", station: { id: "gs-1", code: "INU", name: "Inuvik" } },
])[1];

describe("older route removal words (ux U79)", () => {
  it("stages the legacy_routing_rule delete for the row", () => {
    expect(removeOlderRouteOp("old-1")).toEqual({
      kind: "legacy_routing_rule",
      action: "delete",
      entity_id: "old-1",
    });
  });

  it("names the route in quotes, else by its station; drops a missing spacecraft name", () => {
    if (!old || !unnamed) throw new Error("fixture");
    expect(olderRouteSummary(old, "EARENDIL-389")).toBe(
      "Remove older route “qa-pre-routing-175358” · EARENDIL-389",
    );
    expect(olderRouteSummary(unnamed, "EARENDIL-389")).toBe(
      "Remove older route INU · EARENDIL-389",
    );
    expect(olderRouteSummary(old, null)).toBe("Remove older route “qa-pre-routing-175358”");
    expect(removeOlderRouteSentence(old, "EARENDIL-389")).toBe(
      "Stage removing “qa-pre-routing-175358”? EARENDIL-389 stops using it once the change set is applied.",
    );
  });

  it("finds no staged removal without an open set (the panel test reads a real one)", () => {
    expect(stagedRemovals(null).size).toBe(0);
    expect(stagedRemovals(undefined).size).toBe(0);
  });
});
