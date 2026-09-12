import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import GroundStationDirectory from "./GroundStationDirectory.vue";
import GroundStationDetail from "./GroundStationDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import { context, directoryPayload, detailPayload } from "./read-fixtures.test-support";

test("directory consumes numeric counts, preserves query pagination and exposes creation", () => {
  const page = readDirectory(directoryPayload(), context),
    wrapper = mount(GroundStationDirectory, { props: { page } });
  try {
    expect(wrapper.get("#comms-ground-stations-directory-count").text()).toBe("2 configured");
    const next = new URL(
      wrapper.get("#comms-ground-stations-directory-next").attributes("href")!,
      "https://cadence.invalid",
    );
    expect(Object.fromEntries(next.searchParams)).toEqual({
      q: "Saved",
      page: "2",
      pageSize: "1",
      sort: "display_name",
      dir: "asc",
    });
    expect(wrapper.get("#comms-ground-stations-directory-new").attributes("href")).toBe(
      "/missions/mission-1/comms/ground-stations/new",
    );
    expect(wrapper.get("#ground_stations-ground-stations-1 a").attributes("href")).toBe(
      "/missions/mission-1/comms/ground-stations/ground-stations-1",
    );
    expect(wrapper.get("form").attributes("action")).toBe(
      "/missions/mission-1/comms/ground-stations",
    );
  } finally {
    wrapper.unmount();
  }
});
test("detail renders explicit domain facts, omits unknown data and navigates to its list", () => {
  const input = {
    ...detailPayload(),
    data: { ...detailPayload().data, secret: "must-not-render" },
  };
  const wrapper = mount(GroundStationDetail, { props: { page: readDetail(input, context) } });
  try {
    expect(wrapper.text()).toContain("Saved GroundStation");
    expect(wrapper.text()).not.toContain("must-not-render");
    expect(wrapper.text()).not.toContain("Open Phoenix surface");
    expect(wrapper.get("#comms-ground-stations-detail-back").attributes("href")).toBe(
      "/missions/mission-1/comms/ground-stations",
    );
    expect(wrapper.get("#comms-ground-station-edit").attributes("href")).toBe(
      detailPayload().data.edit_href,
    );
  } finally {
    wrapper.unmount();
  }
});
test("malformed or wrong-scope collections and details fail closed", () => {
  const duplicate = directoryPayload();
  duplicate.data.page_size = 2;
  duplicate.data.page_count = 1;
  duplicate.data.items.push(duplicate.data.items[0]);
  expect(() => readDirectory(duplicate, context)).toThrow();
  expect(() => readDirectory(directoryPayload(), { missionId: "other-mission" })).toThrow();
  const unsafe = detailPayload();
  unsafe.data.list_href = "javascript:alert(1)";
  expect(() => readDetail(unsafe, context)).toThrow();
  const missing = { ...detailPayload(), data: { id: "ground-stations-1" } };
  expect(() => readDetail(missing, context)).toThrow();
});
