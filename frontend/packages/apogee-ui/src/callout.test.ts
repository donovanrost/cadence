import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApCallout from "./ApCallout.vue";

type Tone = "nominal" | "caution" | "crit" | "stale" | "off" | "info";

/** a11y B6 (#243): the role follows what happened; the tone only sets the default. */
describe("ApCallout role", () => {
  const roleOf = (tone: Tone, role?: "alert" | "status") =>
    mount(ApCallout, { props: { tone, role }, slots: { default: "x" } }).attributes("role");

  it("defaults by tone: crit is alert, everything else status", () => {
    expect(roleOf("crit")).toBe("alert");
    const others: readonly Tone[] = ["nominal", "caution", "stale", "off", "info"];
    for (const tone of others) expect(roleOf(tone)).toBe("status");
  });

  it("takes the caller's role over the tone's", () => {
    expect(roleOf("caution", "alert")).toBe("alert");
    expect(roleOf("crit", "status")).toBe("status");
  });
});
