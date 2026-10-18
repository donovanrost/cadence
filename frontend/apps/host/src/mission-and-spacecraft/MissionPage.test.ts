import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import MissionPage from "./MissionPage.vue";
import { directoryFixture } from "./features/mission-directory/fixtures.test-support";
test("invalid and unavailable mission snapshots are contained and refresh can recover", async () => {
  const refresh = vi.fn();
  const ready = { page: "mission_list", version: 1, status: "ready", data: directoryFixture() };
  const wrapper = mount(MissionPage, {
    props: { page: "mission_list", snapshot: null, execute: vi.fn(), refresh },
  });
  for (const snapshot of [
    null,
    {},
    { ...ready, version: 2 },
    { ...ready, page: "mission_new" },
    { ...ready, data: {} },
    { ...ready, status: "unavailable" },
  ]) {
    await wrapper.setProps({ snapshot });
    expect(wrapper.find("#core-mission-error").exists()).toBe(true);
    expect(wrapper.find("#mission-list-table").exists()).toBe(false);
  }
  await wrapper.get("#core-mission-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({ snapshot: ready });
  expect(wrapper.find("#mission-row-mission-a").exists()).toBe(true);
  wrapper.unmount();
});
