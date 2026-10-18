import { required } from "../../../../../test-support/required";
import { afterEach, expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import OpsDashboardShow from "./OpsDashboardShow.vue";
let app: Pick<ReturnType<typeof mount>, "find" | "get" | "setProps" | "unmount">;
afterEach(() => app?.unmount());

test("viewer compatibility preserves runtime selectors and unsupported drilldown identity verbatim", () => {
  const query = {
    time_mode: "range",
    from: "2026-09-10T12:00:00Z",
    to: "2026-09-10T13:00:00Z",
    selected_resource_id: "resource/a?+🌍",
    selected_data_view: "original",
  };
  app = mount(OpsDashboardShow, {
    props: { mission_id: "mission/a", dashboard_id: "dashboard/a?+", mode: "view", query },
  });
  const url = new URL(required(app.get("a").attributes("href")), "https://cadence.test");
  expect(url.pathname).toBe("/missions/mission%2Fa/ops/dashboards/dashboard%2Fa%3F%2B");
  expect(Object.fromEntries(url.searchParams)).toEqual(query);
  expect(app.find("form, button, .grid-stack, #ops-dashboard-canvas").exists()).toBe(false);
});

test("editor compatibility opens the exact governed editor without a duplicate canvas", () => {
  app = mount(OpsDashboardShow, {
    props: { mission_id: "mission", dashboard_id: "dashboard", mode: "edit", query: {} },
  });
  expect(app.get("a").attributes("href")).toBe("/missions/mission/ops/dashboards/dashboard/edit");
  expect(app.get("h1").text()).toBe("Edit Dashboard");
  expect(app.find("form, button, .grid-stack").exists()).toBe(false);
});

test("malformed selectors and modes cannot become broader viewer or editor links", async () => {
  app = mount(OpsDashboardShow, {
    props: { mission_id: "mission", dashboard_id: "dashboard", mode: "view", query: {} },
  });
  for (const mode of [undefined, "", "new", ["view"], 1]) {
    await app.setProps({ mode });
    expect(app.find("a").exists()).toBe(false);
  }
  await app.setProps({ mode: "view" });
  for (const query of [
    undefined,
    null,
    [],
    { unknown: "a" },
    { selected_resource_id: ["one"] },
    { selected_widget: "bad\n" },
  ]) {
    await app.setProps({ query });
    expect(app.find("a").exists()).toBe(false);
  }
  await app.setProps({ mode: "edit", query: { panel: "history" } });
  expect(app.find("a").exists()).toBe(false);
  await app.setProps({ mode: "view", query: {} });
  for (const dashboard_id of [undefined, "", ".", "..", "bad\n", "x".repeat(257)]) {
    await app.setProps({ dashboard_id });
    expect(app.find("a").exists()).toBe(false);
  }
});
