import { describe, expect, it } from "vite-plus/test";
import { craftLabel } from "./names.ts";

/** #237 (U25): the scheduling screens name a craft, or say they can't, never with its id. */
describe("craftLabel", () => {
  it("names a craft, else 'Unknown spacecraft'", () => {
    expect(craftLabel({ name: "EARENDIL-012", scid: 12 })).toBe("EARENDIL-012");
    expect(craftLabel(null)).toBe("Unknown spacecraft");
    expect(craftLabel({ name: "  ", scid: 12 })).toBe("Unknown spacecraft");
  });
});
