import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import SpacecraftIdentityPage from "./SpacecraftIdentityPage.vue";
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
  expect(wrapper.emitted("save")![0]).toEqual([
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
  expect(wrapper.emitted("validate")!.at(-1)).toMatchObject([
    { spacecraft: { spacecraft_type_id: "profile-one", spacecraft_type_version: 2 } },
  ]);
  await select.setValue(JSON.stringify(["", null]));
  expect(wrapper.emitted("validate")!.at(-1)).toMatchObject([
    { spacecraft: { spacecraft_type_id: "", spacecraft_type_version: null } },
  ]);
  wrapper.unmount();
});

test("server refreshes and out-of-order validation replies do not erase drafts or replace newer errors", async () => {
  const replies: ((value: unknown) => void)[] = [];
  const execute = vi.fn(() => new Promise((resolve) => replies.push(resolve)));
  const wrapper = mount(SpacecraftIdentityPage, { props: { data: identityFixture(), execute } });
  await wrapper.get("#spacecraft-display-name").setValue("First");
  await wrapper.get("#spacecraft-display-name").setValue("Latest");
  await wrapper.setProps({ data: identityFixture() });
  replies[1]!({ status: "invalid", errors: { display_name: ["Current error"] } });
  await flushPromises();
  replies[0]!({ status: "invalid", errors: { display_name: ["Old error"] } });
  await flushPromises();
  expect((wrapper.get("#spacecraft-display-name").element as HTMLInputElement).value).toBe(
    "Latest",
  );
  expect(wrapper.get("#spacecraft-display-name-errors").text()).toBe("Current error");
  expect(wrapper.get("#spacecraft-display-name").attributes("aria-invalid")).toBe("true");
  wrapper.unmount();
});

test("a pending save disables repeat submits and failure retains values for retry", async () => {
  let reject!: (reason?: unknown) => void;
  const execute = vi.fn((event: string) =>
    event === "save"
      ? new Promise((_resolve, no) => {
          reject = no;
        })
      : Promise.resolve({ status: "ok", errors: {} }),
  );
  const wrapper = mount(SpacecraftIdentityPage, { props: { data: identityFixture(), execute } });
  await wrapper.get("#spacecraft-display-name").setValue("Vehicle");
  await flushPromises();
  await wrapper.get("#spacecraft-form").trigger("submit");
  expect(wrapper.get("#create-spacecraft-button").attributes("disabled")).toBeDefined();
  await wrapper.get("#spacecraft-form").trigger("submit");
  expect(execute.mock.calls.filter(([event]) => event === "save")).toHaveLength(1);
  reject(new Error("private transport details"));
  await flushPromises();
  expect(wrapper.get("#spacecraft-identity-error").text()).not.toContain("private");
  expect(wrapper.get("#create-spacecraft-button").attributes("disabled")).toBeUndefined();
  expect((wrapper.get("#spacecraft-display-name").element as HTMLInputElement).value).toBe(
    "Vehicle",
  );
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
