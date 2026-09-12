import { mount } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import SpacecraftListPage from "./SpacecraftListPage.vue";
import { spacecraftDirectoryFixture } from "./fixtures.test-support";
import { assertSpacecraftDirectory } from "./validation";

afterEach(() => vi.useRealTimers());
test("directory renders real roster, profile preview and compact producer breadcrumbs", () => {
  const data = spacecraftDirectoryFixture();
  assertSpacecraftDirectory(data);
  const wrapper = mount(SpacecraftListPage, { props: data });
  expect(wrapper.get("#spacecraft-one").text()).toContain("Vehicle One");
  expect(wrapper.get("#profile-one").text()).toContain("v1 × 2");
  expect(wrapper.find('a[href="/missions/mission-a"]').exists()).toBe(true);
  expect(wrapper.get("#spacecraft-tile-missing-scid").attributes("href")).toContain(
    "filter=missing_scid",
  );
  expect(wrapper.get("#spacecraft-previous-page").attributes("disabled")).toBeDefined();
  wrapper.unmount();
});
test("search, sorting and pagination preserve filters and cancel searches after unmount", async () => {
  vi.useFakeTimers();
  const navigate = vi.fn();
  const wrapper = mount(SpacecraftListPage, {
    props: { ...spacecraftDirectoryFixture(), navigate },
  });
  await wrapper.get("#spacecraft-roster-toolbar-search").setValue("Vehicle & Two");
  expect(navigate).not.toHaveBeenCalled();
  await vi.advanceTimersByTimeAsync(300);
  const query = new URL(navigate.mock.calls[0]![0], "https://cadence.test").searchParams;
  expect(Object.fromEntries(query)).toMatchObject({
    q: "Vehicle & Two",
    filter: "missing_profile",
    page: "1",
    pageSize: "1",
  });
  expect(navigate.mock.calls[0]![1]).toBe(true);
  await wrapper.get("#spacecraft-sort-scid").trigger("click");
  expect(navigate.mock.calls[1]![0]).toContain("dir=desc");
  await wrapper.get("#spacecraft-next-page").trigger("click");
  expect(navigate.mock.calls[2]![0]).toContain("page=2");
  await wrapper.get("#spacecraft-roster-toolbar-search").setValue("late");
  wrapper.unmount();
  await vi.advanceTimersByTimeAsync(300);
  expect(navigate).toHaveBeenCalledTimes(3);
});
test("empty fleet and filtered empty states remain distinct", async () => {
  const data = spacecraftDirectoryFixture();
  data.presentation.roster.rows = [];
  data.presentation.roster.filtered_empty = true;
  const wrapper = mount(SpacecraftListPage, { props: data });
  expect(wrapper.text()).toContain("No spacecraft match");
  data.presentation.roster.fleet_empty = true;
  data.presentation.profiles.empty = true;
  data.presentation.profiles.rows = [];
  await wrapper.setProps({ presentation: structuredClone(data.presentation) });
  expect(wrapper.text()).toContain("No spacecraft yet");
  expect(wrapper.find("#spacecraft-roster-toolbar-search").exists()).toBe(false);
  expect(wrapper.text()).toContain("No profiles yet");
  wrapper.unmount();
});
test("malformed rows, navigation and executable attributes are rejected", () => {
  for (const mutate of [
    (data: any) => (data.presentation.roster.rows[0].href = "javascript:alert(1)"),
    (data: any) => (data.presentation.root.attrs.onclick = "alert(1)"),
    (data: any) => (data.presentation.profiles.rows[0].fleet_entries = null),
    (data: any) => (data.presentation.roster.page_size = 0),
  ]) {
    const data = spacecraftDirectoryFixture();
    mutate(data);
    expect(() => assertSpacecraftDirectory(data)).toThrow();
  }
});
