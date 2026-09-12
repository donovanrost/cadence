import { required } from "../../../../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import MissionCreationPage from "./MissionCreationPage.vue";
import { creationFixture } from "./fixtures.test-support";
import { assertCreation } from "./validation";

test("creation validates its DTO and retains edits while ignoring older validation results", async () => {
  const data = creationFixture();
  assertCreation(data);
  const resolve: Array<(value: unknown) => void> = [];
  const execute = vi.fn(() => new Promise<unknown>((done) => resolve.push(done)));
  const wrapper = mount(MissionCreationPage, { props: { data, execute } });
  await wrapper.get("#mission_display_name").setValue("First");
  await wrapper.get("#mission_display_name").setValue("Latest");
  required(resolve[1])({ status: "ok", errors: {} });
  await flushPromises();
  required(resolve[0])({ status: "invalid", errors: { display_name: ["Stale error"] } });
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.get<HTMLInputElement>("#mission_display_name").element.value).toBe("Latest");
  expect(wrapper.get("#cancel-mission-link").attributes("href")).toBe("/missions");
  wrapper.unmount();
  data.form.actions.cancel.href = "javascript:alert(1)";
  expect(() => assertCreation(data)).toThrow();
});
test("save dispatches once, disables inputs, and exposes field errors without dropping entered values", async () => {
  let resolve!: (value: unknown) => void;
  const execute = vi.fn((event: string) =>
    event === "save"
      ? new Promise((done) => (resolve = done))
      : Promise.resolve({ status: "ok", errors: {} }),
  );
  const wrapper = mount(MissionCreationPage, { props: { data: creationFixture(), execute } });
  await wrapper.get("#mission_display_name").setValue("Flight");
  await wrapper.get("#mission_slug").setValue("Invalid Slug");
  await wrapper.get("#mission-form").trigger("submit");
  await wrapper.get("#mission-form").trigger("submit");
  expect(execute.mock.calls.filter(([event]) => event === "save")).toHaveLength(1);
  expect(wrapper.get("#mission_slug").attributes("disabled")).toBeDefined();
  resolve({ status: "invalid", errors: { slug: ["Choose a valid slug."] } });
  await flushPromises();
  expect(wrapper.get("#mission_slug").attributes("aria-invalid")).toBe("true");
  expect(wrapper.get<HTMLInputElement>("#mission_slug").element.value).toBe("Invalid Slug");
  expect(wrapper.find("#mission-create-pending").exists()).toBe(false);
  wrapper.unmount();
});
test("unknown response fields and transport failures are contained", async () => {
  const execute = vi
    .fn()
    .mockResolvedValue({ status: "invalid", errors: { secret: ["Private server data"] } });
  const wrapper = mount(MissionCreationPage, { props: { data: creationFixture(), execute } });
  await wrapper.get("#mission-form").trigger("submit");
  await flushPromises();
  expect(wrapper.find("#mission-create-error").exists()).toBe(true);
  expect(wrapper.text()).not.toContain("Private server data");
  wrapper.unmount();
});
