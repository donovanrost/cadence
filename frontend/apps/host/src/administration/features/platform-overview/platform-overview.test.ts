import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import PlatformOverviewPanel from "./PlatformOverviewPanel.vue";
import PlatformAdministrationPage from "../../PlatformAdministrationPage.vue";
import { readPlatformOverview } from "./contracts";
const fixture = () => ({
  version: 1,
  user_id: "admin",
  observed_at: "2026-09-10T01:00:00.000000Z",
  counts: { organizations: 53, active_users: 2 },
});
test("overview uses actual counts and implemented destinations", () => {
  const wrapper = mount(PlatformOverviewPanel, {
    props: { model: readPlatformOverview(fixture(), "admin") },
  });
  expect(wrapper.get("#admin-home-organizations-card").text()).toContain("53");
  expect(wrapper.get("#admin-home-users-card").text()).toContain("2");
  expect(wrapper.findAll("a").map((a) => a.attributes("href"))).toEqual([
    "/admin/organizations",
    "/admin/runtime",
    "/admin/organizations/new",
  ]);
  expect(wrapper.findAll("button")).toHaveLength(0);
  expect(wrapper.text()).not.toContain("Coming Soon");
  wrapper.unmount();
});
test("unknown pages, unsupported versions, bad counts and another administrator stay contained", async () => {
  const refresh = vi.fn(async () => {});
  const ready = {
    version: 1,
    page: "platform_overview",
    status: "ready",
    user_id: "admin",
    action_token: "visit-1",
    data: fixture(),
  };
  const wrapper = mount(PlatformAdministrationPage, {
    props: { page: "platform_overview", userId: "admin", snapshot: null, act: vi.fn(), refresh },
  });
  for (const snapshot of [
    null,
    { ...ready, version: 2 },
    { ...ready, user_id: "other" },
    { ...ready, data: { ...fixture(), counts: { organizations: -1, active_users: 2 } } },
    { ...ready, status: "unavailable" },
  ]) {
    await wrapper.setProps({ snapshot });
    expect(wrapper.find("#core-platform-administration-error").exists()).toBe(true);
    expect(wrapper.find("#admin-home").exists()).toBe(false);
  }
  await wrapper.get("#core-platform-administration-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({ snapshot: ready });
  expect(wrapper.find("#admin-home").exists()).toBe(true);
  await wrapper.setProps({ page: "unregistered-page" });
  expect(wrapper.find("#core-platform-administration-error").exists()).toBe(true);
  wrapper.unmount();
});
