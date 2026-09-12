import { required } from "../../../../../test-support/required";
import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { listFixture } from "./provider-accounts.test-support";
import { readAccountDirectory } from "./list.validation";
import ProviderAccountListPage from "./ProviderAccountListPage.vue";

test.each([false, true])("directory admits only its scoped known-field DTO, empty=%s", (empty) => {
  const model = listFixture(empty);
  expect(readAccountDirectory({ ...model, attrs: { onclick: "private" } }, "org-1")).toEqual(model);
  expect(() => readAccountDirectory(model, "foreign")).toThrow();
  expect(() => readAccountDirectory(model, "org-1", 2)).toThrow();
  const wrapper = mount(ProviderAccountListPage, { props: model });
  expect(wrapper.find("#provider-accounts-empty-state").exists()).toBe(empty);
  expect(wrapper.get("#new-provider-account-link").attributes("href")).toBe(
    "/provider-accounts/new",
  );
  wrapper.unmount();
});
test("directory rejects cross-account links, inconsistent counts, duplicate identities and malformed rows", () => {
  const mutations: Array<(model: ReturnType<typeof listFixture>) => void> = [
    (model) => {
      model.count = 9;
    },
    (model) => {
      required(model.provider_accounts[0]).href = "/provider-accounts/foreign";
    },
    (model) => {
      required(model.provider_accounts[0]).href = "javascript:alert(1)";
    },
    (model) => {
      required(model.provider_accounts[0]).href = "//foreign.test";
    },
    (model) => {
      required(model.provider_accounts[0]).provider_account_id = "../escape";
    },
    (model) => {
      required(model.provider_accounts[0]).__dom_id = "provider-accounts";
    },
    (model) => {
      required(model.provider_accounts[0]).id = "different";
    },
    (model) => {
      required(model.provider_accounts[0]).config = "latest";
    },
    (model) => {
      required(model.provider_accounts[0]).display_name = "";
    },
    (model) => {
      model.provider_accounts.push(required(model.provider_accounts[0]));
      model.count++;
    },
  ];
  for (const mutate of mutations) {
    const model = listFixture();
    mutate(model);
    expect(() => readAccountDirectory(model, "org-1")).toThrow();
  }
});
test("valid encoded account links remain bound to their identity", () => {
  const model = listFixture();
  const identity = "account?#";
  model.provider_accounts[0] = {
    ...required(model.provider_accounts[0]),
    provider_account_id: identity,
    id: "provider-account-" + identity,
    __dom_id: "provider-account-" + identity,
    href: "/provider-accounts/" + encodeURIComponent(identity),
  };
  expect(readAccountDirectory(model, "org-1")).toEqual(model);
});
