import { afterEach, expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import ExplorationLegacyRedirect from "./ExplorationLegacyRedirect.vue";
let app: ReturnType<typeof mount>;
afterEach(() => app?.unmount());
test("legacy entry preserves literal query identity and alias conflicts for host admission", () => {
  const query = {
    point_id: "HK.value+raw",
    source_binding_id: "binding/a",
    sample_id: "sample+1",
    selected_time: "2026-09-07T11:00:00.123456+02:00",
    selection_view: "current",
    data_view: "original",
  };
  app = mount(ExplorationLegacyRedirect, { props: { mission_id: "mission/one", query } });
  const url = new URL(
    app.get("#exploration-open-workspace").attributes("href")!,
    "https://cadence.test",
  );
  expect(url.pathname).toBe("/missions/mission%2Fone/ops/explore");
  expect(Object.fromEntries(url.searchParams)).toEqual(query);
  expect(app.find("form").exists()).toBe(false);
});
test("malformed legacy queries cannot become a broader investigation link", async () => {
  app = mount(ExplorationLegacyRedirect, { props: { mission_id: "mission", query: {} } });
  expect(app.find("#exploration-open-workspace").exists()).toBe(true);
  for (const query of [
    null,
    [],
    { unknown: "selector" },
    { point_id: ["a"] },
    { point_id: "a\n" },
    { point_id: "x".repeat(257) },
  ]) {
    await app.setProps({ query });
    expect(app.find("#exploration-open-workspace").exists()).toBe(false);
    expect(app.get('[role="status"]').text()).toContain("unavailable");
  }
});
