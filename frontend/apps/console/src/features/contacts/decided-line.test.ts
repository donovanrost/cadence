import { describe, expect, it } from "vite-plus/test";
import { decidedLine } from "./attention.ts";

/** U44 with U25: the signed-in person's own decision, never by their email. */
describe("decidedLine", () => {
  it("names the decider by display name, else drops the clause", () => {
    expect(decidedLine("Approved", "Mira K.", "06:52", "Fine.")).toBe(
      "Approved by Mira K. at 06:52: Fine.",
    );
    expect(decidedLine("Approved", null, "06:52", "Fine")).toBe("Approved at 06:52: Fine.");
    expect(decidedLine("Acknowledged", "  ", "06:52", "Seen")).toBe("Acknowledged at 06:52: Seen.");
  });
});
