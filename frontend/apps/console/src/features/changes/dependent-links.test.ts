import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { MONITORING_EDITS_PENDING } from "@/features/telemetry/index.ts";
import DependentLinks from "./DependentLinks.vue";

const points = Array.from({ length: 7 }, (_, i) => ({
  point_id: `DERIVED.P${i}`,
  definition_id: `dd_${i}`,
}));

/** U42 after #669: the derived points a retire would break are named, not linked (#451). */
describe("derived points a retire would break", () => {
  it("names five, counts the rest and says where they're edited, with no link", () => {
    const w = mount(DependentLinks, {
      props: { points },
      global: { stubs: { RouterLink: RouterLinkStub } },
    });
    expect(w.text()).toContain("Derived points that use it: DERIVED.P0 · DERIVED.P1");
    expect(w.text()).toContain("DERIVED.P4 and 2 more.");
    expect(w.text()).not.toContain("DERIVED.P5");
    expect(w.text()).toContain(MONITORING_EDITS_PENDING);
    expect(w.findAllComponents(RouterLinkStub)).toHaveLength(0);
  });

  it("says nothing when no derived point uses it", () => {
    expect(mount(DependentLinks, { props: { points: [] } }).text()).toBe("");
  });
});
