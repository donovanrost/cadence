import { required } from "../../../../../test-support/required";
import { expect, test } from "vite-plus/test";
import { registrationFixture } from "./provider-accounts.test-support";
import { registrationModel, receipt, validationReceipt } from "./registration.test-support";
import {
  readRegistration,
  readRegistrationPatch,
  registrationReady,
  registrationValues,
} from "./registration.validation";

test("admits known DTO fields, discarding undeclared data", () => {
  const raw = { ...registrationFixture(), secret_material: "do not forward" };
  expect(readRegistration(raw, 1)).toEqual(registrationFixture());
  expect(() => readRegistration(raw, 2)).toThrow();
  const model = registrationModel();
  expect(
    readRegistrationPatch(validationReceipt(registrationValues(model.form)), model.form),
  ).toEqual(model.form);
});
test("rejects malformed, duplicate, unbound and unsafe configuration fields", () => {
  const mutations: Array<(value: ReturnType<typeof registrationFixture>) => void> = [
    (value) => {
      value.form.fields.display_name.name = "credential[secret]";
    },
    (value) => {
      value.form.fields.display_name.id = value.form.fields.backend_key.id;
    },
    (value) => {
      value.form.fields.display_name.type = "hidden";
    },
    (value) => {
      required(required(value.form.connector.configuration.sections[0]).fields[0]).key =
        "__proto__";
    },
    (value) => {
      // @ts-expect-error Producer sections may reference an unregistered field.
      value.form.sections.network_identity.field_keys.push("unknown");
    },
    (value) => {
      value.form.connector.selected.form_value = "unknown";
    },
    (value) => {
      value.form.fields.backend_type.value = "unsupported";
    },
    (value) => {
      value.form.actions.cancel.href = "//outside.test";
    },
    (value) => {
      required(value.page.breadcrumbs[0]).href = "/provider-accounts/foreign";
    },
    (value) => {
      required(required(value.form.connector.configuration.sections[0]).fields[1]).visible_when = {
        field: "unknown",
        equals: "yes",
      };
    },
    (value) => {
      value.form.connector.options.push(required(value.form.connector.options[0]));
    },
    (value) => {
      value.form.fields.max_quota.min = Number.NaN;
    },
    (value) => {
      value.form.fields.display_name.value = "x".repeat(4097);
    },
    (value) => {
      // @ts-expect-error Required native hidden fields must be rejected when omitted.
      delete value.form.fields.credential_ref;
    },
  ];
  for (const mutate of mutations) {
    const value = registrationFixture();
    mutate(value);
    expect(() => readRegistration(value, 1)).toThrow();
  }
});
test("validation receipts cannot rotate the form identity or omit their receipt envelope", () => {
  const model = registrationModel();
  for (const name of ["provider_account_id", "credential_ref"] as const) {
    const modified = structuredClone(model.form);
    modified.fields[name].value = "other";
    expect(() =>
      readRegistrationPatch(receipt({ patch: { form: modified } }), model.form),
    ).toThrow();
  }
  expect(() => readRegistrationPatch({ patch: { form: model.form } }, model.form)).toThrow();
  expect(() =>
    readRegistrationPatch(
      { ...receipt({ patch: { form: model.form } }), completedAt: "invalid" },
      model.form,
    ),
  ).toThrow();
});
test("registration readiness respects required, selected and numeric fields", () => {
  const { form } = registrationModel();
  expect(registrationReady(form)).toBe(true);
  form.fields.max_quota.value = "-1";
  expect(registrationReady(form)).toBe(false);
  form.fields.max_quota.value = "0.5";
  expect(registrationReady(form)).toBe(false);
  form.fields.max_quota.value = "0";
  expect(registrationReady(form)).toBe(true);
  form.fields.display_name.required = true;
  form.fields.display_name.value = "";
  expect(registrationReady(form)).toBe(false);
});
