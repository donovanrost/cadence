import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { expect, test } from "vite-plus/test";
import OrganizationDirectoryPanel from "./OrganizationDirectoryPanel.vue";
import { readOrganizationDirectory } from "./contracts";
const fixture = () => ({
  version: 1,
  user_id: "admin",
  observed_at: "2026-09-10T01:00:00Z",
  limit: 50,
  query: {},
  organizations: [{ id: "org-a", name: "Flight & Test", slug: "A + & Test" }],
  next_cursor: null,
});
test("directory owns canonical links and encodes continuation without arbitrary navigation", () => {
  const doc = fixture();
  const wrapper = mount(
    pageHeaderHarness("/admin/organizations").stage(OrganizationDirectoryPanel),
    {
      props: { model: readOrganizationDirectory(doc, "admin") },
    },
  );
  expect(wrapper.get("#admin-organization-org-a a").attributes("href")).toBe(
    "/admin/organizations/org-a",
  );
  expect(wrapper.get("#admin-organizations-create").attributes("href")).toBe(
    "/admin/organizations/new",
  );
  expect(wrapper.find("#admin-organizations-next").exists()).toBe(false);
  wrapper.unmount();
  const organizations = Array.from({ length: 50 }, (_, i) => ({
    id: `org-${i}`,
    name: `Org ${i}`,
    slug: i === 49 ? "A + & Test" : `slug-${i}`,
  }));
  const page = {
    ...doc,
    organizations,
    next_cursor: { after_id: "org-49", after_slug: "A + & Test" },
  };
  const paged = mount(pageHeaderHarness("/admin/organizations").stage(OrganizationDirectoryPanel), {
    props: { model: readOrganizationDirectory(page, "admin") },
  });
  const href = paged.get("#admin-organizations-next").attributes("href");
  expect(Object.fromEntries(new URL(required(href), "http://localhost").searchParams)).toEqual(
    page.next_cursor,
  );
  paged.unmount();
});
test("empty pages and malformed cursor, identities and duplicate rows fail precisely", () => {
  const doc = fixture();
  const empty = mount(pageHeaderHarness("/admin/organizations").stage(OrganizationDirectoryPanel), {
    props: { model: readOrganizationDirectory({ ...doc, organizations: [] }, "admin") },
  });
  expect(empty.find("#admin-organizations-empty").exists()).toBe(true);
  expect(empty.find("#admin-organizations-create").exists()).toBe(true);
  empty.unmount();
  for (const bad of [
    { ...doc, organizations: [...doc.organizations, ...doc.organizations] },
    { ...doc, organizations: [{ ...doc.organizations[0], id: "../foreign" }] },
    { ...doc, next_cursor: { after_id: "org-a", after_slug: "A + & Test" } },
    { ...doc, query: { after_id: "missing" } },
    { ...doc, limit: 100 },
  ])
    expect(() => readOrganizationDirectory(bad, "admin")).toThrow();
  expect(() => readOrganizationDirectory(doc, "other")).toThrow();
});
