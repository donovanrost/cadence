import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import ProviderAccountRegistrationPage from "./ProviderAccountRegistrationPage.vue";
import {
  registrationModel,
  validationReceipt,
  receipt,
  deferred,
} from "./registration.test-support";
import type { ProviderAccountValues } from "./registration.contracts";

function setup() {
  const execute = vi.fn(async (event: string, input: Record<string, unknown>) => ({
    status: "ok",
    data:
      event === "validate"
        ? validationReceipt(input.provider_account as ProviderAccountValues)
        : receipt({ navigate: "/provider-accounts/account-1" }),
  }));
  const navigate = vi.fn();
  const wrapper = mount(ProviderAccountRegistrationPage, {
    props: { model: registrationModel(), organizationId: "org-1", port: { execute, navigate } },
  });
  return { wrapper, execute, navigate };
}
test("host transport receipts drive the existing feature workflow and preserve drafts across same-instance refresh", async () => {
  const { wrapper, execute, navigate } = setup();
  await wrapper.get("#account-display_name").setValue("Preserved draft");
  await flushPromises();
  const input = wrapper.get("#account-display_name").element;
  await wrapper.setProps({ model: registrationModel(), port: { execute, navigate } });
  expect(wrapper.get("#account-display_name").element).toBe(input);
  expect(input).toHaveProperty("value", "Preserved draft");
  await wrapper.get("#registration-form").trigger("submit");
  await flushPromises();
  expect(navigate).toHaveBeenCalledExactlyOnceWith("/provider-accounts/account-1");
  wrapper.unmount();
});
test.each(["unknown", "malformed"])(
  "%s save outcome locks even after same-instance model refresh",
  async (status) => {
    const { wrapper, execute, navigate } = setup();
    await wrapper.get("#account-display_name").setValue("Draft");
    await flushPromises();
    execute.mockResolvedValueOnce({ status, data: receipt({}) });
    await wrapper.get("#registration-form").trigger("submit");
    await flushPromises();
    await wrapper.setProps({ model: registrationModel() });
    expect(wrapper.find("#check-provider-account-records").exists()).toBe(true);
    expect(navigate).not.toHaveBeenCalled();
    wrapper.unmount();
  },
);
test("unmounting a submitted page ignores its late completion", async () => {
  const { wrapper, execute, navigate } = setup();
  await wrapper.get("#account-display_name").setValue("Draft");
  await flushPromises();
  const pending = deferred<{ status: string; data: ReturnType<typeof receipt> }>();
  execute.mockImplementationOnce(() => pending.promise);
  await wrapper.get("#registration-form").trigger("submit");
  wrapper.unmount();
  pending.resolve({ status: "ok", data: receipt({ navigate: "/provider-accounts/account-1" }) });
  await flushPromises();
  expect(navigate).not.toHaveBeenCalled();
});
