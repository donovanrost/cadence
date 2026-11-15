import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApGantt from "../ApGantt.vue";
import type { GanttBar } from "./model.ts";

const H = 3_600_000;
const bar = (
  id: string,
  rowId: string,
  from: number,
  kind: GanttBar["kind"] = "own",
): GanttBar => ({
  id,
  rowId,
  from,
  to: from + H / 6,
  kind,
  label: id,
  description: `${id} pass`,
});

function gantt() {
  return mount(ApGantt, {
    props: {
      label: "Draft by station",
      rows: [
        { id: "svb", label: "SVB-1", tag: "UP" },
        { id: "fbk", label: "FBK-1", degraded: true },
      ],
      bars: [
        bar("118", "svb", H),
        bar("119", "svb", 3 * H, "window"),
        bar("200", "fbk", 2 * H, "clash"),
      ],
      bands: [{ rowId: "fbk", from: 4 * H, to: 6 * H, kind: "maintenance", label: "Maintenance" }],
      window: { from: 0, to: 24 * H },
      now: 2 * H,
      selected: null,
    },
    attachTo: document.body,
  });
}

describe("ApGantt", () => {
  it("puts interleaved bars in their own rows, in input order", () => {
    const w = mount(ApGantt, {
      props: {
        label: "Rows",
        rows: [
          { id: "a", label: "A" },
          { id: "b", label: "B" },
        ],
        bars: [bar("a1", "a", H), bar("b1", "b", H), bar("a2", "a", 2 * H), bar("b2", "b", 3 * H)],
        window: { from: 0, to: 24 * H },
      },
    });
    const ids = (row: number) =>
      w
        .findAll("[role=group] [role=group]")
        [row]?.findAll("button")
        .map((b) => b.attributes("data-bar"));
    expect(ids(0)).toEqual(["a1", "a2"]);
    expect(ids(1)).toEqual(["b1", "b2"]);
    w.unmount();
  });

  it("renders one tab stop and names every bar", () => {
    const wrapper = gantt();
    const buttons = wrapper.findAll("button");
    expect(buttons).toHaveLength(3);
    expect(buttons.filter((b) => b.attributes("tabindex") === "0")).toHaveLength(1);
    expect(buttons[1]?.attributes("aria-label")).toBe("119 pass");
    wrapper.unmount();
  });

  it("selects by click and by keyboard, moving with arrows", async () => {
    const wrapper = gantt();
    await wrapper.findAll("button")[0]?.trigger("click");
    await wrapper.findAll("button")[0]?.trigger("keydown", { key: "ArrowRight" });
    await wrapper.findAll("button")[1]?.trigger("keydown", { key: "Enter" });
    expect(wrapper.emitted("select")).toEqual([["118"], ["119"]]);
    expect(document.activeElement?.getAttribute("data-bar")).toBe("119");
    wrapper.unmount();
  });
});

describe("ApGantt labels", () => {
  it("hides labels that don't fit (no measured width in tests) but keeps the accessible name", () => {
    const wrapper = gantt();
    const first = wrapper.findAll("button")[0];
    expect(first?.text()).toBe("");
    expect(first?.attributes("aria-label")).toBe("118 pass");
    wrapper.unmount();
  });

  it("draws a dimmed bar faint but still named and focusable, and notches a queued-uplink pass", () => {
    const wrapper = mount(ApGantt, {
      props: {
        label: "Passes",
        rows: [{ id: "svb", label: "SVB-1" }],
        bars: [
          { ...bar("118", "svb", H), dim: true },
          { ...bar("119", "svb", 3 * H), notch: true },
        ],
        bands: [],
        window: { from: 0, to: 24 * H },
        now: 2 * H,
        selected: null,
      },
    });
    const [dimmed, notched] = wrapper.findAll("button");
    expect(dimmed?.classes()).toContain("ap-bar--dim");
    expect(dimmed?.attributes("aria-label")).toBe("118 pass");
    expect(notched?.classes()).toContain("ap-bar--notch");
    expect(notched?.classes()).not.toContain("ap-bar--dim");
  });

  it("marks attention at the bar's leading edge, outside its clip, decorative (ux U45)", () => {
    const narrow: GanttBar = { ...bar("301", "svb", H), to: H + 1_000, attention: "crit" };
    const wrapper = mount(ApGantt, {
      props: {
        label: "Contacts",
        rows: [{ id: "svb", label: "SVB-1" }],
        bars: [
          { ...bar("300", "svb", 2 * H), attention: "caution", dim: true },
          narrow,
          bar("302", "svb", 4 * H),
        ],
        window: { from: 0, to: 24 * H },
        now: null,
        selected: null,
      },
    });
    const mark = (id: string) => wrapper.find(`[data-bar-mark="${id}"]`);
    expect(mark("300").find(".ap-mark--caution").exists()).toBe(true);
    expect(mark("300").classes()).toContain("opacity-35");
    expect(mark("301").find(".ap-mark--crit").exists()).toBe(true);
    expect(mark("302").exists()).toBe(false);
    // Outside the button, so a pass a few px wide can't clip it; hidden from assistive tech.
    expect(wrapper.find('[data-bar="301"]').find(".ap-mark").exists()).toBe(false);
    expect(mark("301").find(".ap-mark").attributes("aria-hidden")).toBe("true");
    expect(mark("301").attributes("style")).toContain("left:");
    // The bar itself keeps its kind; no fill change.
    expect(wrapper.find('[data-bar="301"]').classes()).toContain("ap-bar--own");
    // Legend lists each mark on screen, with ux's fixed words.
    const legend = wrapper.find("ul").text();
    expect(legend).toContain("Needs attention");
    expect(legend).toContain("Missed");
    wrapper.unmount();
  });

  it("leaves the marks out of the legend when no bar has one", () => {
    const wrapper = gantt();
    expect(wrapper.find("ul").text()).not.toContain("Needs attention");
    expect(wrapper.find("ul").text()).not.toContain("Missed");
    wrapper.unmount();
  });
});
