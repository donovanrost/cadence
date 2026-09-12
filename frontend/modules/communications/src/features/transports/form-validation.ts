import type { Page, TransportForm } from "./transport-new.contracts.ts";
import type { ReadContext } from "../../shared/read-contracts.ts";
import { integer, invalid, missionPath } from "../../shared/read-validation.ts";
import {
  actions,
  array,
  boolean,
  envelope,
  id,
  link,
  literal,
  nullable,
  number,
  object,
  oneOf,
  page,
  section,
  string,
  unique,
} from "../../shared/form-validation.ts";

const keys = [
  "display_name",
  "origin",
  "transport_kind",
  "mission_provider_id",
  "service_profile_id",
  "delivery_profile_id",
] as const;
const option = object({ label: string, value: string, disabled: boolean });
const detail = object({ label: string, value: string, mono: boolean });
const key = (value: unknown) => {
  const name = id(value);
  if (!/^[a-z][a-z0-9_]*$/.test(name) || ["constructor", "prototype", "__proto__"].includes(name))
    invalid();
  return name;
};
const configurationField = object({
  key,
  wrapper_id: id,
  id,
  name: string,
  type: oneOf(["text", "number", "select", "checkbox"]),
  label: string,
  required: boolean,
  placeholder: nullable(string),
  help: nullable(string),
  step: nullable((value) => (typeof value === "string" ? string(value) : number(value))),
  min: nullable(number),
  max: nullable(number),
  default: string,
  value: string,
  options: array(option),
  visible: boolean,
  visible_when: nullable(object({ field: key, equals: string })),
});
export function readForm(
  value: unknown,
  context: ReadContext,
): { page: Page; form: TransportForm } {
  const base = missionPath(context) + "/comms/transports";
  const field = (key: (typeof keys)[number], type: "text" | "select") =>
    object({
      key: literal(key),
      id,
      name: literal("transport[" + key + "]"),
      type: literal(type),
      label: string,
      required: boolean,
      placeholder: nullable(string),
      options: array(option),
      value: string,
      provider_managed_id: nullable(id),
    });
  const result = object({
    page: page(context),
    form: object({
      id,
      selected_origin: oneOf(["direct", "provider_managed"]),
      can_submit: boolean,
      sections: object({
        identity: section,
        origin: section,
        source: section,
        provider_capability: section,
        review: section,
      }),
      fields: object({
        display_name: field("display_name", "text"),
        origin: field("origin", "select"),
        transport_kind: field("transport_kind", "select"),
        mission_provider_id: field("mission_provider_id", "select"),
        service_profile_id: field("service_profile_id", "select"),
        delivery_profile_id: field("delivery_profile_id", "select"),
      }),
      origin_cards: array(
        object({
          value: oneOf(["direct", "provider_managed"]),
          label: string,
          description: string,
        }),
        2,
      ),
      direct_configuration: object({
        id,
        kind: string,
        description: nullable(string),
        active: boolean,
        sections: array(
          object({
            id,
            number: string,
            title: string,
            fields_id: id,
            description: nullable(string),
            fields: array(configurationField, 100),
          }),
          20,
        ),
      }),
      provider: object({
        active: boolean,
        profile_fields_id: id,
        ready_count: (value) => integer(value),
        versions: array(object({ id, version: (value) => integer(value, 1) })),
        selected: nullable(
          object({
            display_name: string,
            version: (value) => integer(value, 1),
            status: literal("ready"),
            status_label: string,
          }),
        ),
        empty_state: object({
          id,
          visible: boolean,
          message: string,
          action: object({ label: string, href: link(context) }),
        }),
        operator_summary: nullable(object({ id, label: string, text: string, endpoint: string })),
        derivation_error: nullable(string),
      }),
      provider_derived: object({
        active: boolean,
        id,
        number: string,
        title: string,
        description: string,
        configuration: object({ id, rows: array(detail, 100), empty_text: nullable(string) }),
      }),
      review: object({
        configuration_summary_id: id,
        ownership: object({ label: string, value: string, source: string }),
        readiness: object({
          label: string,
          status: oneOf(["ready", "attention"]),
          value: string,
          endpoint: string,
        }),
        error: nullable(string),
        error_id: id,
        diagnostics: object({ id, label: string, json_id: id, json: string }),
      }),
      actions: actions(context, base),
    }),
  })(envelope(value, context, base + "/new"));
  const form = result.form;
  unique(form.provider.versions.map((provider) => provider.id));
  if (
    form.provider.versions.length !== form.fields.mission_provider_id.options.length ||
    form.fields.mission_provider_id.options.some(
      (option) => !form.provider.versions.some((provider) => provider.id === option.value),
    )
  )
    invalid();
  if (
    form.selected_origin !== form.fields.origin.value ||
    form.direct_configuration.active !== (form.selected_origin === "direct") ||
    form.provider.active !== (form.selected_origin === "provider_managed")
  )
    invalid();
  const configuration = form.direct_configuration.sections.flatMap((section) => section.fields);
  unique([...keys, ...configuration.map((field) => field.key)]);
  unique([...Object.values(form.fields), ...configuration].map((field) => field.id));
  unique(form.origin_cards.map((card) => card.value));
  const allKeys = new Set<string>([...keys, ...configuration.map((field) => field.key)]);
  for (const field of configuration) {
    if (
      field.name !== "transport[" + field.key + "]" ||
      (field.visible_when && !allKeys.has(field.visible_when.field)) ||
      (field.min !== null && field.max !== null && field.min > field.max)
    )
      invalid();
    unique(field.options.map((option) => option.value));
  }
  for (const field of Object.values(form.fields))
    unique(field.options.map((option) => option.value));
  return result;
}
