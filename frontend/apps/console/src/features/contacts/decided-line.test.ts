import { describe, expect, it } from "vite-plus/test";
import { decidedLine } from "./attention.ts";

/** U44 with U25: the signed-in person's own decision, never by their email. */
describe("decidedLine", () => {
  it("names the decider by display name, else 'you' (ux on #605)", () => {
    expect(decidedLine("Approved", "Mira K.", "06:52", "Fine.")).toBe(
      "Approved by Mira K. at 06:52: Fine.",
    );
    expect(decidedLine("Approved", null, "06:52", "Fine")).toBe("Approved by you at 06:52: Fine.");
    expect(decidedLine("Acknowledged", "  ", "06:52", "Seen")).toBe(
      "Acknowledged by you at 06:52: Seen.",
    );
  });
});
