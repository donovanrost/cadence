import { describe, expect, it } from "vite-plus/test";
import { isPlanSuperseded, planErrorText } from "./errors.ts";

describe("planErrorText", () => {
  it("names known refusals in plain words and falls back for the rest", () => {
    expect(
      planErrorText({
        kind: "invalid",
        code: "fleet_planning_requirement_not_active",
        message: "x",
        details: null,
      }),
    ).toContain("Contact rules aren't active for this day");
    expect(
      planErrorText({ kind: "conflict", code: "plan_superseded", message: "x", details: null }),
    ).toContain("superseded and can't be submitted");
    expect(
      planErrorText({
        kind: "invalid",
        code: "something_new",
        message: "Server says no.",
        details: null,
      }),
    ).toBe("Server says no.");
  });
});

describe("isPlanSuperseded", () => {
  it("is true only for a 409 plan_superseded", () => {
    expect(
      isPlanSuperseded({ kind: "conflict", code: "plan_superseded", message: "x", details: null }),
    ).toBe(true);
    expect(
      isPlanSuperseded({ kind: "conflict", code: "plan_changed", message: "x", details: null }),
    ).toBe(false);
  });
});
