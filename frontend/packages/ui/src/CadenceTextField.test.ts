import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import CadenceTextField from "./CadenceTextField.vue";

describe("CadenceTextField", () => {
  it("exposes a labeled two-way input contract", async () => {
    const wrapper = mount(CadenceTextField, {
      props: {
        id: "admin-email",
        label: "Administrator email",
        modelValue: "",
        type: "email",
      },
    });

    const input = wrapper.get("#admin-email");
    await input.setValue("admin@example.com");

    expect(wrapper.get('label[for="admin-email"]')).toBeTruthy();
    expect(wrapper.emitted("update:modelValue")).toEqual([["admin@example.com"]]);
  });

  it("connects validation evidence to the control", () => {
    const wrapper = mount(CadenceTextField, {
      props: {
        error: "Credentials were rejected.",
        id: "admin-password",
        label: "Password",
        modelValue: "",
        type: "password",
      },
    });

    const input = wrapper.get("#admin-password");
    expect(input.attributes("aria-invalid")).toBe("true");
    expect(input.attributes("aria-describedby")).toBe("admin-password-error");
    expect(wrapper.get("#admin-password-error").text()).toBe("Credentials were rejected.");
  });
});
