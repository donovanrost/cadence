import { mount } from "@vue/test-utils";
import { describe, it, expect, test } from "vite-plus/test";
import { defineComponent, h, reactive, nextTick } from "vue";
import UserSession from "./SignInPanel.vue";

describe("sign-in", () => {
  it("submits native credentials and CSRF to the session endpoint", async () => {
    const props = reactive({ page: { version: 1, csrf_token: "csrf-value" } });
    const wrapper = mount(defineComponent(() => () => h(UserSession, props)));
    const form = wrapper.get("form");
    expect(form.attributes("action")).toBe("/sign-in");
    expect(form.attributes("method")).toBe("post");
    expect(wrapper.get('input[name="_csrf_token"]').attributes("value")).toBe("csrf-value");
    await wrapper.get('input[type="email"]').setValue("operator@example.com");
    await wrapper.get('input[type="password"]').setValue("password");
    expect(wrapper.get('input[type="email"]').attributes("name")).toBe("user[email]");
    expect(wrapper.get('input[type="password"]').attributes("name")).toBe("user[password]");
    expect(wrapper.emitted("validate")).toBeUndefined();
    expect(wrapper.get('button[type="submit"]').text()).toBe("Sign In");
    props.page.csrf_token = "renewed-token";
    await nextTick();
    expect((wrapper.get('input[type="password"]').element as HTMLInputElement).value).toBe(
      "password",
    );
    expect(wrapper.get('input[name="_csrf_token"]').attributes("value")).toBe("renewed-token");
    wrapper.unmount();
  });
});

test("malformed transport hides native effects and valid refresh recovers without intercepting submit", async () => {
  const page = { version: 1, csrf_token: "csrf" };
  const wrapper = mount(UserSession, { props: { page } });
  const submit = new Event("submit", { bubbles: true, cancelable: true });
  wrapper.get("#sign-in-form").element.dispatchEvent(submit);
  expect(submit.defaultPrevented).toBe(false);
  for (const bad of [null, {}, { ...page, version: 2 }, { ...page, csrf_token: "" }]) {
    await wrapper.setProps({ page: bad });
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#sign-in-unavailable").exists()).toBe(true);
  }
  await wrapper.setProps({ page });
  expect(wrapper.find("#sign-in-form").exists()).toBe(true);
  wrapper.unmount();
});
