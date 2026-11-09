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
