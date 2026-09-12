import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import SpacecraftShow from "./SpacecraftShow.vue";
import { overviewFixture } from "./fixtures.test-support";
import { assertSpacecraftOverview } from "./validation";

test("shows the pinned version and links to readiness without declaring operations ready", () => {
  const data = overviewFixture();
  assertSpacecraftOverview(data);
  const wrapper = mount(SpacecraftShow, { props: data });
  expect(wrapper.get("#spacecraft-profile-binding").text()).toContain("v1");
  expect(wrapper.get("#spacecraft-profile-binding").text()).toContain("Pinned");
  expect(wrapper.get("#spacecraft-workflow-readiness").text()).toContain("Review setup");
  expect(wrapper.get("#spacecraft-workflow-readiness a").attributes("href")).toBe(
    "/missions/mission-a/spacecraft/craft-a/readiness",
  );
  expect(wrapper.text()).toContain("SCID 0");
  wrapper.unmount();
});

test("an unavailable profile retains identity editing and the rest of the overview", () => {
  const data = overviewFixture();
  Object.assign(data.profile_binding, {
    bound: false,
    title: "Pinned profile unavailable",
    version: null,
    protocols: [],
    description: "Review the spacecraft profile binding.",
    status: { tone: "blocked", label: "Unavailable" },
    view_profile_href: null,
  });
  assertSpacecraftOverview(data);
  const wrapper = mount(SpacecraftShow, { props: data });
  expect(wrapper.get("#spacecraft-profile-binding").text()).toContain("Pinned profile unavailable");
  expect(wrapper.get("#spacecraft-profile-binding a").attributes("href")).toBe(
    "/missions/mission-a/spacecraft/craft-a/identity",
  );
  expect(wrapper.find("#spacecraft-applications").exists()).toBe(true);
  wrapper.unmount();
});

test("unsafe navigation and incomplete profile contracts fail admission", () => {
  const data = overviewFixture();
  data.profile_binding.profile_action.href = "//external.example";
  expect(() => assertSpacecraftOverview(data)).toThrow();
  const missing = overviewFixture();
  delete (missing.profile_binding as Partial<typeof missing.profile_binding>).status;
  expect(() => assertSpacecraftOverview(missing)).toThrow();
});
