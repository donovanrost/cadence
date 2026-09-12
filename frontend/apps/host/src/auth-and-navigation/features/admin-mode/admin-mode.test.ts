import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import AdminModePage from "./AdminModePanel.vue";
test("admin reauthentication uses the native session endpoint", () => {
  const wrapper = mount(AdminModePage, { props: { page: { version: 1, csrf_token: "csrf" } } });
  expect(wrapper.get("#admin-mode-form").attributes("action")).toBe("/admin-mode");
  expect(wrapper.get("#admin-mode-form").attributes("method")).toBe("post");
  expect(wrapper.findAll("button")).toHaveLength(1);
  expect(wrapper.get("button").attributes("type")).toBe("submit");
  expect(wrapper.get('[name="admin_mode[password]"]').attributes("autocomplete")).toBe(
    "current-password",
  );
  expect(wrapper.get<HTMLInputElement>('[name="_csrf_token"]').element.value).toBe("csrf");
  wrapper.unmount();
});

test("malformed transport hides native effects and valid refresh recovers without intercepting submit", async () => {
  const page = { version: 1, csrf_token: "csrf" };
  const wrapper = mount(AdminModePage, { props: { page } });
  const submit = new Event("submit", { bubbles: true, cancelable: true });
  wrapper.get("#admin-mode-form").element.dispatchEvent(submit);
  expect(submit.defaultPrevented).toBe(false);
  for (const bad of [null, {}, { ...page, version: 2 }, { ...page, csrf_token: "" }]) {
    await wrapper.setProps({ page: bad });
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#admin-mode-unavailable").exists()).toBe(true);
  }
  await wrapper.setProps({ page });
  expect(wrapper.find("#admin-mode-form").exists()).toBe(true);
  wrapper.unmount();
});
