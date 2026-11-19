import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApButton from "../ApButton.vue";
import ApDecision from "../ApDecision.vue";
import ApNumberField from "../ApNumberField.vue";
import { readNumber } from "./number.ts";

describe("readNumber", () => {
  it("separates empty, invalid, out of range and ok", () => {
    expect(readNumber("", { min: 0, max: 12 })).toEqual({ kind: "empty" });
    expect(readNumber("8,0", { min: 0, max: 12 })).toEqual({ kind: "invalid" });
    expect(readNumber("13", { min: 0, max: 12 })).toEqual({ kind: "out_of_range", value: 13 });
    expect(readNumber("−2.5", {})).toEqual({ kind: "ok", value: -2.5 });
    expect(readNumber("2.5", { integer: true })).toEqual({ kind: "invalid" });
  });
});

describe("ApNumberField", () => {
  it("says what range is allowed when out of range", () => {
    const wrapper = mount(ApNumberField, {
      props: { label: "Setpoint", unit: "°C", min: 0, max: 12, modelValue: "15" },
    });
    expect(wrapper.text()).toContain("Out of range. Allowed: 0–12 °C.");
    expect(wrapper.get("input").attributes("aria-invalid")).toBe("true");
  });
});

const options = [
  { value: "go", title: "GO as requested", commitLabel: "Sign GO · 98 targets" },
  { value: "back", title: "Send back", needsNote: true, commitLabel: "Send back" },
] as const;

describe("ApDecision", () => {
  it("needs a choice, then a note for options that require one, before it commits", async () => {
    const wrapper = mount(ApDecision, {
      props: { options, noteLabel: "Note to Donovan", modelValue: null },
    });
    expect(wrapper.text()).toContain("Choose a decision first.");
    await wrapper.setProps({ modelValue: "back" });
    expect(wrapper.text()).toContain("Add a note to send back.");
    await wrapper.get("textarea").setValue("Check 117 with Priya.");
    expect(wrapper.text()).not.toContain("Add a note");
    const primary = wrapper.findAll("button").at(-1);
    expect(primary?.text()).toBe("Send back");
    await primary?.trigger("click");
    expect(wrapper.emitted("commit")).toEqual([[{ value: "back", note: "Check 117 with Priya." }]]);
  });

  it("stays blocked with the caller's reason", async () => {
    const wrapper = mount(ApDecision, {
      props: {
        options,
        noteLabel: "Note",
        modelValue: "go",
        blockedReason: "You can't approve your own request.",
      },
    });
    await wrapper.findAll("button").at(-1)?.trigger("click");
    expect(wrapper.emitted("commit")).toBeUndefined();
    expect(wrapper.text()).toContain("You can't approve your own request.");
  });
});

describe("ApButton disabled reason", () => {
  it("describes the button without becoming part of its name", () => {
    const wrapper = mount(ApButton, {
      props: { disabled: true, disabledReason: "Needs a note" },
      slots: { default: "Send" },
    });
    const reason = wrapper.get("button span.sr-only");
    expect(reason.attributes("aria-hidden")).toBe("true");
    expect(wrapper.get("button").attributes("aria-describedby")).toBe(reason.attributes("id"));
  });
});
