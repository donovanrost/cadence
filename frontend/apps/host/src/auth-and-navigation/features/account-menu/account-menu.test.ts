import { afterEach, expect, test } from "vite-plus/test";
import { mount, type VueWrapper } from "@vue/test-utils";
import AccountMenu from "./AccountMenu.vue";
import { context } from "../../shared/context.test-support";
let wrapper: VueWrapper;
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = "";
});
test("account switching and sign-out retain native methods and CSRF across updates", async () => {
  const app = (wrapper = mount(AccountMenu, {
    attachTo: document.body,
    props: { context, id: "account-user" },
  }));
  await app.get("#account-user-user").trigger("click");
  const form = app.get("#account-user-switch-org-2");
  expect(form.attributes("action")).toBe("/session/organization");
  expect(form.attributes("method")).toBe("post");
  expect(form.get<HTMLInputElement>('[name="_method"]').element.value).toBe("put");
  expect(form.get<HTMLInputElement>('[name="organization_id"]').element.value).toBe("org-2");
  expect(form.get<HTMLInputElement>('[name="_csrf_token"]').element.value).toBe("test-csrf");
  await app.setProps({ context: { ...context, csrf_token: "refreshed-csrf" } });
  expect(app.get("#account-user-switch-org-2").element).toBe(form.element);
  expect(form.get<HTMLInputElement>('[name="_csrf_token"]').element.value).toBe("refreshed-csrf");
  expect(app.get<HTMLInputElement>('#account-user-sign-out [name="_method"]').element.value).toBe(
    "delete",
  );
});
test("an invalid account document contains its effects and a failed bell leaves account actions usable", async () => {
  wrapper = mount(AccountMenu, { props: { context, id: "account-user" } });
  for (const bad of [
    { ...context, version: 2 },
    { ...context, csrf_token: "" },
  ]) {
    await wrapper.setProps({ context: bad });
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#account-user-unavailable").exists()).toBe(true);
  }
  await wrapper.setProps({ context: { ...context, notifications: null } });
  expect(wrapper.find("#account-user-notifications-unavailable").exists()).toBe(true);
  await wrapper.get("#account-user-user").trigger("click");
  expect(wrapper.find("#account-user-sign-out").exists()).toBe(true);
});
