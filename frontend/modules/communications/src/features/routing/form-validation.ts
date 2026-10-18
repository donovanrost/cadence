import type { Page, RoutingRuleForm, RoutingRuleOptions } from "./routing-new.contracts.ts";
import type { ReadContext } from "../../shared/read-contracts.ts";
import { invalid, missionPath } from "../../shared/read-validation.ts";
import {
  actions,
  array,
  boolean,
  envelope,
  formSection,
  id,
  literal,
  object,
  page,
  string,
  unique,
} from "../../shared/form-validation.ts";

export function readForm(
  value: unknown,
  context: ReadContext,
): { page: Page; form: RoutingRuleForm; options: RoutingRuleOptions } {
  const base = missionPath(context) + "/comms/routing";
  const field = (key: string, type: "text" | "select" = "text") =>
    object({
      id,
      name: literal("routing_rule[" + key + "]"),
      type: literal(type),
      label: string,
      required: boolean,
      value: string,
    });
  const options = array(object({ label: string, value: string }));
  const result = object({
    page: page(context),
    form: object({
      id,
      sections: object({ intent: formSection, transport: formSection, policy: formSection }),
      fields: object({
        display_name: field("display_name"),
        purpose_label: field("purpose_label"),
        spacecraft_id: field("spacecraft_id", "select"),
        transport_ref: field("transport_ref", "select"),
        direction: field("direction", "select"),
        role: field("role", "select"),
      }),
      actions: actions(context, base),
    }),
    options: object({
      spacecraft: options,
      transports: options,
      directions: options,
      roles: options,
    }),
  })(envelope(value, context, base + "/new"));
  unique(Object.values(result.form.fields).map((field) => field.id));
  for (const [key, options] of [
    ["spacecraft_id", result.options.spacecraft],
    ["transport_ref", result.options.transports],
    ["direction", result.options.directions],
    ["role", result.options.roles],
  ] as const) {
    unique(options.map((option) => option.value));
    const selected = result.form.fields[key].value;
    if (selected && !options.some((option) => option.value === selected)) invalid();
  }
  return result;
}
