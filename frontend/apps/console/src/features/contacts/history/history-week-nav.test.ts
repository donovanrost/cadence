import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { nextTick } from "vue";
import { ApTimePicker } from "@/ui";
import HistoryWeekNav from "./HistoryWeekNav.vue";
import { weekSpan } from "./history.ts";

const NOW = Date.parse("2026-11-16T10:30:00Z");

describe("History week nav (U78)", () => {
  it("refuses a future date with words under the field, and opens a past date's week", async () => {
    const w = mount(HistoryWeekNav, {
      props: { week: "2026-11-16", span: weekSpan("2026-11-16", NOW), now: NOW },
    });
    const picker = w.getComponent(ApTimePicker);
    // The picker has its own status line; the refusal is the nav's, after it.
    const refusal = () => w.findAll('[role="alert"]').at(-1)?.text();
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the picker's emit; the lint type service can't resolve SFC instances.
    picker.vm.$emit("update:modelValue", Date.parse("2026-11-20T00:00:00Z"));
    await nextTick();
    expect(w.emitted("week")).toBeUndefined();
    expect(refusal()).toBe("Pick a date up to today.");
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the picker's emit; the lint type service can't resolve SFC instances.
    picker.vm.$emit("update:modelValue", Date.parse("2026-11-05T00:00:00Z"));
    await nextTick();
    expect(w.emitted("week")).toEqual([["2026-11-02"]]);
    expect(refusal()).toBe("");
  });
});
