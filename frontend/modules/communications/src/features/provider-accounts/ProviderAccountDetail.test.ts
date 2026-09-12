import { containing } from "../../../../../test-support/matchers";
import { required } from "../../../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import ProviderAccountDetail from "./ProviderAccountDetail.vue";
import { accountDetailFixture } from "./detail.test-support";
import { AccountActionFailure, type AccountDetailPort } from "./detail-port";
import { deferred, receipt } from "./registration.test-support";
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
function setup() {
  const model = accountDetailFixture();
  const execute = vi.fn<AccountDetailPort["execute"]>(async () => receipt({ patch: model }));
  const query = vi.fn(async () => model);
  const port = { execute, query };
  const wrapper = mount(ProviderAccountDetail, { props: { model, port } });
  return { wrapper, model, port, execute, query };
}
test("account validation carries identity and updates without losing an unrelated grant draft", async () => {
  const { wrapper, execute, query } = setup();
  const control = wrapper.get("#grant-grant_reason").element;
  await wrapper.get("#grant-grant_reason").setValue("Keep this draft");
  await wrapper.get("#validate-account").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("validate-account", {
    provider_account_id: "account-1",
    expected_account_version: 3,
    credential_ref: "credential-1",
    expected_credential_version: 2,
  });
  expect(query).not.toHaveBeenCalled();
  expect(wrapper.get("#grant-grant_reason").element).toBe(control);
  expect(control).toHaveProperty("value", "Keep this draft");
  wrapper.unmount();
});
test("rotation freezes actions, deduplicates clicks and consumes the updated credential version", async () => {
  const { wrapper, execute, model } = setup();
  const pending = deferred<unknown>();
  execute.mockImplementationOnce(() => pending.promise);
  await wrapper.get("#rotate-credential").trigger("click");
  await wrapper.get("#rotate-credential").trigger("click");
  expect(execute).toHaveBeenCalledTimes(1);
  expect(wrapper.get("#rotate-credential").attributes("disabled")).toBeDefined();
  const updated = { ...model, account: { ...model.account, credential_version: 3 } };
  pending.resolve(receipt({ patch: updated }));
  await flushPromises();
  execute.mockResolvedValueOnce(receipt({ patch: updated }));
  await wrapper.get("#validate-account").trigger("click");
  await flushPromises();
  expect(required(execute.mock.calls[1])[1].expected_credential_version).toBe(3);
  expect(wrapper.find("#provider-account-return").exists()).toBe(false);
  wrapper.unmount();
});
test("grant creation submits normalized scope and clears only a confirmed successful draft", async () => {
  const { wrapper, execute, model } = setup();
  await wrapper.get("#grant-grant_reason").setValue("Commissioning");
  await wrapper.get("#grant-max_quota").setValue("0");
  const next = accountDetailFixture();
  next.account_grants.push({
    ...required(next.account_grants[0]),
    id: "grant-2",
    __dom_id: "grant-row-2",
    provider_account_grant_id: "grant-2",
    mission_id: "mission-2",
    revoke: null,
  });
  next.grant_form.values = { ...model.grant_form.values, grant_reason: "", max_quota: "" };
  for (const key of ["grant_reason", "max_quota"] as const) next.grant_form.fields[key].value = "";
  execute.mockResolvedValueOnce(receipt({ patch: next }));
  await wrapper.get("#grant-form").trigger("submit");
  await flushPromises();
  expect(execute.mock.calls[0]).toEqual([
    "grant-mission",
    containing({
      expected_account_version: 3,
      provider_account_id: "account-1",
      grant: containing({
        mission_id: "mission-2",
        max_quota: "0",
        grant_reason: "Commissioning",
      }),
    }),
  ]);
  expect(wrapper.get("#grant-grant_reason").element).toHaveProperty("value", "");
  expect(wrapper.find("#grant-row-2").exists()).toBe(true);
  wrapper.unmount();
});
test("revocation requires confirmation and sends the exact grant version and account", async () => {
  const { wrapper, execute, model } = setup();
  const confirm = vi.fn().mockReturnValue(false);
  vi.stubGlobal("confirm", confirm);
  await wrapper.get("#revoke-grant-1").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  confirm.mockReturnValue(true);
  const next = accountDetailFixture();
  next.account_grants[0] = {
    ...required(model.account_grants[0]),
    version: 3,
    version_label: "grant v3 · account v3",
    lifecycle: { status: "blocked", label: "Revoked" },
    revoke: null,
  };
  execute.mockResolvedValueOnce(receipt({ patch: next }));
  await wrapper.get("#revoke-grant-1").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith(
    "revoke-grant",
    containing({
      "grant-id": "grant-1",
      expected_grant_version: 2,
      provider_account_id: "account-1",
    }),
  );
  expect(wrapper.find("#revoke-grant-1").exists()).toBe(false);
  wrapper.unmount();
});
test("credential revocation refreshes the disabled state without replaying the effect", async () => {
  const { wrapper, execute } = setup();
  vi.stubGlobal(
    "confirm",
    vi.fn(() => true),
  );
  const next = accountDetailFixture();
  next.account.credential_status = "revoked";
  next.account.credential_version = 3;
  next.actions.validate.disabled = true;
  next.actions.rotate.disabled = true;
  next.actions.revoke = null;
  execute.mockResolvedValueOnce(receipt({ patch: next }));
  await wrapper.get("#revoke-credential").trigger("click");
  await flushPromises();
  expect(wrapper.find("#revoke-credential").exists()).toBe(false);
  expect(wrapper.get("#rotate-credential").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});
test("uncertain outcomes lock mutations, preserve drafts and permit read-only recovery", async () => {
  const { wrapper, execute, query } = setup();
  await wrapper.get("#grant-grant_reason").setValue("Retained");
  execute.mockRejectedValueOnce(new Error("private diagnostic"));
  await wrapper.get("#rotate-credential").trigger("click");
  await flushPromises();
  expect(wrapper.text()).not.toContain("private diagnostic");
  expect(wrapper.find("#provider-account-return").exists()).toBe(true);
  await wrapper.get("#refresh-provider-account").trigger("click");
  await flushPromises();
  expect(query).toHaveBeenCalledTimes(1);
  expect(wrapper.get("#grant-grant_reason").element).toHaveProperty("value", "Retained");
  expect(wrapper.get("#rotate-credential").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});
test("known rejection preserves an editable draft, and malformed completion is uncertain", async () => {
  const { wrapper, execute } = setup();
  await wrapper.get("#grant-grant_reason").setValue("Retained");
  execute.mockRejectedValueOnce(new AccountActionFailure("rejected"));
  await wrapper.get("#validate-account").trigger("click");
  await flushPromises();
  expect(wrapper.get("#grant-grant_reason").element).toHaveProperty("value", "Retained");
  expect(wrapper.get("#rotate-credential").attributes("disabled")).toBeUndefined();
  execute.mockResolvedValueOnce(receipt({ patch: {} }));
  await wrapper.get("#validate-account").trigger("click");
  await flushPromises();
  expect(wrapper.find("#provider-account-return").exists()).toBe(true);
  wrapper.unmount();
});
test.each(["rotate-credential", "revoke-credential", "revoke-grant-1"])(
  "an unchanged receipt cannot confirm %s",
  async (id) => {
    vi.stubGlobal(
      "confirm",
      vi.fn(() => true),
    );
    const { wrapper, execute } = setup();
    await wrapper.get("#" + id).trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#provider-account-return").exists()).toBe(true);
    wrapper.unmount();
  },
);
test("read-only refresh failures preserve the mounted page and editable draft", async () => {
  const { wrapper, query, execute } = setup();
  await wrapper.get("#grant-grant_reason").setValue("Keep on failed read");
  query.mockRejectedValueOnce(new Error("private response"));
  await wrapper.get("#refresh-provider-account").trigger("click");
  await flushPromises();
  expect(wrapper.get("#grant-grant_reason").element).toHaveProperty("value", "Keep on failed read");
  expect(wrapper.text()).not.toContain("private response");
  expect(wrapper.get("#rotate-credential").attributes("disabled")).toBeUndefined();
  expect(execute).not.toHaveBeenCalled();
  wrapper.unmount();
});
test.each(["refresh", "action"])(
  "late %s replies cannot overwrite a different account",
  async (operation) => {
    const { wrapper, execute, query } = setup();
    const pending = deferred<unknown>();
    if (operation === "refresh") {
      query.mockImplementationOnce(() => pending.promise as ReturnType<typeof query>);
      await wrapper.get("#refresh-provider-account").trigger("click");
    } else {
      execute.mockImplementationOnce(() => pending.promise);
      await wrapper.get("#validate-account").trigger("click");
    }
    const next = accountDetailFixture();
    next.account.provider_account_id = "account-2";
    next.page.header.subtitle = "account-2";
    next.page.header.title = "Second account";
    await wrapper.setProps({ model: next });
    pending.resolve(
      operation === "refresh" ? accountDetailFixture() : receipt({ patch: accountDetailFixture() }),
    );
    await flushPromises();
    expect(wrapper.text()).toContain("Second account");
    wrapper.unmount();
  },
);
