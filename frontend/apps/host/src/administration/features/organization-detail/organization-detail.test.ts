import { writeFileSync } from "node:fs";
import OrganizationInvitePanel from "../organization-invite/OrganizationInvitePanel.vue";
import { readOrganizationInvite } from "../organization-invite/contracts";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OrganizationDetailPanel from "./OrganizationDetailPanel.vue";
import { readOrganizationDetail, readIssueResult, detailHref } from "./contracts";
export const detailFixture = () => ({
  version: 1,
  user_id: "admin",
  observed_at: "2026-09-10T00:00:00Z",
  organization: { id: "org-a", name: "Flight organization", slug: "flight" },
  limit: 25,
  query: { members_after: "", invitations_after: "", services_after: "" },
  issued_identity: null,
  members: {
    entries: [
      {
        id: "member-a",
        user_id: "user-a",
        name: "Flight operator",
        email: "operator@example.test",
        role: "member",
        user_state: "disabled",
      },
    ],
    next_after: null,
  },
  invitations: {
    entries: [
      {
        id: "invite-a",
        email: "invitee@example.test",
        role: "organization_admin",
        grant_platform_admin: true,
        expires_at: "2026-09-20T00:00:00Z",
      },
    ],
    next_after: null,
  },
  services: {
    entries: [
      {
        id: "svc-a",
        name: "Mission API",
        mission_id: null,
        token_hint: "cad…1234",
        lifecycle_state: "active",
        capabilities: ["organization_admin"],
      },
    ],
    next_after: null,
  },
});
test("detail renders authoritative facts and preserves native organization switching", async () => {
  const act = vi.fn();
  const wrapper = mount(OrganizationDetailPanel, {
    props: {
      model: readOrganizationDetail(detailFixture(), "admin", "org-a"),
      csrfToken: "csrf-test",
      act,
      refresh: vi.fn(),
    },
  });
  expect(wrapper.get("#organization-member-member-a").text()).toContain("Account disabled");
  expect(wrapper.get("#organization-invitation-invite-a time").attributes("datetime")).toBe(
    "2026-09-20T00:00:00Z",
  );
  expect(wrapper.get("#service-identity-svc-a").text()).toContain("Organization admin");
  expect(wrapper.get("#admin-organization-invite-link").attributes("href")).toBe(
    "/admin/organizations/org-a/invite",
  );
  const form = wrapper.get("#open-organization-form");
  expect(form.attributes("action")).toBe("/session/organization");
  expect(form.attributes("method")).toBe("post");
  expect(form.get('[name="_csrf_token"]').attributes("value")).toBe("csrf-test");
  expect(form.get('[name="_method"]').attributes("value")).toBe("put");
  expect(form.get('[name="organization_id"]').attributes("value")).toBe("org-a");
  const event = new Event("submit", { bubbles: true, cancelable: true });
  form.element.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(false);
  expect(act).not.toHaveBeenCalled();
  wrapper.unmount();
});
test("bounded detail pages preserve independent cursors and reject foreign or malformed context", () => {
  const doc = detailFixture();
  const query = {
    members_after: "member-prev",
    invitations_after: "invite-prev",
    services_after: "",
  };
  const href = detailHref("org-a", query, { services_after: "svc-next" });
  expect(Object.fromEntries(new URL(href, "http://localhost").searchParams)).toEqual({
    ...query,
    services_after: "svc-next",
  });
  expect(() => readOrganizationDetail(doc, "other", "org-a")).toThrow();
  expect(() => readOrganizationDetail(doc, "admin", "other")).toThrow();
  for (const bad of [
    { ...doc, version: 2 },
    {
      ...doc,
      members: { entries: [...doc.members.entries, ...doc.members.entries], next_after: null },
    },
    { ...doc, services: { entries: doc.services.entries, next_after: "svc-a" } },
    { ...doc, query: { ...query, members_after: "../foreign" } },
  ])
    expect(() => readOrganizationDetail(bad, "admin", "org-a")).toThrow();
});
test("issuance is single-flight, displays its token once and dismisses it locally", async () => {
  let finish: (value: unknown) => void = () => {};
  const act = vi.fn(
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  const wrapper = mount(OrganizationDetailPanel, {
    props: {
      model: readOrganizationDetail(detailFixture(), "admin", "org-a"),
      csrfToken: "csrf",
      act,
      refresh: vi.fn(),
    },
  });
  await wrapper.get("#service_identity_display_name").setValue("Flight API");
  await wrapper.get("#service_identity_id").setValue("svc-new");
  await wrapper.get("#service-identity-form").trigger("submit");
  await wrapper.get("#service-identity-form").trigger("submit");
  expect(act).toHaveBeenCalledExactlyOnceWith("issue_service_identity", {
    display_name: "Flight API",
    service_identity_id: "svc-new",
  });
  finish({
    status: "issued",
    identity: { id: "svc-new", name: "Flight API", api_token: "ephemeral-test-token" },
  });
  await flushPromises();
  expect(wrapper.get("#issued-service-token-value").text()).toBe("ephemeral-test-token");
  await wrapper.get("#dismiss-issued-service-token").trigger("click");
  expect(wrapper.find("#issued-service-token").exists()).toBe(false);
  expect(wrapper.text()).not.toContain("ephemeral-test-token");
  await wrapper.get("#service-identity-form").trigger("submit");
  expect(act).toHaveBeenCalledOnce();
  wrapper.unmount();
});
test("uncertain issuance survives refresh without replay and curated duplicate errors retain input", async () => {
  const act = vi
    .fn()
    .mockResolvedValueOnce({
      status: "invalid",
      errors: { service_identity_id: "This identity is already in use." },
    })
    .mockRejectedValueOnce(Error("network lost"));
  const refresh = vi.fn(async () => {});
  const wrapper = mount(OrganizationDetailPanel, {
    props: {
      model: readOrganizationDetail(detailFixture(), "admin", "org-a"),
      csrfToken: "csrf",
      act,
      refresh,
    },
  });
  await wrapper.get("#service_identity_display_name").setValue("Flight API");
  await wrapper.get("#service_identity_id").setValue("svc-a");
  await wrapper.get("#service-identity-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#service_identity_id-error").text()).toContain("already in use");
  await wrapper.get("#service_identity_id").setValue("svc-new");
  await wrapper.get("#service-identity-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#service-identity-message").text()).toContain("unknown");
  await wrapper.get("#refresh-service-identities").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({
    model: readOrganizationDetail(
      { ...detailFixture(), observed_at: "2026-09-10T00:01:00Z" },
      "admin",
      "org-a",
    ),
  });
  await wrapper.get("#service-identity-form").trigger("submit");
  expect(act).toHaveBeenCalledTimes(2);
  expect(() =>
    readIssueResult({
      status: "issued",
      identity: { id: "../bad", name: "Name", api_token: "token" },
    }),
  ).toThrow();
  wrapper.unmount();
});

