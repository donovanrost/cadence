import { describe, expect, it } from "vite-plus/test";
import { rowName } from "./rowName.ts";

describe("rowName (U107)", () => {
  it("label without its ellipsis, then the title with middle dots read as commas", () => {
    expect(rowName("Discard…", "EARENDIL-001 · SNTG 00:13Z pass · 3 connections refused", 0)).toBe(
      "Discard, EARENDIL-001, SNTG 00:13Z pass, 3 connections refused",
    );
    expect(
      rowName("Book 40 passes", "Plan for 11-16 is approved but booking hasn't started", 4),
    ).toBe("Book 40 passes, Plan for 11-16 is approved but booking hasn't started");
  });
  it("a row with no title uses its position", () => {
    expect(rowName("Discard…", "", 2)).toBe("Discard, row 3");
  });
});
