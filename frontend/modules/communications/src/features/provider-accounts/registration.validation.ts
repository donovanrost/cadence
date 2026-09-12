import { identifier, integer, invalid, record, text } from "../../shared/read-validation";
import {
  array,
  boolean,
  id,
  literal,
  nullable,
  number,
  object,
  oneOf,
  string,
  unique,
} from "../../shared/form-validation";
import type {
  Field,
  Page,
  ProviderAccountForm,
  ProviderAccountValues,
} from "./registration.contracts";

export type RegistrationModel = { page: Page; form: ProviderAccountForm };
const key = (value: unknown) => {
  const result = identifier(value);
  if (
    !/^[a-z][a-z0-9_]*$/.test(result) ||
    ["constructor", "prototype", "__proto__"].includes(result)
  )
    invalid();
  return result;
};
const option = object({ label: string, value: string, disabled: boolean });
const fieldSchema = object({
  key,
  id,
  name: string,
  type: oneOf(["hidden", "text", "textarea", "number", "url", "select"]),
  label: nullable(string),
  required: boolean,
  placeholder: nullable(string),
  min: nullable(number),
  max: nullable(number),
  step: nullable(string),
  options: array(option),
  value: string,
});
function readField(value: unknown): Field {
  const input = record(value),
    result: Field = fieldSchema(input);
  if (result.name !== "provider_account[" + result.key + "]") invalid();
  unique(result.options.map((item) => item.value));
  if (result.type !== "select" && result.options.length) invalid();
  if (result.min !== null && result.max !== null && result.min > result.max) invalid();
  if (input.presentations !== undefined) {
    result.presentations = dictionary(
      input.presentations,
      object({ label: string, placeholder: string }),
      8,
    );
  }
  if (input.wrapper_id !== undefined) result.wrapper_id = id(input.wrapper_id);
  if (input.help !== undefined) result.help = nullable(string)(input.help);
  if (input.default !== undefined) result.default = string(input.default);
  if (input.visible_when !== undefined)
    result.visible_when = nullable(object({ field: key, equals: string }))(input.visible_when);
  if (input.reference !== undefined)
    result.reference = nullable(
      object({
        provider_id: id,
        version: (value) => integer(value, 1),
        mode: string,
        result_limit: (value) => integer(value, 1, 100),
      }),
    )(input.reference);
  return result;
}
function dictionary<T>(value: unknown, read: (value: unknown) => T, limit = 64): Record<string, T> {
  const entries = Object.entries(record(value));
  if (entries.length > limit) invalid();
  return Object.fromEntries(entries.map(([name, item]) => [key(name), read(item)]));
}
const section = object({ id, number: string, title: string, field_keys: array(key, 64) });
const fixedKeys = [
  "provider_account_id",
  "credential_ref",
  "display_name",
  "provider_type",
  "backend_type",
  "backend_key",
  "allowed_services",
  "allowed_directions",
  "allowed_stations",
  "max_quota",
] as const;

