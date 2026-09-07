import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { defineComponent, h, reactive, nextTick } from "vue";
import AdminModePage from "./AdminModePage.vue";
import NoOrganizationPage from "./NoOrganizationPage.vue";
import OrganizationInvitationPage from "./OrganizationInvitationPage.vue";
test("admin reauthentication uses the native session endpoint", () => {
  const wrapper = mount(AdminModePage, { props: { page: { csrf_token: "csrf" } } });
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
test("organization bootstrap shows pending invitations and native sign-out", async () => {
  const props = reactive({ page: { csrf_token: "csrf", pending_invitations_count: 0 } });
  const wrapper = mount(defineComponent(() => () => h(NoOrganizationPage, props)));
  expect(wrapper.find('a[href="/notifications"]').exists()).toBe(false);
  props.page.pending_invitations_count = 2;
  await nextTick();
  expect(wrapper.text()).toContain("2 pending invitations.");
  expect(wrapper.get("form").attributes("action")).toBe("/session");
  expect(wrapper.get<HTMLInputElement>('[name="_method"]').element.value).toBe("delete");
  wrapper.unmount();
});
test("invitation form contains the credential fields only while the invitation is available", async () => {
  const page = {
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
