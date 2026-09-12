import { writeFileSync } from "node:fs";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OrganizationCreatePanel from "./OrganizationCreatePanel.vue";
import OrganizationDirectoryPanel from "../organization-directory/OrganizationDirectoryPanel.vue";
import PlatformOverviewPanel from "../platform-overview/PlatformOverviewPanel.vue";
import { readPlatformOverview } from "../platform-overview/contracts";
import { readOrganizationDirectory } from "../organization-directory/contracts";
import { readOrganizationCreate, readResult } from "./contracts";
const fixture = () => ({
  version: 1,
  user_id: "admin",
  observed_at: "2026-09-10T01:00:00Z",
  created: null,
});
const created = { id: "org-created", name: "Flight operations", slug: "flight" };
async function fill(wrapper: ReturnType<typeof mount>) {
  await wrapper.get("#organization_display_name").setValue("Flight operations");
  await wrapper.get("#organization_slug").setValue("flight");
}
test("creation emits only reviewed fields once and success replaces the form with canonical navigation", async () => {
  let finish: (value: unknown) => void = () => {};
  const act = vi.fn(
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  const wrapper = mount(OrganizationCreatePanel, {
    props: { model: readOrganizationCreate(fixture(), "admin"), act, refresh: vi.fn() },
  });
  await fill(wrapper);
  await wrapper.get("#org-form").trigger("submit");
  await wrapper.get("#org-form").trigger("submit");
  expect(act).toHaveBeenCalledTimes(1);
  expect(act).toHaveBeenCalledWith("create", { display_name: "Flight operations", slug: "flight" });
  expect(wrapper.get("#admin-organization-create-submit").attributes("disabled")).toBeDefined();
  finish({ status: "created", organization: created });
  await flushPromises();
  expect(wrapper.find("#org-form").exists()).toBe(false);
  expect(wrapper.get("#admin-organization-created-link").attributes("href")).toBe(
    "/admin/organizations/org-created",
  );
  wrapper.unmount();
});
test("server validation preserves input, enables a corrected submission and rejects malformed results", async () => {
  const act = vi
    .fn()
    .mockResolvedValueOnce({ status: "invalid", errors: { slug: "This slug is already in use." } })
    .mockResolvedValueOnce({ status: "created", organization: created });
  const wrapper = mount(OrganizationCreatePanel, {
    props: { model: readOrganizationCreate(fixture(), "admin"), act, refresh: vi.fn() },
  });
  await fill(wrapper);
  await wrapper.get("#org-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#organization_slug-error").text()).toContain("already in use");
  expect((wrapper.get("#organization_display_name").element as HTMLInputElement).value).toBe(
    "Flight operations",
  );
  await wrapper.get("#organization_slug").setValue("another");
  await wrapper.get("#org-form").trigger("submit");
  await flushPromises();
  expect(act).toHaveBeenLastCalledWith("create", {
    display_name: "Flight operations",
    slug: "another",
  });
  expect(() =>
    readResult({ status: "created", organization: { ...created, id: "../evil" } }),
  ).toThrow();
  expect(() => readResult({ status: "invalid", errors: { script: "message" } })).toThrow();
  wrapper.unmount();
});
test("unknown transport retains the draft and blocks replay through refresh until completion is observed", async () => {
  const act = vi.fn().mockRejectedValue(new Error("network lost"));
  const refresh = vi.fn(async () => {});
  const wrapper = mount(OrganizationCreatePanel, {
    props: { model: readOrganizationCreate(fixture(), "admin"), act, refresh },
  });
  await fill(wrapper);
  await wrapper.get("#org-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#admin-organization-create-message").text()).toContain("unknown");
  await wrapper.get("#admin-organization-create-refresh").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({
    model: readOrganizationCreate({ ...fixture(), observed_at: "2026-09-10T01:01:00Z" }, "admin"),
  });
  await wrapper.get("#org-form").trigger("submit");
  expect(act).toHaveBeenCalledTimes(1);
  await wrapper.setProps({ model: readOrganizationCreate({ ...fixture(), created }, "admin") });
  expect(wrapper.find("#admin-organization-created").exists()).toBe(true);
  wrapper.unmount();
});
test("actual producer documents reach all three owner components and the submitted fields", async () => {
  const encoded = process.env.CADENCE_PLATFORM_DOCUMENT;
  if (!encoded) return;
  const data = JSON.parse(encoded);
  const userId = data.creation.user_id;
  const overview = mount(PlatformOverviewPanel, {
    props: { model: readPlatformOverview(data.overview, userId) },
  });
  expect(overview.get("#admin-home-organizations-card").text()).toContain(
    String(data.overview.counts.organizations),
  );
  const directory = mount(OrganizationDirectoryPanel, {
    props: { model: readOrganizationDirectory(data.directory, userId) },
  });
  expect(
    directory.findAll("#admin-organization-list-component li a").map((a) => a.attributes("href")),
  ).toEqual(
    data.directory.organizations.map(
      (org: { id: string }) => `/admin/organizations/${encodeURIComponent(org.id)}`,
    ),
  );
  const act = vi.fn(async () => ({ status: "unavailable" }));
  const form = mount(OrganizationCreatePanel, {
    props: { model: readOrganizationCreate(data.creation, userId), act, refresh: vi.fn() },
  });
  await form.get("#organization_display_name").setValue("Created through the real form");
  await form.get("#organization_slug").setValue("created-through-vue");
  await form.get("#org-form").trigger("submit");
  await flushPromises();
  expect(act).toHaveBeenCalledOnce();
  if (!process.env.CADENCE_PLATFORM_INPUT_FILE) throw Error("Missing probe output file");
  writeFileSync(
    process.env.CADENCE_PLATFORM_INPUT_FILE,
    JSON.stringify((act.mock.calls[0] as unknown as [string, unknown])[1]),
  );
  overview.unmount();
  directory.unmount();
  form.unmount();
});
