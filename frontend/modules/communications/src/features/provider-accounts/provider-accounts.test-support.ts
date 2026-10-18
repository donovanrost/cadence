import type {
  Field,
  FixedFieldKey,
  ProviderAccountForm,
  Page as RegistrationPage,
} from "./registration.contracts";
import type { GrantValues, GrantField } from "./detail.contracts";
import type { ProviderAccountShowProps } from "./detail.contracts";

export function registrationFixture(): { page: RegistrationPage; form: ProviderAccountForm } {
  const option = (value: string) => ({ value, label: value, disabled: false });
  const field = (key: string, value = "", type: Field["type"] = "text"): Field => ({
    key,
    id: "account-" + key,
    name: "provider_account[" + key + "]",
    value,
    type,
    label: key,
    required: false,
    placeholder: null,
    min: null,
    max: null,
    step: null,
    options: [],
  });
  const fields = {
    provider_account_id: field("provider_account_id", "account-1", "hidden"),
    credential_ref: field("credential_ref", "registry-reference", "hidden"),
    display_name: field("display_name", "Relay"),
    provider_type: {
      ...field("provider_type", "simulator", "select"),
      options: [option("simulator"), option("other")],
    },
    backend_type: {
      ...field("backend_type", "external", "select"),
      options: [option("external"), option("env")],
    },
    backend_key: {
      ...field("backend_key", "providers/relay"),
      presentations: {
        external: { label: "External locator", placeholder: "Locator" },
        env: { label: "Environment variable", placeholder: "VARIABLE" },
      },
    },
    max_quota: { ...field("max_quota", "10", "number"), min: 0 },
    allowed_services: field("allowed_services"),
    allowed_directions: field("allowed_directions"),
    allowed_stations: field("allowed_stations"),
  };
  const section = (id: string, field_keys: FixedFieldKey[]) => ({
    id,
    number: "01",
    title: id,
    field_keys,
  });
  return {
    page: {
      id: "registration-page",
      heading: "Register Provider Account",
      subtitle: "Organization-owned account",
      breadcrumbs: [{ label: "Provider Accounts", href: "/provider-accounts" }],
    },
    form: {
      id: "registration-form",
      hidden_field_keys: ["provider_account_id", "credential_ref"],
      fields,
      sections: {
        network_identity: section("identity", ["display_name", "provider_type"]),
        credential_registry: section("credentials", ["backend_type", "backend_key"]),
        organization_guardrails: section("guardrails", [
          "allowed_services",
          "allowed_directions",
          "allowed_stations",
          "max_quota",
        ]),
      },
      connector: {
        options: fields.provider_type.options,
        selected: {
          id: "connector",
          form_value: "simulator",
          provider_type: "simulator",
          client_key: "simulator",
          label: "Simulator",
          description: "Compiled connector",
        },
        configuration: {
          id: "configuration",
          kind: "provider_connector",
          description: null,
          sections: [
            {
              id: "connection",
              fields_id: "connection-fields",
              number: "02",
              title: "Connection",
              description: null,
              fields: [
                field("endpoint", "https://provider.test", "url"),
                {
                  ...field("notes", "", "textarea"),
                  visible_when: { field: "backend_type", equals: "external" },
                },
              ],
            },
          ],
        },
        boundary: { id: "boundary", text: "Missions receive grants, not credentials." },
      },
      credential_note: { id: "credential-note", text: "Secret material is never returned." },
      actions: {
        submit: { id: "register", label: "Register" },
        cancel: { id: "cancel", label: "Cancel", href: "/provider-accounts" },
      },
    },
  };
}

export function detailFixture(): ProviderAccountShowProps {
  const values: GrantValues = {
    mission_id: "mission-1",
    allowed_services: "telemetry",
    allowed_stations: "",
    max_quota: "10",
    grant_reason: "",
  };
  const fields = Object.fromEntries(
    Object.entries(values).map(([key, value]) => [
      key,
      {
        key,
        value,
        id: "grant-" + key,
        name: "grant[" + key + "]",
        type: key === "mission_id" ? "select" : key === "max_quota" ? "number" : "text",
        label: key,
        required: false,
        min: key === "max_quota" ? 0 : null,
        placeholder: null,
        options:
          key === "mission_id"
            ? [{ value: "mission-1", label: "Mission One", disabled: false }]
            : [],
      },
    ]),
  ) as Record<keyof GrantValues, GrantField>;
  const action = (id: string) => ({ id, label: id, disabled: false, payload: {} });
  return {
    page: {
      id: "detail-page",
      header: {
        title: "Relay",
        subtitle: "Provider Account",
        config_label: "Config v3",
        breadcrumbs: [{ label: "Accounts", href: "/provider-accounts" }],
      },
      grants: {
        card_id: "grants",
        heading: "Grants",
        subtitle: "Mission access",
        stream_id: "grants-stream",
        empty: { id: "grants-empty", text: "No grants" },
      },
      grant_form_card: { id: "grant-card", heading: "Grant access", subtitle: "Scoped access" },
      audit: {
        card_id: "audit",
        heading: "Audit",
        subtitle: "Activity",
        stream_id: "audit-stream",
        empty: { id: "audit-empty", text: "No activity" },
      },
    },
    actions: {
      validate: { ...action("validate-account"), icon: "hero-check" },
      rotate: { ...action("rotate-credential"), icon: "hero-key" },
      revoke: { ...action("revoke-credential"), confirm: "Revoke credential?" },
    },
    stats: [{ id: "config-version", label: "Version", value: 3 }],
    grant_form: {
      id: "grant-form",
      values,
      fields,
      action: { id: "grant-submit", label: "Grant" },
    },
    configuration: {
      id: "configuration",
      title: "Configuration",
      rows: [{ label: "Endpoint", value: "https://provider.test", mono: true, wrapper_id: null }],
    },
    ingestion: { id: "ingestion", title: "Ingestion", description: "Inbound events", rows: [] },
    guardrails: { id: "guardrails", title: "Guardrails", json: '{"max_quota":10}' },
    diagnostics: { id: "diagnostics", title: "Diagnostics", columns: [] },
    account_grants: [
      {
        id: "grant-1",
        __dom_id: "grant-row-1",
        provider_account_grant_id: "grant-1",
        mission_name: "Mission One",
        version_label: "v2",
        restriction_summary: "telemetry only",
        lifecycle: { status: "ready", label: "Active" },
        revoke: {
          id: "revoke-grant-1",
          label: "Revoke",
          confirm: "Revoke mission grant?",
          payload: { "grant-id": "grant-1" },
        },
      },
    ],
    account_audit: [
      {
        id: "entry-1",
        __dom_id: "audit-row-1",
        provider_audit_entry_id: "entry-1",
        recorded_at: "2026-09-07",
        action: "grant",
        outcome: { status: "ready", label: "Succeeded" },
      },
    ],
  };
}

export function listFixture(empty = false): import("./list.contracts").ProviderAccountDirectory {
  return {
    organization_id: "org-1",
    count: empty ? 0 : 1,
    provider_accounts: empty
      ? []
      : [
          {
            __dom_id: "provider-account-account-1",
            id: "provider-account-account-1",
            provider_account_id: "account-1",
            display_name: "Relay",
            status: "ready",
            status_label: "Ready",
            provider: "Simulator",
            config: "v3",
            credential: "Registered",
            events: "0",
            endpoint: "https://provider.test",
            href: "/provider-accounts/account-1",
          },
        ],
  };
}
