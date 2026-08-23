import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import CButton from "./CButton.vue";
import CCheckbox from "./CCheckbox.vue";

describe("Cadence UI", () => {
  it("uses Reka checkbox semantics while exposing a boolean application contract", async () => {
    const wrapper = mount(CCheckbox, {
      props: { id: "packet-selected", modelValue: false },
      slots: { default: "Selected only" },
    });

    const control = wrapper.get('[role="checkbox"]');
    expect(control.attributes("aria-checked")).toBe("false");

    await control.trigger("click");

    expect(wrapper.emitted("update:modelValue")).toEqual([[true]]);
  });

  it("makes a loading action busy and unavailable", () => {
    const wrapper = mount(CButton, {
      props: { loading: true, variant: "primary" },
      slots: { default: "Save bindings" },
    });

    const button = wrapper.get("button");
    expect(button.attributes("aria-busy")).toBe("true");
    expect(button.attributes()).toHaveProperty("disabled");
  });
});
