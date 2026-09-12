import { expect, test } from "vite-plus/test";
import { accountDetailFixture } from "./detail.test-support";
import {
  readAccountDetail,
  readAccountUpdate,
  readAccountPatch,
  grantReady,
  accountActionIdentity,
} from "./detail.validation";
import { receipt } from "./registration.test-support";
test("admits known account data and exact observed identity, dropping undeclared fields", () => {
  const model = accountDetailFixture();
  expect(readAccountDetail({ ...model, rawSecret: "not forwarded" }, "org-1", 1)).toEqual(model);
  expect(accountActionIdentity(model.account)).toEqual({
    provider_account_id: "account-1",
    expected_account_version: 3,
    credential_ref: "credential-1",
    expected_credential_version: 2,
  });
  expect(() => readAccountDetail(model, "other", 1)).toThrow();
  expect(() => readAccountDetail(model, "org-1", 2)).toThrow();
  expect(() => readAccountDetail(model, "org-1", 1, "other")).toThrow();
});
test("rejects malformed grant bindings, duplicate IDs, unsafe links and inconsistent credential actions", () => {
  const mutations: Array<(model: ReturnType<typeof accountDetailFixture>) => void> = [
    (model) => {
      model.account_grants[0].revoke!.payload["grant-id"] = "foreign";
    },
    (model) => {
      model.account_grants.push(model.account_grants[0]);
    },
    (model) => {
      model.grant_form.fields.max_quota.name = "grant[mission_id]";
    },
    (model) => {
      model.grant_form.fields.max_quota.value = "different";
    },
    (model) => {
      model.account.credential_status = "revoked";
    },
    (model) => {
      model.page.header.config_label = "config v999";
    },
    (model) => {
      model.account_grants[0].version_label = "grant v999";
    },
    (model) => {
      model.page.header.breadcrumbs[0].href = "//outside.test" as "/provider-accounts";
    },
    (model) => {
      model.actions.validate.icon = "arbitrary-class";
    },
    (model) => {
      model.account_audit[0].id = "different";
    },
  ];
  for (const mutate of mutations) {
    const model = accountDetailFixture();
    mutate(model);
    expect(() => readAccountDetail(model, "org-1", 1)).toThrow();
  }
});
test("refresh and action patches cannot regress versioned records", () => {
  const previous = accountDetailFixture();
  for (const mutate of [
    (model: typeof previous) => {
      model.account.credential_version = 1;
    },
    (model: typeof previous) => {
      model.account.credential_ref = "other";
    },
    (model: typeof previous) => {
      model.account.credential_status = "revoked";
      model.actions.validate.disabled = true;
      model.actions.rotate.disabled = true;
      model.actions.revoke = null;
    },
    (model: typeof previous) => {
      model.account_grants[0].mission_id = "other";
    },
    (model: typeof previous) => {
      model.account_grants = [];
    },
    (model: typeof previous) => {
      model.account_grants[0].version = 1;
      model.account_grants[0].version_label = "grant v1 · account v3";
    },
  ]) {
    const model = accountDetailFixture();
    mutate(model);
    expect(() => readAccountUpdate(model, previous)).toThrow();
    expect(() => readAccountPatch(receipt({ patch: model }), previous)).toThrow();
  }
});
test("grant readiness requires an available mission and a nonnegative integer quota", () => {
  const model = accountDetailFixture(),
    values = model.grant_form.values;
  expect(grantReady(model, { ...values, max_quota: "0" })).toBe(true);
  for (const max_quota of ["-1", "1.5", "0x10", "1e3"])
    expect(grantReady(model, { ...values, max_quota })).toBe(false);
  expect(grantReady(model, { ...values, mission_id: "foreign" })).toBe(false);
});
