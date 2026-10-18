import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { defineComponent, h, reactive, nextTick } from "vue";
import OrganizationInvitationPage from "./InvitationAcceptancePanel.vue";
test("invitation form contains the credential fields only while the invitation is available", async () => {
  const page = {
    version: 1,
    csrf_token: "csrf",
    token: "test/token",
    available: true,
    error: null as string | null,
    display_name: "Operator",
    organization: { display_name: "Mission Org", slug: "mission" },
    invitation: {
      email: "operator@example.test",
      membership_role: "member",
      grant_platform_admin: false,
    },
  };
  const props = reactive({ page });
  const wrapper = mount(defineComponent(() => () => h(OrganizationInvitationPage, props)));
  expect(wrapper.get("form").attributes("action")).toBe("/invitations/test%2Ftoken");
  expect(wrapper.findAll("input").map((input) => input.attributes("name"))).toEqual([
    "_csrf_token",
    "organization_invitation_acceptance[display_name]",
    "organization_invitation_acceptance[password]",
    "organization_invitation_acceptance[password_confirmation]",
  ]);
  expect(wrapper.get<HTMLInputElement>('[type="password"]').element.value).toBe("");
  props.page.available = false;
  props.page.error = "This invitation link is not valid.";
  await nextTick();
  expect(wrapper.find("form").exists()).toBe(false);
  expect(wrapper.get('[role="alert"]').text()).toBe("This invitation link is not valid.");
  wrapper.unmount();
});

test("malformed transport hides native effects and valid refresh recovers without intercepting submit", async () => {
  const page = {
    version: 1,
    csrf_token: "csrf",
    token: "opaque/invite",
    available: true,
    error: null,
    display_name: "Operator",
    organization: { display_name: "Flight", slug: "flight" },
    invitation: {
      email: "operator@example.test",
      membership_role: "member",
      grant_platform_admin: false,
    },
  };
  const wrapper = mount(OrganizationInvitationPage, { props: { page } });
  const submit = new Event("submit", { bubbles: true, cancelable: true });
  wrapper.get("#organization-invitation-acceptance-form").element.dispatchEvent(submit);
  expect(submit.defaultPrevented).toBe(false);
  for (const bad of [null, {}, { ...page, version: 2 }, { ...page, csrf_token: "" }]) {
    await wrapper.setProps({ page: bad });
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#invitation-acceptance-unavailable").exists()).toBe(true);
  }
  await wrapper.setProps({ page });
  expect(wrapper.find("#organization-invitation-acceptance-form").exists()).toBe(true);
  wrapper.unmount();
});
