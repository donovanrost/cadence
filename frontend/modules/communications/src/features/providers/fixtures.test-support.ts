import type {
  Accounts,
  Notes,
  Page,
  ProviderForm,
  Field,
  ProviderFieldKey,
} from "./provider-new.contracts";

export function providerFormPayload(): ProviderForm {
  const field = (key: ProviderFieldKey): Field => ({
    key,
    id: `provider_${key}`,
    name: `provider[${key}]`,
    type: "text" as const,
    label: key,
    required: false,
    placeholder: null,
    min: null,
    options: [],
    value: "",
  });
  return {
    id: "mission-provider-form",
    sections: {
      binding: {
        id: "binding",
        number: "01",
        title: "Binding",
        field_keys: ["display_name", "provider_account_grant_id"],
      },
      resource_scope: {
        id: "resource",
        number: "02",
        title: "Resource",
        field_keys: ["permitted_resource_refs"],
      },
      delivery_policy: {
        id: "policy",
        number: "03",
        title: "Policy",
        field_keys: ["policy_mode", "deadline_behavior"],
      },
    },
    fields: {
      display_name: field("display_name"),
      provider_account_grant_id: field("provider_account_grant_id"),
      permitted_resource_refs: field("permitted_resource_refs"),
      policy_mode: field("policy_mode"),
      maximum_earlier_start_shift_seconds: field("maximum_earlier_start_shift_seconds"),
      maximum_later_start_shift_seconds: field("maximum_later_start_shift_seconds"),
      maximum_earlier_end_shift_seconds: field("maximum_earlier_end_shift_seconds"),
      maximum_later_end_shift_seconds: field("maximum_later_end_shift_seconds"),
      minimum_retained_duration_seconds: field("minimum_retained_duration_seconds"),
      approved_station_substitutions: field("approved_station_substitutions"),
      deadline_behavior: field("deadline_behavior"),
    },
    conditional: {
      approval_guidance: {
        id: "approval",
        active: false,
        visible_when: { field: "policy_mode", equals: "approval_required" },
        text: "",
      },
      bounded_policy: {
        id: "bounded",
        active: false,
        visible_when: { field: "policy_mode", equals: "bounded_automatic" },
        field_keys: [],
      },
    },
    actions: {
      submit: { id: "submit", label: "Create" },
      cancel: { id: "cancel", label: "Cancel", href: "/comms/providers" },
    },
  };
}

export function providerNewPayload(): {
  page: Page;
  accounts: Accounts;
  notes: Notes;
  form: ProviderForm;
} {
  return {
    page: {
      id: "comms-provider-new-page",
      title: "New Mission Provider",
      subtitle: "Provider setup.",
      breadcrumbs: [],
    },
    accounts: {
      empty: false,
      bindings: [],
      options: [],
      selected: null,
      empty_state: {
        id: "mission-provider-no-grants",
        heading: "No grants",
        message: "Grant an account.",
        action: { id: "open-provider-accounts-link", label: "Open", href: "/provider-accounts" },
      },
    },
    notes: {
      secret_boundary: { id: "secret", text: "Credentials remain server-side." },
      resource_boundary: { id: "resource", text: "Select permitted resources." },
    },
    form: providerFormPayload(),
  };
}
