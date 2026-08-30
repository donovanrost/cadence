import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import SignInView from "./SignInView.vue";

describe("SignInView", () => {
  it("submits one administrator credential shape", async () => {
    const wrapper = mount(SignInView);

    await wrapper.get("#admin-email").setValue("admin@example.com");
    await wrapper.get("#admin-password").setValue("change-me");
    await wrapper.get("#sign-in-form").trigger("submit");

    expect(wrapper.emitted("submit")).toEqual([
      [{ email: "admin@example.com", password: "change-me" }],
    ]);
  });

  it("exposes a stable error region without adding a registration route", () => {
    const wrapper = mount(SignInView, { props: { error: "Credentials were rejected." } });

    expect(wrapper.get("#sign-in-error").attributes("role")).toBe("alert");
    expect(wrapper.find('a[href="/sign-up"]').exists()).toBe(false);
  });
});
