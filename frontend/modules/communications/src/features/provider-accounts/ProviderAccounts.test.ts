import { required } from "../../../../../test-support/required";
import { readFileSync } from "node:fs";
import { mount } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import * as accounts from "../../provider-accounts";
import { registrationFixture, detailFixture, listFixture } from "./provider-accounts.test-support";

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
const legacy = import.meta.glob("../../../../../apps/organization-admin/src/ProviderAccount*.vue", {
  eager: true,
  import: "default",
});

test("legacy provider account surfaces are exact public-entry adapters", () => {
  for (const name of [
    "ProviderAccountCards",
    "ProviderAccountListPage",
    "ProviderAccountNew",
    "ProviderAccountShow",
  ] as const) {
    const path = "../../../../../apps/organization-admin/src/" + name + ".vue";
    expect(legacy[path]).toBe(accounts[name]);
    const source = readFileSync(new URL(path, import.meta.url), "utf8");
    expect(source).toContain('from "@cadence/communications/provider-accounts"');
    expect(source).not.toContain("<template>");
  }
});

test.each([false, true])("directory retains scoped links and empty state, empty=%s", (empty) => {
  const wrapper = mount(accounts.ProviderAccountListPage, { props: listFixture(empty) });
  expect(wrapper.find('a[href="/provider-accounts/new"]').exists()).toBe(true);
  expect(wrapper.find("#provider-accounts-empty-state").exists()).toBe(empty);
  expect(wrapper.find("#provider-account-account-1").exists()).toBe(!empty);
  if (!empty)
    expect(wrapper.get("#provider-account-account-1 a").attributes("href")).toBe(
      "/provider-accounts/account-1",
    );
  wrapper.unmount();
});

test("registration preserves field IDs, native draft controls, connector visibility and payloads", async () => {
  const wrapper = mount(accounts.ProviderAccountNew, { props: registrationFixture() });
  expect(wrapper.get("#account-provider_account_id").attributes("type")).toBe("hidden");
  expect(wrapper.get("#account-provider_account_id").element).toHaveProperty("value", "account-1");
  expect(wrapper.get("#cancel").attributes("href")).toBe("/provider-accounts");
  await wrapper.get("#account-display_name").setValue("Relay Two");
  await wrapper.get("#account-endpoint").setValue("https://relay.test");
  await wrapper.get("#account-max_quota").setValue("0");
  expect(wrapper.find("#account-notes").exists()).toBe(true);
  await wrapper.get("#account-backend_type").setValue("env");
  expect(wrapper.find("#account-notes").exists()).toBe(false);
  expect(wrapper.text()).toContain("Environment variable");
  await wrapper.get("#registration-form").trigger("submit");
  expect(wrapper.emitted("save")).toEqual([
    [
      {
        provider_account: {
          provider_account_id: "account-1",
          credential_ref: "registry-reference",
          display_name: "Relay Two",
          provider_type: "simulator",
          backend_type: "env",
          backend_key: "providers/relay",
          max_quota: "0",
          allowed_services: "",
          allowed_directions: "",
          allowed_stations: "",
          endpoint: "https://relay.test",
          notes: "",
        },
      },
    ],
  ]);
  expect(wrapper.emitted("validate")?.length).toBe(4);
  wrapper.unmount();
});

test("registration keeps newer typing across an older validation reply", async () => {
  const props = registrationFixture();
  const wrapper = mount(accounts.ProviderAccountNew, { props });
  await wrapper.get("#account-display_name").setValue("First");
  await wrapper.get("#account-display_name").setValue("Second");
  const older = structuredClone(props.form);
  older.fields.display_name.value = "First";
  await wrapper.setProps({ form: older });
  expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Second");
  const latest = structuredClone(props.form);
  latest.fields.display_name.value = "Second";
  await wrapper.setProps({ form: latest });
  expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Second");
  wrapper.unmount();
});

