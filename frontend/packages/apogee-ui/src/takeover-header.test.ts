import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import ApTakeoverHeader from "./ApTakeoverHeader.vue";

const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: "/", component: { render: () => null } }],
});
const header = (props: { clock?: boolean } = {}, slots: Record<string, string> = {}) =>
  mount(ApTakeoverHeader, {
    props: { title: "Thermal overview", close: "/", ...props },
    slots,
    global: { plugins: [router] },
  });

describe("ApTakeoverHeader phone layouts (ux Dashboards.md §Phone)", () => {
  it("shows the UTC clock by default, and none with clock: false", () => {
    expect(header().text()).toContain("UTC");
    expect(header({ clock: false }).text()).not.toContain("UTC");
  });
  it("keeps a screen's own clocks slot when the UTC clock is off", () => {
    expect(header({ clock: false }, { clocks: "<span>2 RED</span>" }).text()).toContain("2 RED");
  });
  it("renders a subrow as a full-width row of its own", () => {
    const w = header(
      { clock: false },
      { actions: "<button>⋯</button>", subrow: "<span>scope</span>" },
    );
    const row = w.findAll("header > div").find((d) => d.text() === "scope");
    expect(row?.classes()).toEqual(expect.arrayContaining(["order-last", "w-full"]));
  });
});
