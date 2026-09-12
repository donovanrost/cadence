import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import RoutingDirectory from "./RoutingDirectory.vue";
import RoutingDetail from "./RoutingDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import { context, directoryPayload, detailPayload } from "./read-fixtures.test-support";

test("directory consumes numeric counts, preserves query pagination and exposes creation", () => {
  const page = readDirectory(directoryPayload(), context),
    wrapper = mount(RoutingDirectory, { props: { page } });
  try {
    expect(wrapper.get("#comms-routing-directory-count").text()).toBe("2 configured");
    const next = new URL(
      wrapper.get("#comms-routing-directory-next").attributes("href")!,
      "https://cadence.invalid",
    );
    expect(Object.fromEntries(next.searchParams)).toEqual({
      q: "Saved",
      page: "2",
      pageSize: "1",
      sort: "display_name",
      dir: "asc",
    });
    expect(wrapper.get("#comms-routing-directory-new").attributes("href")).toBe(
      "/missions/mission-1/comms/routing/new",
    );
    expect(wrapper.get("#routing-routing-1 a").attributes("href")).toBe(
      "/missions/mission-1/comms/routing/routing-1",
    );
    expect(wrapper.get("form").attributes("action")).toBe("/missions/mission-1/comms/routing");
  } finally {
    wrapper.unmount();
  }
});
test("detail renders explicit domain facts, omits unknown data and navigates to its list", () => {
  const input = {
    ...detailPayload(),
    data: { ...detailPayload().data, secret: "must-not-render" },
  };
  const wrapper = mount(RoutingDetail, { props: { page: readDetail(input, context) } });
  try {
    expect(wrapper.text()).toContain("Saved Routing");
    expect(wrapper.text()).not.toContain("must-not-render");
    expect(wrapper.text()).not.toContain("Open Phoenix surface");
    expect(wrapper.get("#comms-routing-detail-back").attributes("href")).toBe(
      "/missions/mission-1/comms/routing",
    );
    expect(wrapper.text()).toContain("Pinned transport version");
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
  const missing = { ...detailPayload(), data: { id: "routing-1" } };
  expect(() => readDetail(missing, context)).toThrow();
});
