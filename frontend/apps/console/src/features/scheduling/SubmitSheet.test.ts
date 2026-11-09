import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { PlanDetail } from "./api.ts";
import SubmitSheet from "./SubmitSheet.vue";

const gap = (id: string) => ({
  requirement_id: id,
  requirement_version: 1,
  spacecraft_id: `sc-${id}`,
  why: ["minimum_duration_not_met"],
});
const plan: PlanDetail = {
  id: "plan_1",
  version: 41,
  state: "draft",
  window: { from: null, to: null },
  author: null,
  counts: { passes: 12, minutes: 96, conflicts: 0, unsatisfied: 2 },
  ready_to_approve: false,
  updated_at: "2026-11-09T10:00:00Z",
  passes: [],
  demand: { rule_met: 1, rule_total: 3, spacecraft: [], rules: [] },
  unmet: [gap("r1"), gap("r2")],
  conflicts: [],
};

describe("SubmitSheet", () => {
  it("needs a valid reason for every gap; 'same for all' fills the rest; emits acknowledgements", async () => {
    const wrapper = mount(SubmitSheet, {
      props: {
        plan,
        nameOf: () => null,
        commitLabel: "Accept 2 gaps and submit",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    expect(wrapper.text()).toContain("2 gaps still need a reason");
    const [first] = wrapper.findAll("textarea");
    await first?.setValue("Station maintenance accepted by ops.");
    expect(wrapper.text()).toContain("1 gap still needs a reason");
    await wrapper.get("input[type=checkbox]").setValue(true);
    expect(wrapper.text()).not.toContain("still need");
    await wrapper.findAll("footer button").at(-1)?.trigger("click");
    expect(wrapper.emitted("submit")).toEqual([
      [
        [
          { requirement_id: "r1", reason: "Station maintenance accepted by ops." },
          { requirement_id: "r2", reason: "Station maintenance accepted by ops." },
        ],
      ],
    ]);
    wrapper.unmount();
  });

  it("refuses reasons shorter than 10 characters", async () => {
    const wrapper = mount(SubmitSheet, {
      props: {
        plan: { ...plan, unmet: [gap("r1")] },
        nameOf: () => null,
        commitLabel: "Accept 1 gap and submit",
        confirm: "",
        busy: false,
      },
      attachTo: document.body,
    });
    await wrapper.get("textarea").setValue("too short");
    await wrapper.findAll("footer button").at(-1)?.trigger("click");
    expect(wrapper.emitted("submit")).toBeUndefined();
    wrapper.unmount();
  });
});
