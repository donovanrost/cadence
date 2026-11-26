import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import LimitsNotice from "./LimitsNotice.vue";
import RuleBlock from "./RuleBlock.vue";
import RuleLegs from "./RuleLegs.vue";
import { checkFallback } from "./rulesDraft.ts";

/** #313 (mms-ux's audit follow-ups): the profile rule editor's Check fallback and leg names (B7). */
describe("Check's non-field failures read as a dry run (mms-ux on #323)", () => {
  const RETRY = "A check changes nothing, so try again.";
  it("never says it isn't clear whether anything changed", () => {
    const dropped: ApiError = { kind: "unavailable", status: 0, message: "x" };
    const unreadable: ApiError = { kind: "malformed", message: "x" };
    const failed: ApiError = { kind: "unavailable", status: 500, message: "x" };
    const refused: ApiError = { kind: "forbidden", code: "forbidden", message: "No." };
    expect(checkFallback(dropped)).toBe(`Not checked: the connection dropped. ${RETRY}`);
    expect(checkFallback(unreadable)).toBe(
      `Not checked: the server's reply wasn't understood. ${RETRY}`,
    );
    expect(checkFallback(failed)).toBe(`Not checked: Cadence couldn't run the check. ${RETRY}`);
    // A 403 isn't retried: it says who can (fe-ops, #432).
    expect(checkFallback(refused)).toBe(
      "Not checked: you can't change this profile's routing. Mission admins and organization admins can.",
    );
  });
});

describe("a rule's legs are named groups (a11y B7)", () => {
  it("groups each leg as 'Leg N' and names its remove button 'Remove leg N'", () => {
    const w = mount(RuleLegs, {
      props: {
        modelValue: [
          { direction: "downlink", role: "primary" },
          { direction: "uplink", role: "primary" },
        ],
      },
    });
    expect(w.findAll("legend").map((l) => l.text())).toEqual(["Leg 1", "Leg 2"]);
    expect(w.findAll("[data-remove-leg]").map((b) => b.attributes("aria-label"))).toEqual([
      "Remove leg 1",
      "Remove leg 2",
    ]);
    expect(w.text()).toContain("Direction");
    expect(w.text()).not.toContain("Leg 1 direction");
  });
});

describe("P7: a disabled rule, the Limits link (ux §10)", () => {
  const rule = {
    id: "r1",
    label: "Prime downlink",
    name_template: "{craft}-{station}",
    enabled: false,
    stations: [{ id: "s1", code: "SVB", name: "Svalbard", transport_id: null }],
    legs: [{ direction: "downlink" as const, role: "primary" as const }],
    route_count: 0,
    samples: [],
  };
  it("tags a disabled rule DISABLED in its header and keeps the sentence", () => {
    const w = mount(RuleBlock, { props: { rule, profileName: "Block 1", index: "P2" } });
    expect(w.get("header").text()).toContain("Disabled");
    expect(w.get("[data-rule-disabled]").text()).toBe(
      "This rule is disabled; it generates no routes.",
    );
    // Not dimmed (mms-ux, #460): the query, route and name keep full contrast.
    expect(w.find(".opacity-60").exists()).toBe(false);
    const on = mount(RuleBlock, {
      props: { rule: { ...rule, enabled: true }, profileName: "Block 1", index: "P2" },
    });
    expect(on.get("header").text()).not.toContain("Disabled");
  });
  it("links Limits to the Limits app by name", () => {
    const w = mount(LimitsNotice, { global: { stubs: { RouterLink: RouterLinkStub } } });
    const link = w.getComponent(RouterLinkStub);
    expect(link.text()).toBe("Limits");
    expect(link.props("to")).toEqual({ name: "setup.app", params: { appKey: "limits" } });
  });
});
