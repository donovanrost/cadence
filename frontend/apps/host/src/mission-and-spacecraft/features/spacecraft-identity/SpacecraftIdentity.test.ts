import { required } from "../../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import SpacecraftIdentityForm from "./SpacecraftIdentityForm.vue";
import { identityFixture } from "./fixtures.test-support";
import { assertIdentityForm, assertIdentityResult, assertNewIdentityForm } from "./validation";

test("editing preserves a current pin and offers an explicit newer version or None", async () => {
  const data = identityFixture(true);
  assertIdentityForm(data);
  const wrapper = mount(SpacecraftIdentityForm, { props: data });
  const select = wrapper.get("#spacecraft-edit-spacecraft-type-id");
  expect((select.element as HTMLSelectElement).value).toBe(JSON.stringify(["profile-one", 1]));
  await wrapper.get("#spacecraft-edit-form").trigger("submit");
  expect(required(wrapper.emitted("save"))[0]).toEqual([
    {
      spacecraft: {
        display_name: "Vehicle One",
        scid: "42",
        spacecraft_type_id: "profile-one",
        spacecraft_type_version: 1,
      },
    },
  ]);
  await select.setValue(JSON.stringify(["profile-one", 2]));
  expect(required(wrapper.emitted("validate")).at(-1)).toMatchObject([
    { spacecraft: { spacecraft_type_id: "profile-one", spacecraft_type_version: 2 } },
  ]);
  await select.setValue(JSON.stringify(["", null]));
  expect(required(wrapper.emitted("validate")).at(-1)).toMatchObject([
    { spacecraft: { spacecraft_type_id: "", spacecraft_type_version: null } },
  ]);
  wrapper.unmount();
});

test("identity edits preserve reviewed framing and link back to its configuration workspace", async () => {
  const data = identityFixture(true);
  const path = "/missions/mission-a/spacecraft/vehicle-one";
  data.page.breadcrumbs.push({ label: "Vehicle One", href: path });
  data.form.configuration_href = `${path}?section=communications`;
  assertIdentityForm(data);
  const wrapper = mount(SpacecraftIdentityForm, { props: data });
  expect(wrapper.find("select").exists()).toBe(false);
  expect(wrapper.get("#spacecraft-identity-communications-link").attributes("href")).toBe(
    `${path}?section=communications`,
  );
  await wrapper.get("#spacecraft-edit-display-name").setValue("Renamed");
  await wrapper.get("#spacecraft-edit-form").trigger("submit");
  expect(required(wrapper.emitted("save"))[0]).toMatchObject([
    {
      spacecraft: {
        display_name: "Renamed",
        spacecraft_type_id: "profile-one",
        spacecraft_type_version: 1,
      },
    },
  ]);
  data.form.configuration_href = "/missions/mission-a/spacecraft/other?section=communications";
  expect(() => assertIdentityForm(data)).toThrow("Invalid spacecraft configuration link");
  wrapper.unmount();
});

test("SCID and profile validation errors are visible and linked to their controls", async () => {
  const wrapper = mount(SpacecraftIdentityForm, {
    props: {
      ...identityFixture(),
      errors: {
        scid: ["has already been taken"],
        spacecraft_type_version: ["Select an available version"],
      },
    },
  });
  for (const [field, message] of [
    ["scid", "has already been taken"],
    ["spacecraft-type-id", "Select an available version"],
  ]) {
    const control = wrapper.get(`#spacecraft-${field}`);
    expect(control.attributes("aria-invalid")).toBe("true");
    const errors = wrapper.get(`#${control.attributes("aria-describedby")}`);
    expect(errors.attributes("role")).toBe("alert");
    expect(errors.text()).toBe(message);
  }
  wrapper.unmount();
});

test("contracts reject wrong page identity, missing selected versions and unsafe navigation", () => {
  expect(() => assertNewIdentityForm(identityFixture(true))).toThrow();
  const missing = identityFixture(true);
  missing.profile_options.options = missing.profile_options.options.filter(
    (option) => option.version !== 1,
  );
  expect(() => assertIdentityForm(missing)).toThrow();
  const unsafe = identityFixture();
  unsafe.form.actions.cancel.href = "javascript:alert(1)";
  expect(() => assertIdentityForm(unsafe)).toThrow();
  expect(() => assertIdentityResult({ status: "ok", errors: { other: ["unexpected"] } })).toThrow();
});
