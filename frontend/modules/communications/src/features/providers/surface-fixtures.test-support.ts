import { providerNewPayload } from "./fixtures.test-support";
import type { ProviderDetailModel } from "./provider-detail.contracts";
const base = "/missions/mission-1/comms/providers";
const navigation = (suffix = "") => ({
  fallback_href: base + suffix,
  breadcrumbs: [{ label: "Mission", href: "/missions/mission-1" }],
});
export function providerNewSurface(empty = false) {
  const data = providerNewPayload();
  const bindings = [1, 2].map((i) => ({
    grant_id: "grant-" + i,
    grant_version: i,
    account_id: "account-" + i,
    account_version: i + 2,
    summary: {
      id: "mission-provider-account-summary",
      ownership_label: "Organization-owned configuration",
      display_name: "Ground Network " + i,
      version_label: `account v${i + 2} · grant v${i}`,
      badge: { status: "ready" as const, label: "Granted" },
      restrictions: [{ label: "Mission restrictions", summary: "Downlink only" }],
    },
  }));
  data.accounts.bindings = empty ? [] : bindings;
  data.accounts.empty = empty;
  data.accounts.options = data.accounts.bindings.map((b) => ({
    label: b.summary.display_name + " · " + b.summary.version_label,
    value: b.grant_id,
  }));
  data.accounts.selected = empty ? null : (bindings[0]?.summary ?? null);
  data.form.fields.provider_account_grant_id.options = data.accounts.options;
  data.form.fields.provider_account_grant_id.value = empty ? "" : "grant-1";
  data.form.fields.display_name.value = "Mission downlink";
  data.form.fields.policy_mode.value = "approval_required";
  data.form.fields.policy_mode.options = [
    { label: "Require approval", value: "approval_required" },
    { label: "Bounded automatic", value: "bounded_automatic" },
  ];
  data.form.fields.deadline_behavior.value = "retain_last_accepted";
  data.form.fields.deadline_behavior.options = [
    { label: "Retain accepted schedule", value: "retain_last_accepted" },
    { label: "Cancel if actionable", value: "cancel_if_actionable" },
  ];
  for (const key of ["provider_account_grant_id", "policy_mode", "deadline_behavior"] as const)
    data.form.fields[key].type = "select";
  for (const key of [
    "maximum_earlier_start_shift_seconds",
    "maximum_later_start_shift_seconds",
    "maximum_earlier_end_shift_seconds",
    "maximum_later_end_shift_seconds",
    "minimum_retained_duration_seconds",
  ] as const) {
    data.form.fields[key].type = "number";
    data.form.fields[key].min = key === "minimum_retained_duration_seconds" ? 1 : 0;
    data.form.fields[key].value = key === "minimum_retained_duration_seconds" ? "" : "0";
  }
  data.form.conditional.bounded_policy.field_keys = [
    "maximum_earlier_start_shift_seconds",
    "maximum_later_start_shift_seconds",
    "maximum_earlier_end_shift_seconds",
    "maximum_later_end_shift_seconds",
    "minimum_retained_duration_seconds",
    "approved_station_substitutions",
  ];
  data.form.conditional.approval_guidance.active = true;
  data.form.actions.cancel.href = base;
  data.form.actions.submit.id = "create-mission-provider-button";
  return { navigation: navigation("/new"), data };
}
export function providerDetailSurface(version = 1) {
  const section = (name: string) => ({
    id: name,
    heading: name,
    subtitle: "Profiles synchronized from the provider.",
    empty: true,
    empty_copy: "No profiles yet.",
    table_id: name + "-table",
    table_body_id: name + "-body",
    columns: [],
  });
  const data: ProviderDetailModel = {
    navigation: { breadcrumbs: navigation().breadcrumbs },
    provider: {
      page_id: "comms-provider-show-page",
      display_name: "Simulator",
      provider_id: "provider-1",
      simulated_badge: { id: "simulated-provider-badge", label: "Simulated" },
      version: "v" + version,
      summary_tiles: [],
    },
    actions: {
      validate: { id: "validate-provider-button", label: "Validate", disabled: false },
      sync: { id: "sync-provider-button", label: "Sync Inventory", disabled: false },
      archive: {
        id: "archive-provider-button",
        label: "Archive",
        disabled: false,
        confirm: "Archive this provider?",
      },
    },
    profiles: { service: section("service"), delivery: section("delivery") },
    details: {
      configuration: {
        id: "configuration",
        title: "Configuration",
        rows: [{ label: "Account", value: "account-1 · v3", mono: true }],
      },
      delivery_policy: { id: "policy", title: "Delivery policy", rows: [] },
      capabilities: {
        id: "capabilities",
        title: "Capabilities",
        empty: true,
        empty_copy: "Validate to load capabilities.",
        items: [],
      },
      version_history: { id: "history", title: "Version history", stream_id: "history-rows" },
    },
    diagnostics: {
      id: "diagnostics",
      label: "Admin diagnostics",
      json_id: "diagnostics-json",
      rows: [],
      json: "{}",
    },
    service_profiles: [],
    delivery_profiles: [],
    provider_versions: [{ __dom_id: "version-" + version, version, lifecycle_state: "ACTIVE" }],
  };
  return { navigation: navigation("/provider-1"), data };
}
export function providerListSurface() {
  const element = { attrs: {} },
    label = { attrs: {}, text: "Providers" };
  const create = {
    attrs: { href: base + "/new", class: "btn btn-primary btn-sm", id: "new-provider-link" },
    text: "New provider",
    icon: element,
  };
  return {
    navigation: navigation(),
    data: {
      presentation: {
        root: { attrs: { id: "comms-providers-page", class: "space-y-6" } },
        header: {
          attrs: {},
          body: element,
          content: element,
          breadcrumbs: { attrs: {}, items: [] },
          title: { ...label, suffix: { ...label, text: "1 configured" } },
          subtitle: { ...label, text: "Mission ground network providers" },
          actions: { attrs: {}, new_provider: create },
        },
        empty_state: null,
        card: {
          attrs: { class: "card bg-base-200 border border-base-300" },
          body: element,
          table_component: element,
          rows: [
            {
              id: "mission-provider-provider-1",
              display_name: "Simulator",
              provider_type: "Simulated",
              server_url: "http://127.0.0.1:4101",
              status: "ready" as const,
              status_label: "Healthy",
              account_binding: "account-1 · v3",
              grant_binding: "grant-1 · v1",
              last_synced_at: "Never",
              version: "v1",
              href: base + "/provider-1",
            },
          ],
        },
      },
    },
  };
}
