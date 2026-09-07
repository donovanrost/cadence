import { mount } from "@vue/test-utils";
import { describe, it, expect } from "vite-plus/test";
import { defineComponent, h, reactive, nextTick } from "vue";
import UserSession from "./UserSession.vue";

describe("sign-in", () => {
  it("submits native credentials and CSRF to the session endpoint", async () => {
    const props = reactive({ csrfToken: "csrf-value" });
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
    props.csrfToken = "renewed-token";
    await nextTick();
    expect((wrapper.get('input[type="password"]').element as HTMLInputElement).value).toBe(
      "password",
    );
    expect(wrapper.get('input[name="_csrf_token"]').attributes("value")).toBe("renewed-token");
    wrapper.unmount();
  });
});
