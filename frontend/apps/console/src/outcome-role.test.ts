import { describe, expect, it } from "vite-plus/test";
import { outcomeRole } from "./outcome-role.ts";

describe("outcomeRole (a11y B6, #276)", () => {
  it("reads a success politely and alerts anything that went wrong", () => {
    expect(outcomeRole("nominal")).toBe("status");
    expect(outcomeRole("info")).toBe("status");
    expect(outcomeRole("caution")).toBe("alert");
    expect(outcomeRole("crit")).toBe("alert");
  });
});
