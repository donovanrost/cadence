import { mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import SpacecraftPage from "./SpacecraftPage.vue";
import { spacecraftDirectoryFixture } from "./features/spacecraft-directory/fixtures.test-support";
test("invalid and unavailable spacecraft snapshots are contained and refresh can recover", async () => {
  const refresh = vi.fn();
  const ready = {
    page: "spacecraft_list",
    version: 1,
    status: "ready",
    data: spacecraftDirectoryFixture(),
  };
  const wrapper = mount(SpacecraftPage, {
    props: { page: "spacecraft_list", snapshot: null, navigate: vi.fn(), refresh },
  });
  for (const snapshot of [
    null,
    {},
    { ...ready, version: 2 },
    { ...ready, page: "profile_list" },
    { ...ready, data: {} },
    { ...ready, status: "unavailable" },
  ]) {
    await wrapper.setProps({ snapshot });
    expect(wrapper.find("#core-spacecraft-error").exists()).toBe(true);
    expect(wrapper.find("#spacecraft-list-content").exists()).toBe(false);
  }
  await wrapper.get("#core-spacecraft-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({ snapshot: ready });
  expect(wrapper.find("#spacecraft-one").exists()).toBe(true);
  wrapper.unmount();
});
