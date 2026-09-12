import type { FormField, Page, RoutingRuleForm, RoutingRuleOptions } from "./routing-new.contracts";

export function routingFormPayload(): {
  page: Page;
  form: RoutingRuleForm;
  options: RoutingRuleOptions;
} {
  const field = (key: string, type: FormField["type"] = "text"): FormField => ({
    id: `routing_rule_${key}`,
    name: `routing_rule[${key}]`,
    type,
    label: key,
    required: true,
    value: "",
  });
  return {
    page: {
      id: "comms-routing-new-page",
      title: "New Routing Rule",
      subtitle: "Routing",
      breadcrumbs: [],
    },
    form: {
      id: "routing-rule-form",
      sections: {
        intent: { number: "01", title: "Intent" },
        transport: { number: "02", title: "Transport" },
        policy: { number: "03", title: "Policy" },
      },
      fields: {
        display_name: field("display_name"),
        purpose_label: field("purpose_label"),
        spacecraft_id: field("spacecraft_id", "select"),
        transport_ref: field("transport_ref", "select"),
        direction: field("direction", "select"),
        role: field("role", "select"),
      },
      actions: {
        submit: { id: "create-routing-rule-button", label: "Create" },
        cancel: { id: "cancel", label: "Cancel", href: "/missions/mission-1/comms/routing" },
      },
    },
    options: { spacecraft: [], transports: [], directions: [], roles: [] },
  };
}