export function registrationFields(form: ProviderAccountForm) {
  return [
    ...Object.values(form.fields),
    ...form.connector.configuration.sections.flatMap((section) => section.fields),
  ];
}
export function registrationValues(form: ProviderAccountForm): ProviderAccountValues {
  return Object.fromEntries(registrationFields(form).map((field) => [field.key, field.value]));
}
export function sameRegistrationValues(left: ProviderAccountValues, right: ProviderAccountValues) {
  const keys = Object.keys(left);
  return keys.length === Object.keys(right).length && keys.every((key) => left[key] === right[key]);
}
export function readRegistrationForm(value: unknown): ProviderAccountForm {
  const form = object({
    id,
    hidden_field_keys: array(key, 2),
    sections: object({
      network_identity: section,
      credential_registry: section,
      organization_guardrails: section,
    }),
    fields: (value) => dictionary(value, readField, fixedKeys.length),
    connector: object({
      options: array(option),
      selected: object({
        id,
        form_value: string,
        provider_type: string,
        client_key: string,
        label: string,
        description: string,
      }),
      configuration: object({
        id,
        kind: literal("provider_connector"),
        description: nullable(string),
        sections: array(
          object({
            id,
            fields_id: id,
            number: string,
            title: string,
            description: nullable(string),
            fields: array(readField, 64),
          }),
          12,
        ),
      }),
      boundary: object({ id, text: string }),
    }),
    credential_note: object({ id, text: string }),
    actions: object({
      submit: object({ id, label: string }),
      cancel: object({ id, label: string, href: literal("/provider-accounts") }),
    }),
  })(value);
  if (fixedKeys.some((name) => !Object.hasOwn(form.fields, name))) invalid();
  for (const [name, field] of Object.entries(form.fields)) if (field.key !== name) invalid();
  const hidden = form.hidden_field_keys;
  if (
    hidden.length !== 2 ||
    !hidden.includes("provider_account_id") ||
    !hidden.includes("credential_ref")
  )
    invalid();
  const referenced = [
    ...hidden,
    ...Object.values(form.sections).flatMap((section) => section.field_keys),
  ];
  unique(referenced);
  if (
    referenced.length !== fixedKeys.length ||
    referenced.some((name) => !Object.hasOwn(form.fields, name))
  )
    invalid();
  const fields = registrationFields(form);
  unique(fields.map((field) => field.key));
  const ids = [
    form.id,
    ...fields.map((field) => field.id),
    ...fields.flatMap((field) => (field.wrapper_id ? [field.wrapper_id] : [])),
    ...Object.values(form.sections).map((section) => section.id),
    form.connector.selected.id,
    form.connector.configuration.id,
    form.connector.boundary.id,
    form.credential_note.id,
    ...form.connector.configuration.sections.flatMap((section) => [section.id, section.fields_id]),
    form.actions.submit.id,
    form.actions.cancel.id,
  ];
  unique(ids);
  for (const field of fields) {
    if (
      field.visible_when &&
      !fields.some((candidate) => candidate.key === field.visible_when?.field)
    )
      invalid();
    if ((field.type === "hidden") !== hidden.includes(field.key)) invalid();
  }
  for (const name of fixedKeys) {
    const expected = hidden.includes(name)
      ? "hidden"
      : ["provider_type", "backend_type"].includes(name)
        ? "select"
        : name === "max_quota"
          ? "number"
          : "text";
    if (form.fields[name].type !== expected) invalid();
  }
  for (const name of hidden) identifier(form.fields[name].value);
  if (
    form.connector.selected.form_value !== form.fields.provider_type.value ||
    JSON.stringify(form.connector.options) !== JSON.stringify(form.fields.provider_type.options)
  )
    invalid();
  unique(form.connector.options.map((option) => option.value));
  for (const name of ["provider_type", "backend_type"]) {
    const field = form.fields[name];
    if (!field.options.some((option) => option.value === field.value && !option.disabled))
      invalid();
  }
  if (
    !["env", "external"].includes(form.fields.backend_type.value) ||
    form.fields.backend_type.options.some((option) => !["env", "external"].includes(option.value))
  )
    invalid();
  return form;
}
export function readRegistration(value: unknown, version: number): RegistrationModel {
  if (version !== 1) invalid();
  return object({
    page: object({
      id,
      heading: string,
      subtitle: string,
      breadcrumbs: array(
        object({ label: string, href: nullable(literal("/provider-accounts")) }),
        12,
      ),
    }),
    form: readRegistrationForm,
  })(value);
}
export function registrationReceipt(value: unknown) {
  const envelope = record(value);
  text(envelope.receiptId);
  const completedAt = text(envelope.completedAt);
  if (!Number.isFinite(Date.parse(completedAt))) invalid();
  return record(envelope.result);
}
export function readRegistrationPatch(receipt: unknown, initial: ProviderAccountForm) {
  const form = readRegistrationForm(record(registrationReceipt(receipt).patch).form);
  if (
    form.id !== initial.id ||
    form.hidden_field_keys.some((name) => form.fields[name].value !== initial.fields[name].value)
  )
    invalid();
  return form;
}
export function registrationReady(form: ProviderAccountForm) {
  const values = registrationValues(form);
  return registrationFields(form).every((field) => {
    if (field.visible_when && values[field.visible_when.field] !== field.visible_when.equals)
      return true;
    if (field.required && !field.value.trim()) return false;
    if (!field.value) return true;
    if (field.type === "select")
      return field.options.some((option) => option.value === field.value && !option.disabled);
    if (field.type === "number") {
      const value = Number(field.value);
      return (
        Number.isFinite(value) &&
        (field.min === null || value >= field.min) &&
        (field.max === null || value <= field.max) &&
        (field.key !== "max_quota" || Number.isSafeInteger(value))
      );
    }
    return true;
  });
}
