import type { Field, Page, TransportForm } from "./transport-new.contracts";

export function transportFormPayload(): { page: Page; form: TransportForm } {
  const field = (key: string, id: string, type: Field["type"] = "text", value = ""): Field => ({
    key,
    id,
    name: `transport[${key}]`,
    type,
    label: key,
    required: false,
    placeholder: null,
    options: [],
    value,
    provider_managed_id: null,
  });
  return {
    page: {
      id: "comms-transport-new-page",
      title: "New Transport",
      subtitle: "Transport",
      breadcrumbs: [],
    },
    form: {
      id: "transport-form",
      selected_origin: "direct",
      can_submit: false,
      sections: {
        identity: { id: "identity", number: "01", title: "Identity" },
        origin: { id: "origin", number: "02", title: "Origin" },
        source: { id: "source", number: "03", title: "Source" },
        provider_capability: { id: "capability", number: "04", title: "Capability" },
        review: { id: "review", number: "06", title: "Review" },
      },
      fields: {
        display_name: field("display_name", "transport-display-name"),
        origin: field("origin", "transport-origin", "select", "direct"),
        transport_kind: field("transport_kind", "transport-kind", "select", "tcp_socket"),
        mission_provider_id: field("mission_provider_id", "transport-provider", "select"),
        service_profile_id: field("service_profile_id", "transport-service-profile", "select"),
        delivery_profile_id: field("delivery_profile_id", "transport-delivery-profile", "select"),
      },
      origin_cards: [],
      direct_configuration: {
        id: "transport-direct-configuration",
        kind: "transport_kind",
        description: null,
        active: true,
        sections: [],
      },
      provider: {
        active: false,
        profile_fields_id: "profiles",
        ready_count: 0,
        versions: [],
        selected: null,
        empty_state: {
          id: "empty",
          visible: true,
          message: "",
          action: { label: "", href: "/missions/mission-1/comms/providers" },
        },
        operator_summary: null,
        derivation_error: null,
      },
      provider_derived: {
        active: false,
        id: "derived",
        number: "05",
        title: "Derived",
        description: "",
        configuration: { id: "configuration", rows: [], empty_text: "" },
      },
      review: {
        configuration_summary_id: "summary",
        ownership: { label: "", value: "", source: "" },
        readiness: { label: "", status: "attention", value: "", endpoint: "" },
        error: null,
        error_id: "error",
        diagnostics: { id: "diagnostics", label: "", json_id: "json", json: "{}" },
      },
      actions: {
        submit: { id: "create-transport-button", label: "Create" },
        cancel: { id: "cancel", label: "Cancel", href: "/missions/mission-1/comms/transports" },
      },
    },
  };
}
