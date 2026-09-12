import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { defineComponent, h, reactive, nextTick } from "vue";
import NoOrganizationPage from "./OrganizationAccessPanel.vue";
test("organization bootstrap shows pending invitations and native sign-out", async () => {
  const props = reactive({
    page: { version: 1, csrf_token: "csrf", pending_invitations_count: 0 },
  });
  const wrapper = mount(defineComponent(() => () => h(NoOrganizationPage, props)));
  expect(wrapper.find('a[href="/notifications"]').exists()).toBe(false);
  props.page.pending_invitations_count = 2;
  await nextTick();
  expect(wrapper.text()).toContain("2 pending invitations.");
  expect(wrapper.get("form").attributes("action")).toBe("/session");
  expect(wrapper.get<HTMLInputElement>('[name="_method"]').element.value).toBe("delete");
  wrapper.unmount();
});

test("malformed transport hides native effects and valid refresh recovers without intercepting submit", async () => {
  const page = { version: 1, csrf_token: "csrf", pending_invitations_count: 0 };
  const wrapper = mount(NoOrganizationPage, { props: { page } });
  const submit = new Event("submit", { bubbles: true, cancelable: true });
  wrapper.get("#no-organization-sign-out").element.dispatchEvent(submit);
  expect(submit.defaultPrevented).toBe(false);
  for (const bad of [null, {}, { ...page, version: 2 }, { ...page, csrf_token: "" }]) {
    await wrapper.setProps({ page: bad });
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#organization-access-unavailable").exists()).toBe(true);
  }
  await wrapper.setProps({ page });
  expect(wrapper.find("#no-organization-sign-out").exists()).toBe(true);
  wrapper.unmount();
});
