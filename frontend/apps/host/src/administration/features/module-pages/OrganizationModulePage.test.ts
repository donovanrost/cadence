import "../../../module-pages.test-support";
import { fixtureRecord } from "../../../../../../test-support/json-fixture";
import { containing } from "../../../../../../test-support/matchers";
import type {
  OrganizationPagePort,
  OrganizationPageAction,
} from "@cadence/plugin-sdk/organization-pages";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OrganizationModulePage from "./OrganizationModulePage.vue";
import { admitOrganizationPages } from "./contributions";
import {
  ProviderAccountListPage,
  providerAccountDirectoryContribution,
  providerAccountRegistrationContribution,
} from "@cadence/communications/provider-accounts";
import { listFixture } from "../../../../../../modules/communications/src/features/provider-accounts/provider-accounts.test-support";
import { registrationFixture } from "../../../../../../modules/communications/src/features/provider-accounts/provider-accounts.test-support";
import { validationReceipt } from "../../../../../../modules/communications/src/features/provider-accounts/registration.test-support";
const context = { organizationId: "org-1" };
const snapshot = () => ({
  id: "comms.provider-account-directory",
  slot: "organization.page",
  version: 1,
  context,
  status: "ready",
  data: listFixture(),
});
const props = () => ({
  contributionId: "comms.provider-account-directory",
  context,
  snapshot: snapshot(),
  refresh: vi.fn(async () => {}),
});

test("host admits the module-owned renderer and rejects incompatible envelopes and DTOs", async () => {
  const wrapper = mount(OrganizationModulePage, { props: props() });
  expect(wrapper.find("#provider-account-account-1").exists()).toBe(true);
  const valid = snapshot();
  for (const value of [
    null,
    { ...valid, id: "other" },
    { ...valid, slot: "spacecraft.page" },
    { ...valid, version: 2 },
    { ...valid, context: { organizationId: "foreign" } },
    { ...valid, data: {} },
    { ...valid, data: { ...valid.data, organization_id: "foreign" } },
    { ...valid, status: "unavailable" },
  ]) {
    await wrapper.setProps({ snapshot: value });
    expect(wrapper.find("#organization-module-unavailable").exists()).toBe(true);
    expect(wrapper.find("#provider-account-account-1").exists()).toBe(false);
  }
  await wrapper.setProps({ snapshot: valid, contributionId: "__proto__" });
  expect(wrapper.find("#organization-module-unavailable").exists()).toBe(true);
  wrapper.unmount();
});
test("compiled registrations reject duplicate identities and unsupported contracts", () => {
  expect(() =>
    admitOrganizationPages([
      providerAccountDirectoryContribution,
      providerAccountDirectoryContribution,
    ]),
  ).toThrow();
  expect(() =>
    admitOrganizationPages([
      { ...providerAccountRegistrationContribution, actions: ["save", "save"] },
    ]),
  ).toThrow();
  expect(() =>
    admitOrganizationPages([
      { ...providerAccountRegistrationContribution, actions: ["private:execute"] },
    ]),
  ).toThrow();
  expect(() =>
    admitOrganizationPages([{ ...providerAccountDirectoryContribution, version: 2 } as never]),
  ).toThrow();
  expect(() =>
    admitOrganizationPages([{ ...providerAccountDirectoryContribution, slot: "other" } as never]),
  ).toThrow();
});
test("action contribution requires a token and binds only declared actions to the current instance", async () => {
  const token = "11111111-1111-4111-8111-111111111111";
  const page = {
    ...snapshot(),
    id: providerAccountRegistrationContribution.id,
    token,
    data: registrationFixture(),
  };
  const execute = vi.fn(async ({ input }: OrganizationPageAction) => {
    const values: Record<string, string> = {};
    for (const [key, value] of Object.entries(fixtureRecord(input.provider_account))) {
      if (typeof value !== "string") throw Error("Expected native provider account field text");
      values[key] = value;
    }
    return { status: "ok", data: validationReceipt(values) };
  });
  const navigate = vi.fn();
  const wrapper = mount(OrganizationModulePage, {
    props: { ...props(), contributionId: page.id, snapshot: page, execute, navigate },
  });
  expect(wrapper.find("#registration-form").exists()).toBe(true);
  await wrapper.get("#account-display_name").setValue("Admitted");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith(containing({ id: page.id, token, event: "validate" }));
  const feature = wrapper.findComponent(providerAccountRegistrationContribution.component);
  const port: OrganizationPagePort = feature.props("port");
  await expect(port.execute("delete", {})).rejects.toThrow();
  await wrapper.setProps({ snapshot: { ...page, token: "22222222-2222-4222-8222-222222222222" } });
  await expect(port.execute("save", {})).rejects.toThrow();
  port.navigate("/provider-accounts");
  expect(navigate).not.toHaveBeenCalled();
  await wrapper.setProps({ snapshot: { ...page, token: null } });
  expect(wrapper.find("#organization-module-unavailable").exists()).toBe(true);
  wrapper.unmount();
});
test("retry deduplicates pending reads and preserves the unavailable page on rejection", async () => {
  let reject!: (reason: Error) => void;
  const refresh = vi.fn(
    () =>
      new Promise<void>((_resolve, fail) => {
        reject = fail;
      }),
  );
  const wrapper = mount(OrganizationModulePage, { props: { ...props(), snapshot: null, refresh } });
  await wrapper.get("#organization-module-retry").trigger("click");
  await wrapper.get("#organization-module-retry").trigger("click");
  expect(refresh).toHaveBeenCalledTimes(1);
  reject(new Error("private details"));
  await flushPromises();
  expect(wrapper.get("#organization-module-retry").attributes("disabled")).toBeUndefined();
  expect(wrapper.text()).not.toContain("private details");
  await wrapper.setProps({ snapshot: snapshot() });
  expect(wrapper.find("#provider-account-account-1").exists()).toBe(true);
  wrapper.unmount();
});
test("renderer failure is contained and a fresh snapshot recovers", async () => {
  const setup = vi.spyOn(ProviderAccountListPage, "setup").mockImplementation(() => {
    throw new Error("private renderer failure");
  });
  const wrapper = mount(OrganizationModulePage, { props: props() });
  try {
    await flushPromises();
    expect(wrapper.find("#organization-module-unavailable").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("private renderer failure");
    setup.mockRestore();
    await wrapper.setProps({ snapshot: snapshot() });
    expect(wrapper.find("#provider-account-account-1").exists()).toBe(true);
  } finally {
    setup.mockRestore();
    wrapper.unmount();
  }
});
