import { required } from "../../../../test-support/required";
import { afterEach, expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import type { Component } from "vue";
import Library from "../features/library/LibraryLegacyRedirect.vue";
import Playlists from "../features/playlists/PlaylistsLegacyRedirect.vue";
import Presentation from "../features/playlists/PlaylistPresentationLegacyRedirect.vue";
import Activity from "../features/activity/ActivityLegacyRedirect.vue";

let app: Pick<ReturnType<typeof mount>, "find" | "get" | "setProps" | "unmount">;
afterEach(() => app?.unmount());

const cases: [Component, Record<string, unknown>, string][] = [
  [Library, {}, "library"],
  [Playlists, {}, "playlists"],
  [
    Activity,
    {
      dashboard_id: "dashboard/a?+",
      query: { version: "9007199254740990", selected_publish_issue: "issue/a?+🌍" },
    },
    "dashboard%2Fa%3F%2B/activity",
  ],
  [
    Presentation,
    { playlist_id: "playlist/a?+", query: { index: "99" } },
    "playlists/playlist%2Fa%3F%2B/present",
  ],
];

test.each(cases)(
  "preserves exact identities through a domain-owned destination",
  (component, supplied, path) => {
    const props = { mission_id: "mission/a?+🌍", query: {}, ...supplied };
    app = mount(component, { props, attrs: { onclick: "untrusted", "data-raw": "raw" } });
    const url = new URL(required(app.get("a").attributes("href")), "https://cadence.test");
    expect(url.pathname).toBe(
      `/missions/${encodeURIComponent(props.mission_id)}/ops/dashboards/${path}`,
    );
    expect(Object.fromEntries(url.searchParams)).toEqual(props.query);
    expect(app.find("form, button, iframe, [onclick], [data-raw]").exists()).toBe(false);
  },
);

test.each(cases)(
  "rejects missing or malformed destination identity",
  async (component, supplied) => {
    app = mount(component, { props: { mission_id: "mission", query: {}, ...supplied } });
    for (const mission_id of [undefined, "", ".", "..", "bad\n", "x".repeat(257), "\ud800"]) {
      await app.setProps({ mission_id });
      expect(app.find("a").exists()).toBe(false);
      expect(app.get('[role="status"]').text()).toContain("unavailable");
    }
    await app.setProps({ mission_id: "mission" });
    for (const query of [undefined, null, [], { unknown: "selector" }, { version: ["1"] }]) {
      await app.setProps({ query });
      expect(app.find("a").exists()).toBe(false);
    }
  },
);

test("does not broaden invalid activity selection to latest history", async () => {
  app = mount(Activity, { props: { mission_id: "mission", dashboard_id: "dashboard", query: {} } });
  for (const query of [
    { version: "0" },
    { version: "01" },
    { version: "9007199254740991" },
    { version: 1 },
    { selected_publish_issue: "" },
    { selected_publish_issue: "bad\n" },
    { issue_id: "renamed" },
  ]) {
    await app.setProps({ query });
    expect(app.find("a").exists()).toBe(false);
  }
  await app.setProps({ query: { version: "1" }, dashboard_id: "" });
  expect(app.find("a").exists()).toBe(false);
});

test("does not substitute a different playlist or position", async () => {
  app = mount(Presentation, {
    props: { mission_id: "mission", playlist_id: "playlist", query: {} },
  });
  for (const index of ["-1", "01", "100", "1.1", 1]) {
    await app.setProps({ query: { index } });
    expect(app.find("a").exists()).toBe(false);
  }
  await app.setProps({ query: { index: "0" }, playlist_id: "" });
  expect(app.find("a").exists()).toBe(false);
});