test("actual producer documents drive organization facts and reviewed submissions", async () => {
  const encoded = process.env.CADENCE_PLATFORM_DETAIL_DOCUMENT;
  if (!encoded) return;
  const data = JSON.parse(encoded);
  const userId = data.detail.user_id;
  const organizationId = data.detail.organization.id;
  const calls: { event: string; input: Record<string, unknown> }[] = [];
  const act = vi.fn(async (event: string, input: Record<string, unknown>) => {
    calls.push({ event, input });
    return { status: "unavailable" };
  });
  const detail = mount(OrganizationDetailPanel, {
    props: {
      model: readOrganizationDetail(data.detail, userId, organizationId),
      csrfToken: "probe-csrf",
      act,
      refresh: vi.fn(),
    },
  });
  for (const row of data.detail.members.entries)
    expect(detail.get(`#organization-member-${row.id}`).text()).toContain(row.email);
  expect(detail.get('#open-organization-form [name="organization_id"]').attributes("value")).toBe(
    organizationId,
  );
  await detail.get("#service_identity_display_name").setValue("Issued through the real form");
  await detail.get("#service_identity_id").setValue("producer-vue-service");
  await detail.get("#service-identity-form").trigger("submit");
  const invitation = mount(OrganizationInvitePanel, {
    props: {
      model: readOrganizationInvite(data.invite, userId, organizationId),
      act,
      refresh: vi.fn(),
    },
  });
  await invitation.get("#invite_email").setValue(data.recipient_email);
  await invitation.get("#invite_display_name").setValue("Reviewed operator");
  await invitation.get("#invite_membership_role").setValue("organization_admin");
  await invitation.get("#invite_grant_platform_admin").setValue(true);
  await invitation.get("#invite-form").trigger("submit");
  await flushPromises();
  expect(calls.map((call) => call.event)).toEqual(["issue_service_identity", "invite"]);
  if (!process.env.CADENCE_PLATFORM_INPUT_FILE) throw Error("Missing probe output file");
  writeFileSync(process.env.CADENCE_PLATFORM_INPUT_FILE, JSON.stringify(calls));
  detail.unmount();
  invitation.unmount();
});
