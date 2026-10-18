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

test("readiness puts names, SCID and setup meaning ahead of collapsed diagnostic identities", () => {
  const data = overviewFixture();
  const row = required(data.spacecraft_readiness[0]);
  row.endpoint_label = "Telemetry identity";
  row.endpoint_ref_label = "spacecraft_runtime:sc-one/full-original-value";
  row.scid_label = "42";
  const wrapper = mount(MissionOverview, { props: data });
  const details = wrapper.get("#spacecraft-readiness-sc-one-details");
  expect(details.attributes("open")).toBeUndefined();
  expect(details.text()).toContain(row.endpoint_ref_label);
  expect(wrapper.get("#mission-spacecraft-readiness thead").text()).not.toContain(
    "Runtime Identity",
  );
  expect(wrapper.get("#spacecraft-readiness-sc-one").text()).toContain("SC One");
  expect(wrapper.get("#spacecraft-readiness-sc-one").text()).toContain("42");
  expect(wrapper.get("#spacecraft-readiness-sc-one").text()).toContain(
    "Telemetry identity: Configured",
  );
  expect(wrapper.get("#mission-technical-details").text()).toContain(data.overview.mission.slug);
  wrapper.unmount();
});

test("missing human names and runtime identity keep a useful fallback without copying placeholder text", () => {
  const data = overviewFixture();
  required(data.spacecraft_readiness[0]).spacecraft_display_name = " ";
  const wrapper = mount(MissionOverview, { props: data });
  expect(wrapper.get("#spacecraft-readiness-sc-one .font-medium").text()).toBe("sc-one");
  expect(wrapper.get("#spacecraft-readiness-sc-one-details").findAll("button")).toHaveLength(1);
  expect(wrapper.get("#spacecraft-readiness-sc-one").text()).toContain(
    "Telemetry identity: Missing",
  );
  wrapper.unmount();
});
