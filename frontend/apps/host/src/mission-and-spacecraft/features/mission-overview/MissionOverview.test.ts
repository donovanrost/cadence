import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import MissionOverview from "./MissionOverview.vue";
import { overviewFixture } from "./fixtures.test-support";
import { assertOverview } from "./validation";
test("overview renders stable readiness rows and rejects malformed status or links", () => {
  const data = overviewFixture();
  assertOverview(data);
  const wrapper = mount(MissionOverview, { props: data });
  expect(wrapper.find("#spacecraft-readiness-sc-one").exists()).toBe(true);
  expect(wrapper.find("#sc-one-readiness-actions-trigger").exists()).toBe(true);
  wrapper.unmount();
  required(data.spacecraft_readiness[0]).primary_action_href = "//external.test";
  expect(() => assertOverview(data)).toThrow();
});
