import { identifier, integer, invalid, record, text } from "../../shared/read-validation";
import {
  array,
  boolean,
  id,
  literal,
  nullable,
  object,
  oneOf,
  string,
  unique,
} from "../../shared/form-validation";
import { registrationReceipt } from "./registration.validation";
import type { GrantField, GrantValues } from "./detail.contracts";

export const grantKeys = [
  "mission_id",
  "allowed_services",
  "allowed_stations",
  "max_quota",
  "grant_reason",
] as const;
const emptyPayload = (value: unknown): Record<string, never> => {
  if (Object.keys(record(value)).length) invalid();
  return {};
};
const empty = object({ id, text: string });
const breadcrumb = object({ label: string, href: nullable(literal("/provider-accounts")) });
const row = object({ label: string, value: string, mono: boolean, wrapper_id: nullable(id) });
const rows = array(row, 32);
const card = object({ id, title: string, rows });
const action = { id, label: string, disabled: boolean, payload: emptyPayload };
const icon = (value: unknown) => {
  const result = string(value);
  return /^hero-[a-z0-9-]+$/.test(result) ? result : invalid();
};
const fields = Object.fromEntries(
  grantKeys.map((name) => [
    name,
    object({
      key: literal(name),
      id,
      name: literal("grant[" + name + "]"),
      type: literal(name === "mission_id" ? "select" : name === "max_quota" ? "number" : "text"),
      label: string,
      value: string,
      required: boolean,
      min: nullable((value) => integer(value)),
      placeholder: nullable(string),
      options: array(object({ label: string, value: string, disabled: boolean }), 500),
    }),
  ]),
) as Record<keyof GrantValues, (value: unknown) => GrantField>;
const values = object(Object.fromEntries(grantKeys.map((name) => [name, string]))) as (
  value: unknown,
) => GrantValues;
const grant = object({
  id,
  __dom_id: id,
  provider_account_grant_id: id,
  mission_id: id,
  version: (value) => integer(value, 1),
  account_version: (value) => integer(value, 1),
  mission_name: string,
  version_label: string,
  restriction_summary: nullable(string),
  lifecycle: object({ status: oneOf(["ready", "blocked"]), label: string }),
  revoke: nullable(
    object({ id, label: string, confirm: string, payload: object({ "grant-id": id }) }),
  ),
});
const audit = object({
  id,
  __dom_id: id,
  provider_audit_entry_id: id,
  recorded_at: string,
  action: string,
  outcome: object({ status: oneOf(["ready", "blocked"]), label: string }),
});
const account = object({
  organization_id: id,
  provider_account_id: id,
  version: (value) => integer(value, 1),
  credential_ref: id,
  credential_version: (value) => integer(value, 1),
  credential_status: oneOf(["active", "revoked"]),
});
const shape = object({
  account,
  page: object({
    id,
    header: object({
      title: string,
      subtitle: string,
      config_label: string,
      breadcrumbs: array(breadcrumb, 12),
    }),
    grants: object({ card_id: id, heading: string, subtitle: string, stream_id: id, empty }),
    grant_form_card: object({ id, heading: string, subtitle: string }),
    audit: object({ card_id: id, heading: string, subtitle: string, stream_id: id, empty }),
  }),
  actions: object({
    validate: object({ ...action, icon }),
    rotate: object({ ...action, icon }),
    revoke: nullable(object({ ...action, confirm: string })),
  }),
  stats: array(
    object({
      id,
      label: string,
      value: (value) => (typeof value === "number" ? integer(value) : string(value)),
    }),
    12,
  ),
  grant_form: object({ id, values, fields: object(fields), action: object({ id, label: string }) }),
  configuration: card,
  ingestion: object({ id, title: string, rows, description: string }),
  guardrails: object({
    id,
    title: string,
    json: (value) => {
      const result = text(value);
      try {
        record(JSON.parse(result));
      } catch {
        invalid();
      }
      return result;
    },
  }),
  diagnostics: object({ id, title: string, columns: array(rows, 4) }),
  account_grants: array(grant, 500),
  account_audit: array(audit, 20),
});
export type AccountDetailModel = ReturnType<typeof shape>;
export type AccountIdentity = AccountDetailModel["account"];

