import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApTimeRange from "../ApTimeRange.vue";

const NOW = Date.UTC(2026, 9, 23, 2, 21, 30);
const presets = [
  { id: "h1", label: "Last 1h", from: NOW - 3_600_000, to: NOW },
  { id: "h24", label: "24h", from: NOW - 86_400_000, to: NOW },
];

function range() {
  return mount(ApTimeRange, {
    props: { label: "Plot window", presets, modelValue: { from: NOW - 3_600_000, to: NOW } },
  });
}

describe("ApTimeRange", () => {
  it("marks the matching preset and emits a preset's window", async () => {
    const wrapper = range();
    expect(wrapper.get("[role=radio][aria-checked=true]").text()).toBe("Last 1h");
    await wrapper.findAll("[role=radio]")[1]?.trigger("click");
    expect(wrapper.emitted("update:modelValue")).toEqual([[{ from: NOW - 86_400_000, to: NOW }]]);
  });

  it("commits typed From/To and refuses a reversed range", async () => {
    const wrapper = range();
    const [from, to] = wrapper.findAll("input");
    await from?.setValue("2026-10-22 00:00");
    await to?.setValue("2026-10-22 06:00");
    await to?.trigger("change");
    expect(wrapper.emitted("update:modelValue")?.at(-1)).toEqual([
      { from: Date.UTC(2026, 9, 22, 0, 0), to: Date.UTC(2026, 9, 22, 6, 0) },
    ]);
    const before = wrapper.emitted("update:modelValue")?.length;
    await to?.setValue("2026-10-21 06:00");
    await to?.trigger("change");
    expect(wrapper.text()).toContain("To must be after From.");
    expect(wrapper.emitted("update:modelValue")?.length).toBe(before);
  });
});

describe("ApTimeRange preset drift", () => {
  it("still highlights a preset whose window drifted by seconds", () => {
    const wrapper = mount(ApTimeRange, {
      props: {
        label: "Plot window",
        presets,
        modelValue: { from: NOW - 3_600_000 - 5_000, to: NOW - 5_000 },
      },
    });
    expect(wrapper.get("[role=radio][aria-checked=true]").text()).toBe("Last 1h");
  });
});
