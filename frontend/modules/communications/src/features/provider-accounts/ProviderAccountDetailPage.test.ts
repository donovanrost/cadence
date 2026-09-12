import { containing } from "../../../../../test-support/matchers";
import { required } from "../../../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import ProviderAccountDetailPage from "./ProviderAccountDetailPage.vue";
import { providerAccountDetailContribution } from "./detail.contribution";
import { accountDetailFixture } from "./detail.test-support";
import { receipt } from "./registration.test-support";

function setup(locked = false) {
  const model = accountDetailFixture();
  const execute = vi.fn(async (event: string, _input: Record<string, unknown>) => ({
    status: "ok",
    data: event === "refresh" ? model : receipt({ patch: model }),
  }));
  const wrapper = mount(ProviderAccountDetailPage, {
    props: { model, sequence: 4, locked, port: { execute, navigate: vi.fn() } },
  });
  return { wrapper, execute, model };
}
test("detail contribution binds the account to host route context and validates initial sequence and lock", () => {
  const data = { model: accountDetailFixture(), sequence: 0, locked: false };
  expect(
    providerAccountDetailContribution.read(data, {
      organizationId: "org-1",
      resourceId: "account-1",
    }),
  ).toEqual(data);
  for (const context of [
    { organizationId: "org-1" },
    { organizationId: "org-1", resourceId: "foreign" },
    { organizationId: "foreign", resourceId: "account-1" },
  ])
    expect(() => providerAccountDetailContribution.read(data, context)).toThrow();
  for (const bad of [
    { ...data, sequence: -1 },
    { ...data, locked: "false" },
  ])
    expect(() =>
      providerAccountDetailContribution.read(bad, {
        organizationId: "org-1",
        resourceId: "account-1",
      }),
    ).toThrow();
});
test("effects advance a page-local sequence while refresh preserves draft and sequence", async () => {
  const { wrapper, execute } = setup();
  await wrapper.get("#grant-grant_reason").setValue("Keep this draft");
  await wrapper.get("#validate-account").trigger("click");
  await flushPromises();
  expect(execute.mock.calls[0]).toEqual([
    "validate-account",
    containing({ sequence: 5, provider_account_id: "account-1" }),
  ]);
  await wrapper.setProps({ model: accountDetailFixture(), sequence: 5 });
  expect(wrapper.get("#grant-grant_reason").element).toHaveProperty("value", "Keep this draft");
  await wrapper.get("#refresh-provider-account").trigger("click");
  await flushPromises();
  expect(execute.mock.calls[1]).toEqual(["refresh", {}]);
  await wrapper.get("#validate-account").trigger("click");
  await flushPromises();
  expect(required(execute.mock.calls[2])[1].sequence).toBe(6);
  wrapper.unmount();
});
test("unknown effects remain locked across refresh and server-locked mounts permit only reads", async () => {
  const { wrapper, execute } = setup();
  execute.mockResolvedValueOnce({ status: "unknown", data: accountDetailFixture() });
  await wrapper.get("#validate-account").trigger("click");
  await flushPromises();
  await wrapper.setProps({ model: accountDetailFixture() });
  await wrapper.get("#refresh-provider-account").trigger("click");
  await flushPromises();
  expect(wrapper.get("#validate-account").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledTimes(2);
  wrapper.unmount();
  const next = setup(true);
  expect(next.wrapper.get("#validate-account").attributes("disabled")).toBeDefined();
  await next.wrapper.get("#refresh-provider-account").trigger("click");
  await flushPromises();
  expect(next.execute).toHaveBeenCalledExactlyOnceWith("refresh", {});
  expect(next.wrapper.find("#provider-account-return").exists()).toBe(true);
  next.wrapper.unmount();
});
