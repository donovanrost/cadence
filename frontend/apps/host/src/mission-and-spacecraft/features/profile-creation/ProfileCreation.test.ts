import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import SpacecraftTypeNew from "./SpacecraftTypeNew.vue";
import { profileFixture } from "./fixtures.test-support";
import { assertProfileForm, assertProfileResult } from "./validation";
test("protocol controls adapt while preserving the draft and selected applications", async () => {
  const data = profileFixture();
  assertProfileForm(data);
  const wrapper = mount(SpacecraftTypeNew, { props: data });
  await wrapper.get("#profile-display_name").setValue("Orbiter");
  expect(wrapper.find("#profile-secondary_header_length").exists()).toBe(true);
  expect(wrapper.find("#profile-insert_zone_length").exists()).toBe(false);
  await wrapper.get("#profile-downlink_protocol").setValue("aos");
  expect(wrapper.find("#profile-secondary_header_length").exists()).toBe(false);
  await wrapper.get("#profile-insert_zone_length").setValue("8");
  await wrapper.get("#profile-downlink_protocol").setValue("uslp");
  expect(wrapper.find("#profile-truncated_primary_header").exists()).toBe(true);
  await wrapper.get("#app-telemetry").setValue(true);
  await wrapper.setProps(profileFixture());
  await wrapper.get("#spacecraft-profile-form").trigger("submit");
  expect(required(wrapper.emitted("save")).at(-1)).toMatchObject([
    {
      spacecraft_type: {
        display_name: "Orbiter",
        downlink_protocol: "uslp",
        insert_zone_length: 8,
        applications: { telemetry_decom: "1" },
      },
    },
  ]);
  wrapper.unmount();
});
test("contracts reject malformed controls, protocol choices, applications and links", () => {
  const unsafe = profileFixture();
  unsafe.form.actions.cancel.href = "javascript:alert(1)";
  expect(() => assertProfileForm(unsafe)).toThrow();
  const choices = profileFixture();
  required(choices.options.downlink_protocols[0]).value = "unknown";
  expect(() => assertProfileForm(choices)).toThrow();
  const selected = profileFixture();
  selected.form.fields.applications.value = { unknown: "1" };
  expect(() => assertProfileForm(selected)).toThrow();
  expect(() =>
    assertProfileResult({ status: "invalid", errors: { arbitrary: ["bad"] } }),
  ).toThrow();
});
