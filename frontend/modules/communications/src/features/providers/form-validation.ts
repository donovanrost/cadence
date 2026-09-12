import type { ReadContext } from "../../shared/read-contracts.ts";
import { choice, integer, invalid, missionPath } from "../../shared/read-validation.ts";
import {
  actions,
  array,
  boolean,
  envelope,
  id,
  literal,
  nullable,
  object,
  page,
  string,
  unique,
} from "../../shared/form-validation.ts";
import { providerFieldKeys, type ProviderFieldKey } from "./provider-new.contracts.ts";

const option = object({ label: string, value: string });
const key = (v: unknown) => choice(v, providerFieldKeys);
const section = object({ id, number: string, title: string, field_keys: array(key, 11) });
const summary = object({
  id,
  ownership_label: string,
  display_name: string,
  version_label: string,
  badge: object({ status: literal("ready"), label: string }),
  restrictions: array(object({ label: string, summary: string }), 16),
});

export function readForm(value: unknown, context: ReadContext) {
  const base = missionPath(context) + "/comms/providers";
  const fields = Object.fromEntries(
    providerFieldKeys.map((name) => [
      name,
      object({
        key: literal(name),
        id,
        name: literal("provider[" + name + "]"),
        type: (v) => choice(v, ["text", "number", "select"]),
        label: string,
        required: boolean,
        placeholder: nullable(string),
        min: nullable((v) => integer(v)),
        options: array(option),
        value: string,
      }),
    ]),
  ) as { [K in ProviderFieldKey]: ReturnType<typeof fieldReader> };
  const result = object({
    page: page(context),
    accounts: object({
      empty: boolean,
      options: array(option),
      selected: nullable(summary),
      bindings: array(
        object({
          grant_id: id,
          grant_version: (v) => integer(v, 1),
          account_id: id,
          account_version: (v) => integer(v, 1),
          summary,
        }),
      ),
      empty_state: object({
        id,
        heading: string,
        message: string,
        action: object({
          id,
          label: string,
          href: (v) => (v === "/provider-accounts" ? v : invalid()),
        }),
      }),
    }),
    notes: object({
      secret_boundary: object({ id, text: string }),
      resource_boundary: object({ id, text: string }),
    }),
    form: object({
      id,
      sections: object({ binding: section, resource_scope: section, delivery_policy: section }),
      fields: object(fields),
      conditional: object({
        approval_guidance: object({
          id,
          active: boolean,
          visible_when: object({
            field: literal("policy_mode"),
            equals: literal("approval_required"),
          }),
          text: string,
        }),
        bounded_policy: object({
          id,
          active: boolean,
          visible_when: object({
            field: literal("policy_mode"),
            equals: literal("bounded_automatic"),
          }),
          field_keys: array(key, 11),
        }),
      }),
      actions: actions(context, base),
    }),
  })(envelope(value, context, base + "/new"));
  const { accounts, form } = result;
  const grant = form.fields.provider_account_grant_id.value;
  unique(accounts.bindings.map((item) => item.grant_id));
  unique(accounts.options.map((item) => item.value));
  if (
    accounts.empty !== (accounts.bindings.length === 0) ||
    accounts.options.length !== accounts.bindings.length ||
    accounts.options.some(
      (item) => !accounts.bindings.some((binding) => binding.grant_id === item.value),
    ) ||
    JSON.stringify(accounts.options) !==
      JSON.stringify(form.fields.provider_account_grant_id.options) ||
    (accounts.empty
      ? grant !== "" || accounts.selected !== null
      : !accounts.bindings.some(
          (item) =>
            item.grant_id === grant &&
            JSON.stringify(item.summary) === JSON.stringify(accounts.selected),
        ))
  )
    invalid();
  unique(Object.values(form.fields).map((field) => field.id));
  const referenced = [
    ...Object.values(form.sections).flatMap((section) => section.field_keys),
    ...form.conditional.bounded_policy.field_keys,
  ];
  unique(referenced);
  if (referenced.length !== providerFieldKeys.length) invalid();
  for (const field of Object.values(form.fields)) {
    unique(field.options.map((option) => option.value));
    const numeric = field.key.endsWith("_seconds");
    const select = ["provider_account_grant_id", "policy_mode", "deadline_behavior"].includes(
      field.key,
    );
    if (
      field.type !== (numeric ? "number" : select ? "select" : "text") ||
      field.min !==
        (numeric ? (field.key === "minimum_retained_duration_seconds" ? 1 : 0) : null) ||
      (!select && field.options.length !== 0)
    )
      invalid();
  }
  for (const [name, values] of [
    ["policy_mode", ["approval_required", "bounded_automatic"]],
    ["deadline_behavior", ["retain_last_accepted", "cancel_if_actionable"]],
  ] as const) {
    const field = form.fields[name];
    if (
      field.options.length !== values.length ||
      field.options.some((option) => !values.some((value) => value === option.value)) ||
      !values.some((value) => value === field.value)
    )
      invalid();
  }
  return result;
}

// Named return shape keeps dynamic field assembly typed without a broad response cast.
function fieldReader() {
  return object({
    key,
    id,
    name: string,
    type: (v) => choice(v, ["text", "number", "select"]),
    label: string,
    required: boolean,
    placeholder: nullable(string),
    min: nullable((v) => integer(v)),
    options: array(option),
    value: string,
  });
}
export type ProviderNewModel = ReturnType<typeof readForm>;
