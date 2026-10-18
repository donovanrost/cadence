import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import SettingsLegacyRedirect from "./SettingsLegacyRedirect.vue";

test.each([120, 121, 149, 256])(
  "preserves supported %i-byte mission and dashboard identities",
  (length) => {
    const mission = "m".repeat(length),
      dashboard = "d".repeat(length);
    const wrapper = mount(SettingsLegacyRedirect, {
      props: { mission_id: mission, dashboard_id: dashboard },
    });
    expect(wrapper.get("#settings-open-workspace").attributes("href")).toBe(
      `/missions/${mission}/ops/dashboards/${dashboard}/settings`,
    );
    wrapper.unmount();
  },
);

test.each([
  "",
  "x".repeat(257),
  ".",
  "..",
  "../forged",
  "bad\\path",
  "bad\nidentity",
  "bad\u0000identity",
  "bad?query",
  "bad#fragment",
])("contains unsupported identities without navigation: %j", async (id) => {
  const wrapper = mount(SettingsLegacyRedirect, {
    props: { mission_id: "mission", dashboard_id: id },
  });
  expect(wrapper.find("a").exists()).toBe(false);
  await wrapper.setProps({ mission_id: id, dashboard_id: "dashboard" });
  expect(wrapper.find("a").exists()).toBe(false);
  wrapper.unmount();
});

test("changing from a long identity to an invalid one removes the previous destination", async () => {
  const wrapper = mount(SettingsLegacyRedirect, {
    props: { mission_id: "mission", dashboard_id: "d".repeat(256) },
  });
  expect(wrapper.find("a").exists()).toBe(true);
  await wrapper.setProps({ dashboard_id: "d".repeat(257) });
  expect(wrapper.find("a").exists()).toBe(false);
  wrapper.unmount();
});