test("registration accepts a server-corrected unavailable connector", async () => {
  const props = registrationFixture();
  const wrapper = mount(accounts.ProviderAccountNew, { props });
  await wrapper.get("#account-provider_type").setValue("other");
  const corrected = structuredClone(props.form);
  corrected.connector.options = corrected.connector.options.filter(
    (option) => option.value !== "other",
  );
  corrected.fields.provider_type.options = corrected.connector.options;
  await wrapper.setProps({ form: corrected });
  expect(wrapper.get("#account-provider_type").element).toHaveProperty("value", "simulator");
  wrapper.unmount();
});

test("detail keeps configured versions, audit rows and string-valued grant payloads", async () => {
  const wrapper = mount(accounts.ProviderAccountShow, { props: detailFixture() });
  expect(wrapper.text()).toContain("Config v3");
  expect(wrapper.get("#grant-row-1").text()).toContain("v2");
  expect(wrapper.find("#audit-row-1").exists()).toBe(true);
  await wrapper.get("#grant-max_quota").setValue("0");
  await wrapper.get("#grant-grant_reason").setValue("Commissioning");
  await wrapper.get("#grant-form").trigger("submit");
  expect(wrapper.emitted("grant-mission")).toEqual([
    [
      {
        grant: {
          mission_id: "mission-1",
          allowed_services: "telemetry",
          allowed_stations: "",
          max_quota: "0",
          grant_reason: "Commissioning",
        },
      },
    ],
  ]);
  wrapper.unmount();
});

test("credential and grant revocation require confirmation; disabled actions stay inert", async () => {
  const props = detailFixture();
  const confirm = vi.fn().mockReturnValue(false);
  vi.stubGlobal("confirm", confirm);
  const wrapper = mount(accounts.ProviderAccountShow, { props });
  await wrapper.get("#revoke-credential").trigger("click");
  await wrapper.get("#revoke-grant-1").trigger("click");
  expect(wrapper.emitted("revoke-credential")).toBeUndefined();
  expect(wrapper.emitted("revoke-grant")).toBeUndefined();
  confirm.mockReturnValue(true);
  await wrapper.get("#revoke-credential").trigger("click");
  await wrapper.get("#revoke-grant-1").trigger("click");
  expect(wrapper.emitted("revoke-credential")).toEqual([[{}]]);
  expect(wrapper.emitted("revoke-grant")).toEqual([[{ "grant-id": "grant-1" }]]);
  await wrapper.get("#validate-account").trigger("click");
  await wrapper.get("#rotate-credential").trigger("click");
  expect(wrapper.emitted("validate-account")).toEqual([[{}]]);
  expect(wrapper.emitted("rotate-credential")).toEqual([[{}]]);
  await wrapper.setProps({
    actions: {
      ...required(props.actions),
      validate: { ...required(props.actions).validate, disabled: true },
      rotate: { ...required(props.actions).rotate, disabled: true },
      revoke: null,
    },
  });
  await wrapper.get("#validate-account").trigger("click");
  await wrapper.get("#rotate-credential").trigger("click");
  expect(wrapper.emitted("validate-account")).toHaveLength(1);
  expect(wrapper.emitted("rotate-credential")).toHaveLength(1);
  expect(wrapper.find("#revoke-credential").exists()).toBe(false);
  wrapper.unmount();
});

test("feature binds the unchanged seven Phoenix action IDs", () => {
  expect(accounts.providerAccountActions).toEqual({
    provider_accounts: {},
    provider_account_new: {
      validate: "validate_provider_account_form",
      save: "register_provider_account",
    },
    provider_account_show: {
      "validate-account": "validate_provider_account",
      "rotate-credential": "rotate_provider_credential",
      "revoke-credential": "revoke_provider_credential",
      "grant-mission": "grant_provider_account_mission",
      "revoke-grant": "revoke_provider_account_mission",
    },
  });
});
