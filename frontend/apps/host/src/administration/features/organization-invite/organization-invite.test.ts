import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OrganizationInvitePanel from "./OrganizationInvitePanel.vue";
import { readOrganizationInvite, readInviteResult } from "./contracts";
const fixture = () => ({
  version: 1,
  user_id: "admin",
  observed_at: "2026-09-10T00:00:00Z",
  organization: { id: "org-a", name: "Flight organization", slug: "flight" },
  submitted: null,
});
const receipt = {
  id: "invite-a",
  email: "invitee@example.test",
  role: "organization_admin",
  grant_platform_admin: true,
  expires_at: "2026-09-20T00:00:00Z",
  delivery: "submitted",
};
test("the reviewed role and platform grant reach one invitation request", async () => {
  const act = vi.fn().mockResolvedValue({ status: "invited", invitation: receipt });
  const wrapper = mount(OrganizationInvitePanel, {
    props: { model: readOrganizationInvite(fixture(), "admin", "org-a"), act, refresh: vi.fn() },
  });
  await wrapper.get("#invite_email").setValue("invitee@example.test");
  await wrapper.get("#invite_display_name").setValue("Flight operator");
  await wrapper.get("#invite_membership_role").setValue("organization_admin");
  await wrapper.get("#invite_grant_platform_admin").setValue(true);
  await wrapper.get("#invite-form").trigger("submit");
  await flushPromises();
  expect(act).toHaveBeenCalledExactlyOnceWith("invite", {
    email: "invitee@example.test",
    display_name: "Flight operator",
    membership_role: "organization_admin",
    grant_platform_admin: true,
  });
  expect(wrapper.find("#invite-form").exists()).toBe(false);
  expect(wrapper.get("#organization-invitation-email-submitted").text()).toContain(
    "submitted for delivery",
  );
  expect(wrapper.get("#organization-invitation-created a").attributes("href")).toBe(
    "/admin/organizations/org-a",
  );
  wrapper.unmount();
});
test("mail failure retains a saved invitation receipt without automatic resend", async () => {
  const act = vi
    .fn()
    .mockResolvedValue({ status: "invited", invitation: { ...receipt, delivery: "unavailable" } });
  const wrapper = mount(OrganizationInvitePanel, {
    props: { model: readOrganizationInvite(fixture(), "admin", "org-a"), act, refresh: vi.fn() },
  });
  await wrapper.get("#invite-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#organization-invitation-email-unavailable").text()).toContain("saved");
  expect(wrapper.find("#invite-form").exists()).toBe(false);
  expect(act).toHaveBeenCalledOnce();
  expect(wrapper.text()).not.toContain("email was submitted");
  wrapper.unmount();
});
test("unknown invitation outcomes keep the draft and never infer failure from refresh", async () => {
  const act = vi.fn().mockRejectedValue(Error("network lost"));
  const refresh = vi.fn(async () => {});
  const wrapper = mount(OrganizationInvitePanel, {
    props: { model: readOrganizationInvite(fixture(), "admin", "org-a"), act, refresh },
  });
  await wrapper.get("#invite_email").setValue("invitee@example.test");
  await wrapper.get("#invite-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#organization-invitation-message").text()).toContain("unknown");
  await wrapper.get("#refresh-organization-invitation").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({
    model: readOrganizationInvite(
      { ...fixture(), observed_at: "2026-09-10T00:01:00Z" },
      "admin",
      "org-a",
    ),
  });
  await wrapper.get("#invite-form").trigger("submit");
  expect(act).toHaveBeenCalledOnce();
  await wrapper.setProps({
    model: readOrganizationInvite({ ...fixture(), submitted: receipt }, "admin", "org-a"),
  });
  expect(wrapper.find("#organization-invitation-created").exists()).toBe(true);
  wrapper.unmount();
});
test("foreign organizations, unsupported documents and false delivery claims are rejected", () => {
  expect(() => readOrganizationInvite(fixture(), "other", "org-a")).toThrow();
  expect(() => readOrganizationInvite(fixture(), "admin", "org-other")).toThrow();
  expect(() => readOrganizationInvite({ ...fixture(), version: 2 }, "admin", "org-a")).toThrow();
  expect(() =>
    readInviteResult({ status: "invited", invitation: { ...receipt, delivery: "delivered" } }),
  ).toThrow();
  expect(() => readInviteResult({ status: "invalid", errors: { script: "invalid" } })).toThrow();
});
