import { containing } from "../../../../../test-support/matchers";
import { required } from "../../../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import ProviderAccountRegistration from "./ProviderAccountRegistration.vue";
import { RegistrationActionFailure, type RegistrationPort } from "./registration-port";
import {
  deferred,
  receipt,
  registrationModel,
  validationReceipt,
} from "./registration.test-support";
import type { ProviderAccountPayload } from "./registration.contracts";

function setup() {
  const execute = vi.fn<RegistrationPort["execute"]>(async (action, input) =>
    action === "validate"
      ? validationReceipt(input.provider_account)
      : receipt({ navigate: "/provider-accounts/account-1" }),
  );
  const navigate = vi.fn();
  const port = { execute, navigate };
  const wrapper = mount(ProviderAccountRegistration, {
    props: { model: registrationModel(), organizationId: "org-1", port },
  });
  return { wrapper, execute, navigate, port };
}
test("validation updates the same form and native input instead of querying a new identity", async () => {
  const { wrapper, execute, navigate } = setup();
  const field = wrapper.get("#account-display_name").element;
  const form = wrapper.get("#registration-form").element;
  await wrapper.get("#account-display_name").setValue("Second");
  await flushPromises();
  expect(wrapper.get("#account-display_name").element).toBe(field);
  expect(wrapper.get("#registration-form").element).toBe(form);
  expect(field).toHaveProperty("value", "Second");
  expect(wrapper.get("#register").attributes("disabled")).toBeUndefined();
  await wrapper.get("#account-max_quota").setValue("0");
  await flushPromises();
  await wrapper.get("#registration-form").trigger("submit");
  await flushPromises();
  expect(execute.mock.calls.at(-1)).toEqual([
    "save",
    containing({
      provider_account: containing({
        provider_account_id: "account-1",
        max_quota: "0",
        display_name: "Second",
      }),
    }),
  ]);
  expect(navigate).toHaveBeenCalledExactlyOnceWith("/provider-accounts/account-1");
  wrapper.unmount();
});
test("coalesces validation and preserves newer typing until its matching reply", async () => {
  const { wrapper, execute } = setup();
  const first = deferred<unknown>();
  execute.mockImplementationOnce(() => first.promise);
  await wrapper.get("#account-display_name").setValue("First");
  await wrapper.get("#account-display_name").setValue("Second");
  await wrapper.get("#account-display_name").setValue("Third");
  expect(execute).toHaveBeenCalledTimes(1);
  first.resolve(
    validationReceipt(
      (required(execute.mock.calls[0])[1] as ProviderAccountPayload).provider_account,
    ),
  );
  await flushPromises();
  expect(execute).toHaveBeenCalledTimes(2);
  expect(required(execute.mock.calls[1])[1].provider_account.display_name).toBe("Third");
  expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Third");
  wrapper.unmount();
});
test("accepts corrected connector choices but rejects a changed hidden identity", async () => {
  const { wrapper, execute } = setup();
  execute.mockImplementationOnce(async (_action, input) =>
    validationReceipt({ ...input.provider_account, provider_type: "simulator" }),
  );
  await wrapper.get("#account-provider_type").setValue("other");
  await flushPromises();
  expect(wrapper.get("#account-provider_type").element).toHaveProperty("value", "simulator");
  execute.mockImplementationOnce(async (_action, input) =>
    validationReceipt({ ...input.provider_account, credential_ref: "foreign" }),
  );
  await wrapper.get("#account-display_name").setValue("Kept");
  await flushPromises();
  expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Kept");
  expect(wrapper.get("#register").attributes("disabled")).toBeDefined();
  expect(wrapper.find("#recheck-provider-account-draft").exists()).toBe(true);
  await wrapper.get("#recheck-provider-account-draft").trigger("click");
  await flushPromises();
  expect(wrapper.get("#register").attributes("disabled")).toBeUndefined();
  wrapper.unmount();
});
test("freezes pending saves, deduplicates submission and locks uncertain outcomes", async () => {
  const { wrapper, execute, navigate } = setup();
  await wrapper.get("#account-display_name").setValue("Relay Two");
  await flushPromises();
  const saved = deferred<unknown>();
  execute.mockImplementationOnce(() => saved.promise);
  await wrapper.get("#registration-form").trigger("submit");
  await wrapper.get("#registration-form").trigger("submit");
  expect(execute.mock.calls.filter(([action]) => action === "save")).toHaveLength(1);
  expect(wrapper.get("fieldset").attributes("disabled")).toBeDefined();
  saved.reject(new Error("raw backend details"));
  await flushPromises();
  expect(wrapper.text()).not.toContain("raw backend details");
  expect(wrapper.find("#check-provider-account-records").exists()).toBe(true);
  await wrapper.get("#registration-form").trigger("submit");
  expect(execute.mock.calls.filter(([action]) => action === "save")).toHaveLength(1);
  expect(navigate).not.toHaveBeenCalled();
  wrapper.unmount();
});
test("known rejection retains the draft and allows correction", async () => {
  const { wrapper, execute } = setup();
  await wrapper.get("#account-display_name").setValue("Kept");
  await flushPromises();
  execute.mockRejectedValueOnce(new RegistrationActionFailure("rejected"));
  await wrapper.get("#registration-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Kept");
  expect(wrapper.get("fieldset").attributes("disabled")).toBeUndefined();
  await wrapper.get("#account-display_name").setValue("Corrected");
  await flushPromises();
  expect(wrapper.get("#register").attributes("disabled")).toBeUndefined();
  wrapper.unmount();
});
test.each(["/provider-accounts/other", "https://outside.test", undefined])(
  "successful receipt with unusable destination never permits another save: %s",
  async (navigate) => {
    const { wrapper, execute } = setup();
    await wrapper.get("#account-display_name").setValue("Kept");
    await flushPromises();
    execute.mockResolvedValueOnce(receipt({ navigate }));
    await wrapper.get("#registration-form").trigger("submit");
    await flushPromises();
    expect(wrapper.find("#check-provider-account-records").exists()).toBe(true);
    await wrapper.get("#registration-form").trigger("submit");
    expect(execute.mock.calls.filter(([action]) => action === "save")).toHaveLength(1);
    wrapper.unmount();
  },
);
test.each(["unmount", "organization"])(
  "stale save replies cannot affect a new page: %s",
  async (change) => {
    const { wrapper, execute, navigate } = setup();
    await wrapper.get("#account-display_name").setValue("Old");
    await flushPromises();
    const pending = deferred<unknown>();
    execute.mockImplementationOnce(() => pending.promise);
    await wrapper.get("#registration-form").trigger("submit");
    if (change === "unmount") wrapper.unmount();
    else await wrapper.setProps({ organizationId: "org-2", model: registrationModel() });
    pending.resolve(receipt({ navigate: "/provider-accounts/account-1" }));
    await flushPromises();
    expect(navigate).not.toHaveBeenCalled();
    if (change !== "unmount") {
      expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Relay");
      wrapper.unmount();
    }
  },
);

test("changing organization invalidates an in-flight validation without overwriting the new draft", async () => {
  const { wrapper, execute } = setup();
  const pending = deferred<unknown>();
  execute.mockImplementationOnce(() => pending.promise);
  await wrapper.get("#account-display_name").setValue("Old organization");
  const old = required(execute.mock.calls[0])[1].provider_account;
  await wrapper.setProps({ organizationId: "org-2", model: registrationModel() });
  await wrapper.get("#account-display_name").setValue("New organization");
  await flushPromises();
  pending.resolve(validationReceipt(old));
  await flushPromises();
  expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "New organization");
  expect(wrapper.get("#register").attributes("disabled")).toBeUndefined();
  wrapper.unmount();
});
