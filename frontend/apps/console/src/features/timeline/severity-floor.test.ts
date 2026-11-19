import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import SeverityFloor from "./SeverityFloor.vue";

describe("Timeline severity floor (ux U69 A9a, api severity_at_least)", () => {
  it("reads All by default and writes ?severity= as a threshold", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: "/t", component: { render: () => null } }],
    });
    await router.push({ path: "/t", query: { kind: "limit" } });
    const w = mount(SeverityFloor, { global: { plugins: [router] } });
    const radios = () => w.findAll('[role="radio"]');
    expect(radios().map((r) => r.text())).toEqual(["All", "Caution and up", "Critical"]);
    expect(radios()[0]?.attributes("aria-checked")).toBe("true");
    await radios()[1]?.trigger("click");
    await flushPromises();
    expect(router.currentRoute.value.query).toEqual({ kind: "limit", severity: "caution" });
    await radios()[0]?.trigger("click");
    await flushPromises();
    expect(router.currentRoute.value.query).toEqual({ kind: "limit" });
  });
});
