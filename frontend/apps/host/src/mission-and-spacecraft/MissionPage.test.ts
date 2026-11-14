import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import MissionPage from "./MissionPage.vue";
import { overviewFixture } from "./features/mission-overview/fixtures.test-support";
test("invalid and unavailable mission snapshots are contained and refresh can recover", async () => {
  const refresh = vi.fn();
  const ready = { page: "mission_overview", version: 1, status: "ready", data: overviewFixture() };
  const wrapper = mount(MissionPage, {
    props: { page: "mission_overview", snapshot: null, refresh },
  });
  for (const snapshot of [
    null,
    {},
    { ...ready, version: 2 },
    { ...ready, page: "unregistered_page" },
    { ...ready, data: {} },
    { ...ready, status: "unavailable" },
  ]) {
    await wrapper.setProps({ snapshot });
    expect(wrapper.find("#core-mission-error").exists()).toBe(true);
    expect(wrapper.find("#spacecraft-readiness-section").exists()).toBe(false);
  }
  await wrapper.get("#core-mission-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({ snapshot: ready });
  expect(wrapper.find("#spacecraft-readiness-sc-one").exists()).toBe(true);
  wrapper.unmount();
});