export function readAccountDetail(
  value: unknown,
  organizationId: string,
  version: number,
  expectedAccountId?: string,
) {
  if (version !== 1) invalid();
  const model = shape(value),
    account = model.account;
  if (
    account.organization_id !== identifier(organizationId) ||
    (expectedAccountId !== undefined && account.provider_account_id !== expectedAccountId) ||
    model.page.header.subtitle !== account.provider_account_id ||
    model.page.header.config_label !== "config v" + account.version
  )
    invalid();
  const missionField = model.grant_form.fields.mission_id;
  unique(missionField.options.map((option) => option.value));
  for (const key of grantKeys) {
    const field = model.grant_form.fields[key];
    if (
      field.value !== model.grant_form.values[key] ||
      field.min !== (key === "max_quota" ? 0 : null) ||
      (key !== "mission_id" && field.options.length)
    )
      invalid();
  }
  if (
    account.credential_status === "revoked" &&
    (!model.actions.validate.disabled ||
      !model.actions.rotate.disabled ||
      model.actions.revoke !== null)
  )
    invalid();
  const ids = [
    model.page.id,
    model.page.grants.card_id,
    model.page.grants.stream_id,
    model.page.grants.empty.id,
    model.page.audit.card_id,
    model.page.audit.stream_id,
    model.page.audit.empty.id,
    model.page.grant_form_card.id,
    model.grant_form.id,
    model.grant_form.action.id,
    ...grantKeys.map((key) => model.grant_form.fields[key].id),
    model.configuration.id,
    model.ingestion.id,
    model.guardrails.id,
    model.diagnostics.id,
    ...model.stats.map((item) => item.id),
    model.actions.validate.id,
    model.actions.rotate.id,
    ...(model.actions.revoke ? [model.actions.revoke.id] : []),
    ...model.account_grants.flatMap((item) => [
      item.__dom_id,
      ...(item.revoke ? [item.revoke.id] : []),
    ]),
    ...model.account_audit.map((item) => item.__dom_id),
    ...model.ingestion.rows.flatMap((item) => (item.wrapper_id ? [item.wrapper_id] : [])),
  ];
  unique(ids);
  unique(model.account_grants.map((item) => item.id));
  unique(model.account_audit.map((item) => item.id));
  for (const grant of model.account_grants) {
    if (
      grant.id !== grant.provider_account_grant_id ||
      grant.version_label !== "grant v" + grant.version + " · account v" + grant.account_version ||
      (grant.revoke &&
        (grant.revoke.payload["grant-id"] !== grant.id || grant.lifecycle.status !== "ready"))
    )
      invalid();
  }
  for (const entry of model.account_audit)
    if (entry.id !== entry.provider_audit_entry_id) invalid();
  return model;
}
export function readAccountUpdate(value: unknown, previous: AccountDetailModel) {
  const old = previous.account;
  const next = readAccountDetail(value, old.organization_id, 1, old.provider_account_id);
  if (
    next.account.version < old.version ||
    (next.account.version === old.version && next.account.credential_ref !== old.credential_ref) ||
    (next.account.credential_ref === old.credential_ref &&
      (next.account.credential_version < old.credential_version ||
        (next.account.credential_version === old.credential_version &&
          next.account.credential_status !== old.credential_status)))
  )
    invalid();
  for (const grant of previous.account_grants) {
    const updated = next.account_grants.find((item) => item.id === grant.id);
    if (
      !updated ||
      updated.mission_id !== grant.mission_id ||
      updated.version < grant.version ||
      (updated.version === grant.version &&
        (updated.account_version !== grant.account_version ||
          updated.lifecycle.status !== grant.lifecycle.status))
    )
      invalid();
  }
  return next;
}
export function readAccountPatch(receipt: unknown, previous: AccountDetailModel) {
  return readAccountUpdate(registrationReceipt(receipt).patch, previous);
}
export function readGrantValues(input: unknown): GrantValues {
  return values(input);
}
export function grantReady(model: AccountDetailModel, input: GrantValues) {
  if (
    !model.grant_form.fields.mission_id.options.some(
      (option) => option.value === input.mission_id && !option.disabled,
    )
  )
    return false;
  return (
    input.max_quota === "" ||
    (/^\d+$/.test(input.max_quota) && Number.isSafeInteger(Number(input.max_quota)))
  );
}
export function accountActionIdentity(account: AccountIdentity) {
  return {
    provider_account_id: account.provider_account_id,
    expected_account_version: account.version,
    credential_ref: account.credential_ref,
    expected_credential_version: account.credential_version,
  };
}
