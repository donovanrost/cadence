import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApTimePicker from "../ApTimePicker.vue";

const AT = Date.UTC(2026, 9, 23, 2, 59, 40);

function picker(modelValue: number | null) {
  return mount(ApTimePicker, {
    props: {
      label: "Release at",
      modelValue,
      presets: [{ id: "aos", label: "Next AOS", at: AT, sub: "Fairbanks" }],
      warn: (at: number) => (at === AT ? "In umbra then." : null),
    },
    attachTo: document.body,
  });
}

describe("ApTimePicker", () => {
  it("sets a typed time and emits it on Set", async () => {
    const wrapper = picker(null);
    await wrapper.get("button[aria-haspopup=dialog]").trigger("click");
    await wrapper.get("dialog input").setValue("2026-10-24 06:00");
    expect(wrapper.text()).toContain("Parsed");
    const set = wrapper.findAll("dialog footer button").at(-1);
    expect(set?.text()).toBe("Set 10-24 06:00:00Z");
    await set?.trigger("click");
    expect(wrapper.emitted("update:modelValue")).toEqual([[Date.UTC(2026, 9, 24, 6, 0, 0)]]);
    wrapper.unmount();
  });

  it("applies a preset, shows the caller's warning, and Cancel emits nothing", async () => {
    const wrapper = picker(null);
    await wrapper.get("button[aria-haspopup=dialog]").trigger("click");
    await wrapper.get("button[aria-pressed]").trigger("click");
    expect(wrapper.get("[role=alert]").text()).toContain("In umbra then.");
    await wrapper.findAll("dialog footer button").at(0)?.trigger("click");
    expect(wrapper.emitted("update:modelValue")).toBeUndefined();
    wrapper.unmount();
  });

  it("flags text it can't read", async () => {
    const wrapper = picker(AT);
    await wrapper.get("button[aria-haspopup=dialog]").trigger("click");
    await wrapper.get("dialog input").setValue("next tuesday");
    expect(wrapper.text()).toContain("Can’t read that");
    expect(wrapper.get("dialog input").attributes("aria-invalid")).toBe("true");
    wrapper.unmount();
  });
});

describe("ApTimePicker calendar", () => {
  it("shows the month of the value being edited", async () => {
    const wrapper = picker(AT);
    await wrapper.get("button[aria-haspopup=dialog]").trigger("click");
    expect(wrapper.text()).toContain("October 2026");
    await wrapper.get("dialog input").setValue("2027-03-05 10:00");
    expect(wrapper.text()).toContain("March 2027");
    wrapper.unmount();
  });
});

describe("ApTimePicker future", () => {
  it("flags a past time only when the caller asks for future times", async () => {
    const wrapper = mount(ApTimePicker, {
      props: {
        label: "Release at",
        modelValue: null,
        future: true,
        pastMessage: "In the past: it would send at the next AOS.",
      },
      attachTo: document.body,
    });
    await wrapper.get("button[aria-haspopup=dialog]").trigger("click");
    await wrapper.get("dialog input").setValue("2020-01-01 00:00");
    expect(wrapper.text()).toContain("In the past: it would send at the next AOS.");
    wrapper.unmount();
  });
});
