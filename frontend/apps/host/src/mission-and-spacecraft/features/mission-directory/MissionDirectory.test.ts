import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import MissionList from "./MissionList.vue";
import { directoryFixture } from "./fixtures.test-support";
import { assertDirectory } from "./validation";
test("directory renders real mission rows and rejects unsafe bound attributes", () => {
  const data = directoryFixture();
  assertDirectory(data);
  const wrapper = mount(MissionList, { props: data });
  expect(wrapper.get("#mission-row-mission-a a").attributes("href")).toBe("/missions/mission-a");
  wrapper.unmount();
  Object.assign(data.presentation.header.action.attrs, { onclick: "alert(1)" });
  expect(() => assertDirectory(data)).toThrow();
});

test("mission slugs are disclosed while duplicate names retain distinguishing context", async () => {
  const data = directoryFixture();
  const first = data.presentation.card.rows[0];
  if (!first) throw new Error("Fixture must contain a mission");
  first.display_name = "Flight";
  const wrapper = mount(MissionList, { props: data });
  expect(wrapper.get("#mission-row-mission-a-details").attributes("open")).toBeUndefined();
  expect(wrapper.get("#mission-list-table thead").text()).not.toContain("Slug");
  await wrapper.setProps({
    presentation: {
      ...data.presentation,
      card: {
        ...data.presentation.card,
        rows: [first, { ...first, id: "mission-row-b", slug: "flight-b", href: "/missions/b" }],
      },
    },
  });
  expect(wrapper.get("#mission-row-b p").text()).toBe("flight-b");
  wrapper.unmount();
});
