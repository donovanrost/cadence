import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import OutcomeCallout from "./OutcomeCallout.vue";
import { outcomeRole } from "./outcome-role.ts";

describe("outcomeRole (a11y B6, #276)", () => {
  it("reads a success politely and alerts anything that went wrong", () => {
    expect(outcomeRole("nominal")).toBe("status");
    expect(outcomeRole("info")).toBe("status");
    expect(outcomeRole("caution")).toBe("alert");
    expect(outcomeRole("crit")).toBe("alert");
  });
});

describe("OutcomeCallout", () => {
  it("shows the outcome's words with its tone's role", () => {
    const role = (tone: "nominal" | "caution") =>
      mount(OutcomeCallout, { props: { outcome: { tone, text: "Approved." } } }).attributes("role");
    expect(role("nominal")).toBe("status");
    expect(role("caution")).toBe("alert");
  });
});
