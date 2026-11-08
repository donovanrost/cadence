import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApButton from "./ApButton.vue";
import ApSegmented from "./ApSegmented.vue";
import ApStatTile from "./ApStatTile.vue";

describe("ApButton", () => {
  it("stays focusable when disabled, explains why, and drops clicks", async () => {
    const wrapper = mount(ApButton, {
      props: { disabled: true, disabledReason: "Needs the 3 breaking items fixed first" },
      slots: { default: "Apply" },
    });
    const button = wrapper.get("button");
    expect(button.attributes("aria-disabled")).toBe("true");
    expect(button.attributes("disabled")).toBeUndefined();
    expect(wrapper.text()).toContain("Needs the 3 breaking items fixed first");
    await button.trigger("click");
    expect(wrapper.emitted("click")).toBeUndefined();
  });
});

describe("ApSegmented", () => {
  const options = [
    { value: "a", label: "A" },
    { value: "b", label: "B" },
    { value: "c", label: "C" },
  ] as const;

  it("moves selection with arrows, Home and End", async () => {
    const wrapper = mount(ApSegmented, { props: { options, modelValue: "a", label: "Pick" } });
    const first = wrapper.findAll("button")[0];
    await first?.trigger("keydown", { key: "ArrowLeft" });
    await first?.trigger("keydown", { key: "End" });
    await first?.trigger("keydown", { key: "ArrowDown" });
    expect(wrapper.emitted("update:modelValue")).toEqual([["c"], ["c"], ["b"]]);
  });
});

describe("ApStatTile", () => {
  it("says unknown instead of inventing a number", () => {
    const wrapper = mount(ApStatTile, { props: { label: "Stale", value: null } });
    expect(wrapper.text()).toContain("unknown");
  });
});

describe("ApStatTile caption", () => {
  it("tints the caption with captionState independently of the value", () => {
    const wrapper = mount(ApStatTile, {
      props: {
        label: "Uplinks queued",
        value: 23,
        caption: "2 await your GO",
        captionState: "caution",
      },
    });
    expect(wrapper.get("span.text-caution-text").text()).toBe("2 await your GO");
    expect(wrapper.find(".shadow-\\[inset_0_2px_0_var\\(--color-caution\\)\\]").exists()).toBe(
      false,
    );
  });
});
