import type { ProfileDirectory } from "./contracts";
import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import SpacecraftTypeShow from "./SpacecraftTypeShow.vue";
import SpacecraftTypeListPage from "./SpacecraftTypeListPage.vue";
import { assertProfileDetail, assertProfileDirectory } from "./validation";
import { profileDetailFixture } from "./fixtures.test-support";

test("profile detail consumes producer navigation, labels and immutable version history", () => {
  const data = profileDetailFixture();
  assertProfileDetail(data);
  const wrapper = mount(SpacecraftTypeShow, { props: data });
  expect(wrapper.find('a[href="/missions/mission-a/spacecraft/profiles"]').exists()).toBe(true);
  expect(wrapper.get("#spacecraft-profile-byte-interpretation").text()).toContain(
    "Downlink Protocol",
  );
  expect(wrapper.get("#frame-length").text()).toContain("1024");
  expect(wrapper.get("#version-1").text()).toContain("v1");
  expect(wrapper.get("#version-2").text()).toContain("v2");
  wrapper.unmount();
});
test("profile directory renders empty and populated producer states", async () => {
  const element = { attrs: {} };
  const data: { presentation: ProfileDirectory } = {
    presentation: {
      root: element,
      header: {
        ...element,
        body: element,
        content: element,
        title: { ...element, text: "Profiles" },
        subtitle: { ...element, text: "0 profiles" },
        actions: {
          ...element,
          new_profile: {
            id: "new-profile",
            label: "New Profile",
            href: "/missions/a/spacecraft/profiles/new",
          },
        },
      },
      empty_state: { title: "No Profiles", description: "Create a profile." },
      card: null,
    },
  };
  assertProfileDirectory(data);
  const wrapper = mount(SpacecraftTypeListPage, { props: data });
  expect(wrapper.text()).toContain("No Profiles");
  data.presentation.empty_state = null;
  data.presentation.card = {
    ...element,
    body: element,
    list_component: element,
    rows: [
      {
        id: "profile-a",
        display_name: "Profile A",
        version: "v1",
        downlink_protocol: "TM",
        uplink_protocol: "TC",
        applications: "",
        href: "/missions/a/spacecraft/profiles/a",
      },
    ],
  };
  assertProfileDirectory(data);
  await wrapper.setProps({ presentation: structuredClone(data.presentation) });
  expect(wrapper.get("#profile-a").text()).toContain("Profile A");
  wrapper.unmount();
});
test("incomplete labels and unsafe profile navigation fail contract admission", () => {
  const data = profileDetailFixture();
  // @ts-expect-error Missing required producer labels must fail admission.
  delete data.labels.downlink_protocol;
  expect(() => assertProfileDetail(data)).toThrow();
  const unsafe = profileDetailFixture();
  required(unsafe.navigation.breadcrumbs[0]).href = "//external.example";
  expect(() => assertProfileDetail(unsafe)).toThrow();
});
