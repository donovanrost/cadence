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
