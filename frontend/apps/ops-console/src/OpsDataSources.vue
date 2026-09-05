<script setup lang="ts">
import { reactive, watch } from "vue";
import CadenceField from "./ui/components/CadenceField.vue";
import CadencePanel from "./ui/components/CadencePanel.vue";
import CadenceStatTile from "./ui/components/CadenceStatTile.vue";

type EmptyPayload = Record<string, never>;
type StringMap = Record<string, string>;

type Link = {
  id?: string;
  href: string;
  label: string;
  icon?: string;
};

type FocusReturn = Link & {
  dashboard_id: string;
  panel: string;
  activity_filter: string;
  activity_event: string;
};

type FocusRemediation = {
  id: string;
  kind: string;
  title: string;
  detail: string;
  target: string;
  target_id: string;
  capability_rows: Array<{
    key: string;
    label: string;
    requested: string;
    supported: string;
  }>;
  candidate_rows: Array<{
    data_source_id: string;
    compatible: boolean;
    status_text: string;
    missing_text: string;
    reason_text: string;
  }>;
  action?:
    | {
        kind: "event";
        id: string;
        event: "open_register_source";
        payload: EmptyPayload;
        label: string;
        icon: string;
      }
    | ({ kind: "anchor" } & Link)
    | null;
  dashboard_return: FocusReturn | null;
};

type FocusResource = {
  id: string;
  selected_target: string;
  selected_id: string;
  transport_id: string;
  source_endpoint_id: string;
  ground_station_id: string;
  link_id: string;
  heading: string;
  rows: Array<{
    key: string;
    label: string;
    value: string;
    display_value: string;
    status: string;
    status_text: string;
    href: string | null;
  }>;
};

type FocusEvidence = {
  id: string;
  kind: string;
  mode: string;
  state: string;
  reason: string;
  title: string;
  detail: string;
  dashboard_return: FocusReturn | null;
};

type Focus = {
  state: string;
  data_source_id: string;
  source_binding_id: string;
  logical_source: string;
  realm: string;
  scope_kind: string;
  scope_id: string;
  contact_id: string;
  selected_target: string;
  selected_id: string;
  transport_id: string;
  source_endpoint_id: string;
  ground_station_id: string;
  link_id: string;
  source_empty_reason: string;
  requested_source_products: string;
  requested_product_families: string;
  source_dashboard_id: string;
  selected_evidence_kind: string;
  selected_source_evidence_mode: string;
  selected_source_evidence_state: string;
  notice: {
    id: string;
    icon: string;
    title: string;
    detail: string;
  } | null;
  remediation: FocusRemediation | null;
  resource: FocusResource | null;
  evidence: FocusEvidence | null;
};

type BindingRow = {
  binding_id: string;
  focused: boolean;
  logical_source_text: string;
  realm_text: string;
  binding_status: string;
  data_source_id: string;
  dataset_text: string;
  priority_text: string;
  version_text: string;
  active_from_text: string;
  active_to_text: string;
  current_event_id_text: string;
  source_status_text: string;
  source_kind_text: string;
  source_owner_text: string;
  source_isolation_text: string;
  source_adapter_text: string;
  credential_ref_text: string;
  health_status: string;
  health_reason_text: string;
  health_observed_at_text: string;
  health_event_type_text: string;
  source_readiness_status: string;
  source_readiness_policy_id: string;
  source_readiness_reason_text: string;
  change_action?: {
    id: string;
    event: "open_change_binding";
    payload: { "binding-id": string };
    label: string;
    icon: string;
  };
};

type BindingGroup = {
  id: string;
  logical_source_text: string;
  realm_text: string;
  group_status: string;
  count_label: string;
  rows: BindingRow[];
};

type SourceAction = {
  id: string;
  event:
    | "disable_source"
    | "enable_source"
    | "reconcile_tsdb_backend"
    | "deprovision_tsdb_backend"
    | "provision_tsdb_backend"
    | "probe_source"
    | "rotate_source_credential";
  payload: StringMap;
  label: string;
  icon: string;
  variant: "ghost" | "secondary" | "danger";
  confirm: string | null;
};

type SourceRow = {
  data_source_id: string;
  focused: boolean;
  status_text: string;
  kind_text: string;
  owner_text: string;
  isolation_text: string;
  adapter_text: string;
  credential_ref_text: string;
  credential_state_text: string;
  credential_provider_text: string;
  credential_version_text: string;
  credential_material_state_text: string;
  credential_endpoint_text: string;
  credential_secret_fields_text: string;
  deployment_status_text: string;
  deployment_mode_text: string;
  deployment_backend_text: string;
  deployment_boundary_text: string;
  deployment_job_id_text: string;
  deployment_run_id_text: string;
  deployment_remediation_text: string;
  deployment_lifecycle_operation_text: string;
  deployment_lifecycle_status_text: string;
  deployment_lifecycle_observed_at_text: string;
  capability_text: string;
  supported_sampling_text: string;
  supported_products_text: string;
  supported_metric_history_products_text: string;
  supported_product_families_text: string;
  health_status: string;
  health_reason_text: string;
  probe_policy_text: string;
  probe_stale_after_ms_text: string;
  source_readiness_status: string;
  source_readiness_policy_id: string;
  source_readiness_reason_text: string;
  probe_kind_text: string;
  probe_message_text: string;
  probe_metadata_text: string;
  probe_diagnostic_kind_text: string;
  probe_diagnostic_stage_text: string;
  probe_remediation_text: string;
  connection_test_result_text: string;
  connection_test_kind_text: string;
  connection_test_message_text: string;
  watermark_text: string;
  watermark_confidence_text: string;
  detail_link: Link;
  settings_link?: Link;
  actions?: SourceAction[];
};

type DeploymentRun = {
  job_id: string;
  run_id: string;
  data_source_id: string;
  status_text: string;
  mode_text: string;
  backend_text: string;
  physical_boundary_text: string;
  attempt_count_text: string;
  failure_summary: string;
  started_at_text: string;
  completed_at_text: string;
  remediation: string;
  action?: {
    id: string;
    event: "retry_deployment_run" | "requeue_deployment_run";
    payload: { "job-id": string };
    label: string;
    icon: string;
  };
};

type EventList = {
  id: string;
  heading: string;
  subtitle: string;
  empty: string;
  rows: Array<{
    id: string;
    event_type: string;
    title: string;
    subtitle: string;
    occurred_at: string;
    probe_kind?: string;
    probe_message?: string;
    probe_metadata?: string;
    probe_diagnostic_kind?: string;
    probe_diagnostic_stage?: string;
    probe_remediation?: string;
    connection_test_result?: string;
    connection_test_kind?: string;
    connection_test_message?: string;
  }>;
};

type Option = { label: string; value: string };

type RegistrationValues = {
  data_source_id: string;
  logical_source: string;
  kind: string;
  isolation_level: string;
  credentials_ref: string;
  credential_provider: string;
  endpoint_ref: string;
  material_env_profile: string;
  http_endpoint_env: string;
  storage: string;
};

type Registration = {
  id: string;
  heading: string;
  description: string;
  form: {
    id: string;
    values: RegistrationValues;
    options: {
      logical_source: Option[];
      kind: Option[];
      isolation_level: Option[];
      credential_provider: Option[];
      storage: Option[];
    };
    error: string | null;
  };
};

type BindingForm = {
  binding_id: string;
  form_id: string;
  panel_id: string;
  data_source_id: string;
  source_options: Option[];
  error: string | null;
};

type Page = {
  id: string;
  mode: "reader" | "admin";
  focus: Focus;
  header: {
    heading: string;
    mission_id: string;
    register_link: Link | null;
    stats: Array<{ label: string; value: number }>;
    readiness_policy: {
      id: string;
      label: string;
      policy_id: string;
      block_source_health: string;
      block_freshness: string;
      block_connection_test: string;
      connection_summary: string;
    };
  };
  bindings: {
    heading: string;
    description: string;
    empty: string;
    groups: BindingGroup[];
  };
  sources: {
    heading: string;
    subtitle: string;
    empty: string;
    rows: SourceRow[];
  };
  deployment_runs: {
    heading: string;
    subtitle: string;
    empty: string;
    rows: DeploymentRun[];
  };
  activity: {
    binding_events: EventList;
    source_events: EventList;
    health_events: EventList;
  };
  admin?: {
    registration: Registration | null;
    binding_form: BindingForm | null;
  };
};

const props = defineProps<{ page: Page }>();

const emit = defineEmits<{
  "open-register-source": [payload: EmptyPayload];
  "cancel-register-source": [payload: EmptyPayload];
  "register-source": [payload: { source: RegistrationValues }];
  "open-change-binding": [payload: { "binding-id": string }];
  "cancel-change-binding": [payload: EmptyPayload];
  "change-binding": [payload: { binding: { data_source_id: string } }];
  "disable-source": [payload: { "data-source-id": string }];
  "enable-source": [payload: { "data-source-id": string }];
  "reconcile-tsdb-backend": [payload: { "data-source-id": string }];
  "deprovision-tsdb-backend": [payload: { "data-source-id": string }];
  "provision-tsdb-backend": [payload: { "data-source-id": string }];
  "probe-source": [payload: { "data-source-id": string }];
  "rotate-source-credential": [payload: { "data-source-id": string; "credentials-ref": string }];
  "retry-deployment-run": [payload: { "job-id": string }];
  "requeue-deployment-run": [payload: { "job-id": string }];
}>();

const normalizeString = (value: unknown): string => (value == null ? "" : String(value));

const registrationValues = (registration: Registration | null | undefined): RegistrationValues => {
  const values = registration?.form.values;

  return {
    data_source_id: normalizeString(values?.data_source_id),
    logical_source: normalizeString(values?.logical_source),
    kind: normalizeString(values?.kind),
    isolation_level: normalizeString(values?.isolation_level),
    credentials_ref: normalizeString(values?.credentials_ref),
    credential_provider: normalizeString(values?.credential_provider),
    endpoint_ref: normalizeString(values?.endpoint_ref),
    material_env_profile: normalizeString(values?.material_env_profile),
    http_endpoint_env: normalizeString(values?.http_endpoint_env),
    storage: normalizeString(values?.storage),
  };
};

const registerSource = reactive<RegistrationValues>(
  registrationValues(props.page.admin?.registration),
);

const registrationFingerprint = (registration: Registration | null | undefined): string =>
  JSON.stringify([
    registration?.id ?? null,
    registration?.form.values ?? null,
    registration?.form.error ?? null,
  ]);

watch(
  () => registrationFingerprint(props.page.admin?.registration),
  () => Object.assign(registerSource, registrationValues(props.page.admin?.registration)),
);

const binding = reactive({
  data_source_id: normalizeString(props.page.admin?.binding_form?.data_source_id),
});

const bindingFingerprint = (form: BindingForm | null | undefined): string =>
  JSON.stringify([form?.binding_id ?? null, form?.data_source_id ?? null, form?.error ?? null]);

watch(
  () => bindingFingerprint(props.page.admin?.binding_form),
  () => {
    binding.data_source_id = normalizeString(props.page.admin?.binding_form?.data_source_id);
  },
);

const submitRegistration = () =>
  emit("register-source", {
    source: {
      data_source_id: normalizeString(registerSource.data_source_id),
      logical_source: normalizeString(registerSource.logical_source),
      kind: normalizeString(registerSource.kind),
      isolation_level: normalizeString(registerSource.isolation_level),
      credentials_ref: normalizeString(registerSource.credentials_ref),
      credential_provider: normalizeString(registerSource.credential_provider),
      endpoint_ref: normalizeString(registerSource.endpoint_ref),
      material_env_profile: normalizeString(registerSource.material_env_profile),
      http_endpoint_env: normalizeString(registerSource.http_endpoint_env),
      storage: normalizeString(registerSource.storage),
    },
  });

const submitBinding = () =>
  emit("change-binding", {
    binding: { data_source_id: normalizeString(binding.data_source_id) },
  });

const emitSourceAction = (action: SourceAction) => {
  if (action.confirm && !window.confirm(action.confirm)) return;

  const dataSourcePayload = {
    "data-source-id": normalizeString(action.payload["data-source-id"]),
  };

  switch (action.event) {
    case "disable_source":
      emit("disable-source", dataSourcePayload);
      break;
    case "enable_source":
      emit("enable-source", dataSourcePayload);
      break;
    case "reconcile_tsdb_backend":
      emit("reconcile-tsdb-backend", dataSourcePayload);
      break;
    case "deprovision_tsdb_backend":
      emit("deprovision-tsdb-backend", dataSourcePayload);
      break;
    case "provision_tsdb_backend":
      emit("provision-tsdb-backend", dataSourcePayload);
      break;
    case "probe_source":
      emit("probe-source", dataSourcePayload);
      break;
    case "rotate_source_credential":
      emit("rotate-source-credential", {
        ...dataSourcePayload,
        "credentials-ref": normalizeString(action.payload["credentials-ref"]),
      });
      break;
  }
};

const emitDeploymentAction = (run: DeploymentRun) => {
  if (!run.action) return;

  const payload = { "job-id": normalizeString(run.action.payload["job-id"]) };

  if (run.action.event === "retry_deployment_run") emit("retry-deployment-run", payload);
  if (run.action.event === "requeue_deployment_run") emit("requeue-deployment-run", payload);
};

const statusClass = (status: string): string => {
  if (["active", "healthy", "recovered", "ready"].includes(status)) {
    return "bg-success/20 text-success";
  }

  if (["degraded", "disabled", "unknown"].includes(status)) {
    return "bg-warning/20 text-warning";
  }

  if (["unavailable", "superseded", "missing", "blocked"].includes(status)) {
    return "bg-error/20 text-error";
  }

  return "bg-info/20 text-info";
};

const actionClass = (variant: SourceAction["variant"]): string => {
  if (variant === "danger") return "btn btn-error btn-outline btn-xs";
  if (variant === "secondary") return "btn btn-secondary btn-xs";
  return "btn btn-ghost btn-xs";
};

const displayValue = (row: object, key: string): string =>
  normalizeString((row as Record<string, unknown>)[key]);

const bindingDescriptorFields = [
  { label: "dataset", key: "dataset_text" },
  { label: "priority", key: "priority_text" },
  { label: "version", key: "version_text" },
  { label: "active from", key: "active_from_text" },
  { label: "active to", key: "active_to_text" },
];

const bindingSourceFields = [
  { label: "status", key: "source_status_text" },
  { label: "kind", key: "source_kind_text" },
  { label: "owner", key: "source_owner_text" },
  { label: "isolation", key: "source_isolation_text" },
  { label: "adapter", key: "source_adapter_text" },
  { label: "credential", key: "credential_ref_text" },
];

const bindingHealthFields = [
  { label: "observed", key: "health_observed_at_text" },
  { label: "event", key: "health_event_type_text" },
  { label: "current event", key: "current_event_id_text" },
  { label: "readiness", key: "source_readiness_status" },
  { label: "policy", key: "source_readiness_policy_id" },
  { label: "reason", key: "source_readiness_reason_text" },
];

const sourceFields = [
  { label: "status", key: "status_text" },
  { label: "readiness", key: "source_readiness_status" },
  { label: "policy", key: "source_readiness_policy_id" },
  { label: "ready reason", key: "source_readiness_reason_text" },
  { label: "health reason", key: "health_reason_text" },
  { label: "probe kind", key: "probe_kind_text" },
  { label: "probe policy", key: "probe_policy_text" },
  { label: "probe stale", key: "probe_stale_after_ms_text" },
  { label: "probe message", key: "probe_message_text" },
  { label: "probe metadata", key: "probe_metadata_text" },
  { label: "diagnostic", key: "probe_diagnostic_kind_text" },
  { label: "diag stage", key: "probe_diagnostic_stage_text" },
  { label: "remediation", key: "probe_remediation_text" },
  { label: "connection", key: "connection_test_result_text" },
  { label: "conn kind", key: "connection_test_kind_text" },
  { label: "conn detail", key: "connection_test_message_text" },
  { label: "watermark", key: "watermark_text" },
  { label: "confidence", key: "watermark_confidence_text" },
  { label: "adapter", key: "adapter_text" },
  { label: "credential", key: "credential_ref_text" },
  { label: "cred state", key: "credential_state_text" },
  { label: "cred provider", key: "credential_provider_text" },
  { label: "cred material", key: "credential_material_state_text" },
  { label: "cred endpoint", key: "credential_endpoint_text" },
  { label: "cred fields", key: "credential_secret_fields_text" },
  { label: "deploy", key: "deployment_status_text" },
  { label: "deploy mode", key: "deployment_mode_text" },
  { label: "backend", key: "deployment_backend_text" },
  { label: "boundary", key: "deployment_boundary_text" },
  { label: "deploy job", key: "deployment_job_id_text" },
  { label: "deploy run", key: "deployment_run_id_text" },
  { label: "deploy fix", key: "deployment_remediation_text" },
  { label: "backend op", key: "deployment_lifecycle_operation_text" },
  { label: "backend state", key: "deployment_lifecycle_status_text" },
  { label: "backend seen", key: "deployment_lifecycle_observed_at_text" },
  { label: "capability", key: "capability_text" },
  { label: "sampling", key: "supported_sampling_text" },
  { label: "products", key: "supported_products_text" },
  { label: "history", key: "supported_metric_history_products_text" },
  { label: "families", key: "supported_product_families_text" },
];

const deploymentFields = [
  { label: "job", key: "job_id" },
  { label: "mode", key: "mode_text" },
  { label: "backend", key: "backend_text" },
  { label: "boundary", key: "physical_boundary_text" },
  { label: "attempts", key: "attempt_count_text" },
  { label: "started", key: "started_at_text" },
  { label: "completed", key: "completed_at_text" },
  { label: "failure", key: "failure_summary" },
  { label: "fix", key: "remediation" },
];
</script>

<template>
  <div
    :id="page.id"
    class="flex flex-1 min-h-0"
    :data-source-focus-state="page.focus.state"
    :data-source-focus-data-source="page.focus.data_source_id"
    :data-source-focus-binding="page.focus.source_binding_id"
    :data-source-focus-logical-source="page.focus.logical_source"
    :data-source-focus-realm="page.focus.realm"
    :data-source-focus-scope-kind="page.focus.scope_kind"
    :data-source-focus-scope-id="page.focus.scope_id"
    :data-source-focus-contact-id="page.focus.contact_id"
    :data-source-focus-selected-target="page.focus.selected_target"
    :data-source-focus-selected-id="page.focus.selected_id"
    :data-source-focus-transport-id="page.focus.transport_id"
    :data-source-focus-source-endpoint-id="page.focus.source_endpoint_id"
    :data-source-focus-ground-station-id="page.focus.ground_station_id"
    :data-source-focus-link-id="page.focus.link_id"
    :data-source-focus-empty-reason="page.focus.source_empty_reason"
    :data-source-focus-requested-source-products="page.focus.requested_source_products"
    :data-source-focus-requested-product-families="page.focus.requested_product_families"
    :data-source-focus-dashboard="page.focus.source_dashboard_id"
    :data-source-focus-evidence-kind="page.focus.selected_evidence_kind"
    :data-source-focus-evidence-mode="page.focus.selected_source_evidence_mode"
    :data-source-focus-evidence-state="page.focus.selected_source_evidence_state"
  >
    <div class="flex-1 min-w-0 overflow-y-auto">
      <div class="mx-auto max-w-6xl px-6 py-8">
        <div
          class="flex flex-col gap-3 border-b border-base-300/60 pb-5 md:flex-row md:items-end md:justify-between"
        >
          <div>
            <h1 class="text-lg font-semibold text-base-content">{{ page.header.heading }}</h1>
            <p class="mt-1 font-mono text-xs text-base-content/60">
              {{ page.header.mission_id }}
            </p>
          </div>
          <div class="flex flex-col items-stretch gap-3 md:items-end">
            <a
              v-if="page.header.register_link"
              :id="page.header.register_link.id"
              :href="page.header.register_link.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-primary btn-sm"
            >
              <span :class="[page.header.register_link.icon, 'h-4 w-4']"></span>
              {{ page.header.register_link.label }}
            </a>
            <div class="grid grid-cols-3 gap-2 text-right">
              <CadenceStatTile v-for="stat in page.header.stats" :key="stat.label">
                <template #label>{{ stat.label }}</template>
                <p class="mt-1 font-mono text-xl text-base-content">{{ stat.value }}</p>
              </CadenceStatTile>
            </div>
            <div
              :id="page.header.readiness_policy.id"
              class="border border-base-300 bg-base-200 px-3 py-2 text-right"
              :data-source-readiness-policy-id="page.header.readiness_policy.policy_id"
              :data-source-readiness-block-health="page.header.readiness_policy.block_source_health"
              :data-source-readiness-block-freshness="page.header.readiness_policy.block_freshness"
              :data-source-readiness-block-connection-test="
                page.header.readiness_policy.block_connection_test
              "
            >
              <p class="hud-label">{{ page.header.readiness_policy.label }}</p>
              <p class="font-mono text-xs text-base-content">
                {{ page.header.readiness_policy.policy_id }}
              </p>
              <p class="mt-1 font-mono text-[0.65rem] text-base-content/60">
                {{ page.header.readiness_policy.connection_summary }}
              </p>
            </div>
          </div>
        </div>

        <div
          v-if="page.focus.notice"
          :id="page.focus.notice.id"
          :class="[
            'mt-5 flex items-start gap-3 border px-4 py-3 text-sm',
            page.focus.state === 'matched' && 'border-primary/30 bg-primary/5 text-base-content',
            page.focus.state === 'missing' && 'border-warning/30 bg-warning/10 text-base-content',
          ]"
          :data-source-focus-state="page.focus.state"
          :data-source-focus-data-source="page.focus.data_source_id"
          :data-source-focus-binding="page.focus.source_binding_id"
          :data-source-focus-logical-source="page.focus.logical_source"
          :data-source-focus-realm="page.focus.realm"
          :data-source-focus-scope-kind="page.focus.scope_kind"
          :data-source-focus-scope-id="page.focus.scope_id"
          :data-source-focus-contact-id="page.focus.contact_id"
          :data-source-focus-selected-target="page.focus.selected_target"
          :data-source-focus-selected-id="page.focus.selected_id"
          :data-source-focus-transport-id="page.focus.transport_id"
          :data-source-focus-source-endpoint-id="page.focus.source_endpoint_id"
          :data-source-focus-ground-station-id="page.focus.ground_station_id"
          :data-source-focus-link-id="page.focus.link_id"
          :data-source-focus-empty-reason="page.focus.source_empty_reason"
          :data-source-focus-requested-source-products="page.focus.requested_source_products"
          :data-source-focus-requested-product-families="page.focus.requested_product_families"
          :data-source-focus-dashboard="page.focus.source_dashboard_id"
          :data-source-focus-evidence-kind="page.focus.selected_evidence_kind"
          :data-source-focus-evidence-mode="page.focus.selected_source_evidence_mode"
          :data-source-focus-evidence-state="page.focus.selected_source_evidence_state"
        >
          <span :class="[page.focus.notice.icon, 'mt-0.5 h-4 w-4 shrink-0']"></span>
          <div class="min-w-0">
            <p class="font-semibold">{{ page.focus.notice.title }}</p>
            <p class="mt-1 break-all font-mono text-xs text-base-content/60">
              {{ page.focus.notice.detail }}
            </p>

            <div
              v-if="page.focus.remediation"
              :id="page.focus.remediation.id"
              class="mt-3 border-l-2 border-warning/60 pl-3"
              :data-source-remediation-kind="page.focus.remediation.kind"
              :data-source-remediation-target="page.focus.remediation.target"
              :data-source-remediation-target-id="page.focus.remediation.target_id"
            >
              <p class="text-xs font-semibold text-base-content">
                {{ page.focus.remediation.title }}
              </p>
              <p class="mt-1 text-xs text-base-content/70">
                {{ page.focus.remediation.detail }}
              </p>
              <div
                v-if="page.focus.remediation.candidate_rows.length > 0"
                id="source-focus-capability-candidates"
                class="mt-2 space-y-1 text-xs"
              >
                <p class="hud-label">candidate sources</p>
                <div
                  v-for="candidate in page.focus.remediation.candidate_rows"
                  :key="candidate.data_source_id"
                  class="flex flex-wrap items-center gap-x-2 gap-y-1 font-mono"
                  :data-source-capability-candidate="candidate.data_source_id"
                  :data-source-capability-compatible="String(candidate.compatible)"
                  :data-source-capability-missing="candidate.missing_text"
                >
                  <span
                    :class="[
                      'font-semibold',
                      candidate.compatible ? 'text-success' : 'text-warning',
                    ]"
                    >{{ candidate.status_text }}</span
                  >
                  <span class="text-base-content">{{ candidate.data_source_id }}</span>
                  <span class="text-base-content/60">{{ candidate.reason_text }}</span>
                </div>
              </div>
              <dl
                v-if="page.focus.remediation.capability_rows.length > 0"
                id="source-focus-capability-mismatch"
                class="mt-2 grid grid-cols-[6rem_1fr_1fr] gap-x-2 gap-y-1 text-xs"
              >
                <dt class="hud-label">field</dt>
                <dd class="hud-label">requested</dd>
                <dd class="hud-label">supported</dd>
                <template v-for="row in page.focus.remediation.capability_rows" :key="row.key">
                  <dt
                    class="font-mono text-base-content/70"
                    :data-source-capability-mismatch-field="row.key"
                  >
                    {{ row.label }}
                  </dt>
                  <dd
                    class="break-all font-mono text-base-content"
                    :data-source-capability-mismatch-requested="row.key"
                  >
                    {{ row.requested }}
                  </dd>
                  <dd
                    class="break-all font-mono text-base-content/70"
                    :data-source-capability-mismatch-supported="row.key"
                  >
                    {{ row.supported }}
                  </dd>
                </template>
              </dl>
              <div class="mt-2 flex flex-wrap gap-2">
                <button
                  v-if="page.focus.remediation.action?.kind === 'event'"
                  :id="page.focus.remediation.action.id"
                  type="button"
                  class="btn btn-primary btn-xs"
                  @click="emit('open-register-source', {})"
                >
                  <span :class="[page.focus.remediation.action.icon, 'h-3.5 w-3.5']"></span>
                  {{ page.focus.remediation.action.label }}
                </button>
                <a
                  v-else-if="page.focus.remediation.action?.kind === 'anchor'"
                  :id="page.focus.remediation.action.id"
                  :href="page.focus.remediation.action.href"
                  class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
                >
                  <span :class="[page.focus.remediation.action.icon, 'h-3.5 w-3.5']"></span>
                  {{ page.focus.remediation.action.label }}
                </a>
                <a
                  v-if="page.focus.remediation.dashboard_return"
                  :id="page.focus.remediation.dashboard_return.id"
                  :href="page.focus.remediation.dashboard_return.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
                  :data-source-focus-dashboard-return="
                    page.focus.remediation.dashboard_return.dashboard_id
                  "
                  :data-source-focus-dashboard-return-panel="
                    page.focus.remediation.dashboard_return.panel
                  "
                  :data-source-focus-dashboard-return-activity-filter="
                    page.focus.remediation.dashboard_return.activity_filter
                  "
                  :data-source-focus-dashboard-return-activity-event="
                    page.focus.remediation.dashboard_return.activity_event
                  "
                >
                  <span
                    :class="[page.focus.remediation.dashboard_return.icon, 'h-3.5 w-3.5']"
                  ></span>
                  {{ page.focus.remediation.dashboard_return.label }}
                </a>
              </div>
            </div>

            <div
              v-if="page.focus.resource"
              :id="page.focus.resource.id"
              class="mt-3 border-l-2 border-primary/70 pl-3"
              :data-source-resource-selected-target="page.focus.resource.selected_target"
              :data-source-resource-selected-id="page.focus.resource.selected_id"
              :data-source-resource-transport-id="page.focus.resource.transport_id"
              :data-source-resource-source-endpoint-id="page.focus.resource.source_endpoint_id"
              :data-source-resource-ground-station-id="page.focus.resource.ground_station_id"
              :data-source-resource-link-id="page.focus.resource.link_id"
            >
              <p class="text-xs font-semibold text-base-content">
                {{ page.focus.resource.heading }}
              </p>
              <dl class="mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                <template v-for="row in page.focus.resource.rows" :key="row.key">
                  <dt class="hud-label" :data-source-resource-row-label="row.key">
                    {{ row.label }}
                  </dt>
                  <dd
                    class="break-all font-mono text-base-content"
                    :data-source-resource-row="row.key"
                    :data-source-resource-row-value="row.value"
                    :data-source-resource-row-name="row.display_value"
                    :data-source-resource-row-status="row.status"
                  >
                    <a
                      v-if="row.href"
                      :href="row.href"
                      data-phx-link="redirect"
                      data-phx-link-state="push"
                      class="inline-flex items-center gap-1 text-primary hover:underline"
                      :data-source-resource-link="row.key"
                    >
                      {{ row.display_value }}
                      <span class="hero-arrow-top-right-on-square h-3 w-3"></span>
                    </a>
                    <span v-else>{{ row.display_value }}</span>
                    <span
                      class="ml-1 font-sans text-[0.65rem] uppercase tracking-normal text-base-content/50"
                      >{{ row.status_text }}</span
                    >
                  </dd>
                </template>
              </dl>
            </div>

            <div
              v-if="page.focus.evidence"
              :id="page.focus.evidence.id"
              class="mt-3 border-l-2 border-info/70 pl-3"
              :data-source-evidence-kind="page.focus.evidence.kind"
              :data-source-evidence-mode="page.focus.evidence.mode"
              :data-source-evidence-state="page.focus.evidence.state"
              :data-source-evidence-reason="page.focus.evidence.reason"
            >
              <p class="text-xs font-semibold text-base-content">
                {{ page.focus.evidence.title }}
              </p>
              <p class="mt-1 text-xs text-base-content/70">
                {{ page.focus.evidence.detail }}
              </p>
              <a
                v-if="page.focus.evidence.dashboard_return"
                :id="page.focus.evidence.dashboard_return.id"
                :href="page.focus.evidence.dashboard_return.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
                :data-source-focus-dashboard-return="
                  page.focus.evidence.dashboard_return.dashboard_id
                "
                :data-source-focus-dashboard-return-panel="
                  page.focus.evidence.dashboard_return.panel
                "
                :data-source-focus-dashboard-return-activity-filter="
                  page.focus.evidence.dashboard_return.activity_filter
                "
                :data-source-focus-dashboard-return-activity-event="
                  page.focus.evidence.dashboard_return.activity_event
                "
              >
                <span :class="[page.focus.evidence.dashboard_return.icon, 'h-3.5 w-3.5']"></span>
                {{ page.focus.evidence.dashboard_return.label }}
              </a>
            </div>
          </div>
        </div>

        <section
          v-if="page.admin?.registration"
          :id="page.admin.registration.id"
          class="mt-5 border border-primary/20 bg-base-200/60 p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <h2 class="text-sm font-semibold text-base-content">
                {{ page.admin.registration.heading }}
              </h2>
              <p class="mt-1 text-xs text-base-content/60">
                {{ page.admin.registration.description }}
              </p>
            </div>
            <button
              id="cancel-register-source-top"
              type="button"
              class="btn btn-ghost btn-xs"
              aria-label="Cancel source registration"
              @click="emit('cancel-register-source', {})"
            >
              <span class="hero-x-mark h-4 w-4"></span>
            </button>
          </div>

          <form
            :id="page.admin.registration.form.id"
            class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4"
            @submit.prevent="submitRegistration"
          >
            <CadenceField
              control-id="source_data_source_id"
              wrapper-class="fieldset mb-3"
              label="Source ID"
              label-class="hud-label block mb-1.5"
            >
              <input
                id="source_data_source_id"
                v-model="registerSource.data_source_id"
                name="source[data_source_id]"
                type="text"
                placeholder="rehearsal-questdb"
                required
                class="w-full input"
              />
            </CadenceField>
            <CadenceField
              control-id="source_logical_source"
              wrapper-class="fieldset mb-3"
              label="Logical source"
              label-class="hud-label block mb-1.5"
            >
              <select
                id="source_logical_source"
                v-model="registerSource.logical_source"
                name="source[logical_source]"
                required
                class="w-full select"
              >
                <option
                  v-for="option in page.admin.registration.form.options.logical_source"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
            <CadenceField
              control-id="source_kind"
              wrapper-class="fieldset mb-3"
              label="Ownership"
              label-class="hud-label block mb-1.5"
            >
              <select
                id="source_kind"
                v-model="registerSource.kind"
                name="source[kind]"
                required
                class="w-full select"
              >
                <option
                  v-for="option in page.admin.registration.form.options.kind"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
            <CadenceField
              control-id="source_isolation_level"
              wrapper-class="fieldset mb-3"
              label="Isolation"
              label-class="hud-label block mb-1.5"
            >
              <select
                id="source_isolation_level"
                v-model="registerSource.isolation_level"
                name="source[isolation_level]"
                required
                class="w-full select"
              >
                <option
                  v-for="option in page.admin.registration.form.options.isolation_level"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
            <CadenceField
              control-id="source_credentials_ref"
              wrapper-class="fieldset mb-3"
              label="Credential ref"
              label-class="hud-label block mb-1.5"
            >
              <input
                id="source_credentials_ref"
                v-model="registerSource.credentials_ref"
                name="source[credentials_ref]"
                type="text"
                placeholder="cred-rehearsal-questdb"
                class="w-full input"
              />
            </CadenceField>
            <CadenceField
              control-id="source_credential_provider"
              wrapper-class="fieldset mb-3"
              label="Credential provider"
              label-class="hud-label block mb-1.5"
            >
              <select
                id="source_credential_provider"
                v-model="registerSource.credential_provider"
                name="source[credential_provider]"
                class="w-full select"
              >
                <option
                  v-for="option in page.admin.registration.form.options.credential_provider"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
            <CadenceField
              control-id="source_endpoint_ref"
              wrapper-class="fieldset mb-3"
              label="Endpoint ref"
              label-class="hud-label block mb-1.5"
            >
              <input
                id="source_endpoint_ref"
                v-model="registerSource.endpoint_ref"
                name="source[endpoint_ref]"
                type="text"
                placeholder="endpoint://customer/rehearsal"
                class="w-full input"
              />
            </CadenceField>
            <CadenceField
              control-id="source_material_env_profile"
              wrapper-class="fieldset mb-3"
              label="Env material profile"
              label-class="hud-label block mb-1.5"
            >
              <input
                id="source_material_env_profile"
                v-model="registerSource.material_env_profile"
                name="source[material_env_profile]"
                type="text"
                placeholder="customer-rehearsal-questdb"
                class="w-full input"
              />
            </CadenceField>
            <CadenceField
              control-id="source_http_endpoint_env"
              wrapper-class="fieldset mb-3"
              label="HTTP endpoint env"
              label-class="hud-label block mb-1.5"
            >
              <input
                id="source_http_endpoint_env"
                v-model="registerSource.http_endpoint_env"
                name="source[http_endpoint_env]"
                type="text"
                placeholder="CADENCE_CUSTOMER_QUESTDB_HTTP_ENDPOINT"
                class="w-full input"
              />
            </CadenceField>
            <CadenceField
              control-id="source_storage"
              wrapper-class="fieldset mb-3"
              label="Storage"
              label-class="hud-label block mb-1.5"
            >
              <select
                id="source_storage"
                v-model="registerSource.storage"
                name="source[storage]"
                required
                class="w-full select"
              >
                <option
                  v-for="option in page.admin.registration.form.options.storage"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
            <div class="flex items-end gap-2">
              <button id="submit-register-source" type="submit" class="btn btn-primary btn-sm">
                Register
              </button>
              <button
                id="cancel-register-source"
                type="button"
                class="btn btn-ghost btn-sm"
                @click="emit('cancel-register-source', {})"
              >
                Cancel
              </button>
            </div>
          </form>
          <p
            v-if="page.admin.registration.form.error"
            id="register-source-error"
            class="mt-2 text-xs text-error"
          >
            {{ page.admin.registration.form.error }}
          </p>
        </section>

        <div class="mt-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <section class="space-y-4">
            <div class="flex items-center justify-between gap-3">
              <h2 class="hud-label">{{ page.bindings.heading }}</h2>
              <span class="font-mono text-xs text-base-content/50">
                {{ page.bindings.description }}
              </span>
            </div>

            <div
              v-if="page.bindings.groups.length === 0"
              class="border border-dashed border-base-300 p-6"
            >
              <p class="text-sm text-base-content/70">{{ page.bindings.empty }}</p>
            </div>

            <div
              v-for="group in page.bindings.groups"
              :id="`source-binding-group-${group.id}`"
              :key="group.id"
              class="border border-base-300 bg-base-200/50"
              :data-source-binding-group="group.id"
            >
              <div
                class="flex items-center justify-between gap-3 border-b border-base-300 px-3 py-2"
              >
                <div class="min-w-0">
                  <h3 class="text-sm font-semibold text-base-content">
                    {{ group.logical_source_text }}
                    <span class="text-base-content/40">/</span>
                    {{ group.realm_text }}
                  </h3>
                  <p class="font-mono text-xs text-base-content/50">{{ group.count_label }}</p>
                </div>
                <span
                  :class="[
                    'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
                    statusClass(group.group_status),
                  ]"
                  :data-status-pill="group.group_status"
                  >{{ group.group_status }}</span
                >
              </div>

              <div class="divide-y divide-base-300/70">
                <div
                  v-for="row in group.rows"
                  :id="`source-binding-${row.binding_id}`"
                  :key="row.binding_id"
                  :class="[
                    'grid gap-3 px-3 py-3 xl:grid-cols-[minmax(13rem,1fr)_minmax(16rem,1.1fr)_minmax(11rem,.7fr)]',
                    row.focused && 'ring-1 ring-inset ring-primary/40 bg-primary/5',
                  ]"
                  :data-source-focus="String(row.focused)"
                  :data-source-binding-id="row.binding_id"
                  :data-logical-source="row.logical_source_text"
                  :data-source-realm="row.realm_text"
                  :data-data-source-id="row.data_source_id"
                  :data-source-health="row.health_status"
                  :data-source-readiness="row.source_readiness_status"
                  :data-source-readiness-reasons="row.source_readiness_reason_text"
                  :data-source-readiness-policy="row.source_readiness_policy_id"
                >
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <p class="truncate font-mono text-xs font-semibold text-base-content">
                        {{ row.binding_id }}
                      </p>
                      <span
                        :class="[
                          'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
                          statusClass(row.binding_status),
                        ]"
                        :data-status-pill="row.binding_status"
                        >{{ row.binding_status }}</span
                      >
                      <button
                        v-if="row.change_action"
                        :id="row.change_action.id"
                        type="button"
                        class="btn btn-ghost btn-xs"
                        @click="emit('open-change-binding', row.change_action.payload)"
                      >
                        <span :class="[row.change_action.icon, 'h-3.5 w-3.5']"></span>
                        {{ row.change_action.label }}
                      </button>
                    </div>
                    <dl class="mt-2 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <template v-for="field in bindingDescriptorFields" :key="field.key">
                        <dt class="text-base-content/50">{{ field.label }}</dt>
                        <dd class="break-all font-mono text-base-content">
                          {{ displayValue(row, field.key) }}
                        </dd>
                      </template>
                    </dl>
                  </div>

                  <div class="min-w-0">
                    <p class="hud-label">Physical source</p>
                    <p class="mt-1 truncate font-mono text-xs text-base-content">
                      {{ row.data_source_id }}
                    </p>
                    <dl class="mt-2 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <template v-for="field in bindingSourceFields" :key="field.key">
                        <dt class="text-base-content/50">{{ field.label }}</dt>
                        <dd class="break-all font-mono text-base-content">
                          {{ displayValue(row, field.key) }}
                        </dd>
                      </template>
                    </dl>
                  </div>

                  <div class="min-w-0">
                    <p class="hud-label">Health</p>
                    <div class="mt-1 flex items-center gap-2">
                      <span
                        :class="[
                          'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
                          statusClass(row.health_status),
                        ]"
                        :data-status-pill="row.health_status"
                        >{{ row.health_status }}</span
                      >
                      <span class="font-mono text-xs text-base-content/60">
                        {{ row.health_reason_text }}
                      </span>
                    </div>
                    <dl class="mt-2 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <template v-for="field in bindingHealthFields" :key="field.key">
                        <dt class="text-base-content/50">{{ field.label }}</dt>
                        <dd class="break-all font-mono text-base-content">
                          {{ displayValue(row, field.key) }}
                        </dd>
                      </template>
                    </dl>
                  </div>

                  <div
                    v-if="page.admin?.binding_form?.binding_id === row.binding_id"
                    :id="page.admin.binding_form.panel_id"
                    class="border-t border-primary/20 bg-base-100/80 px-3 py-3 xl:col-span-3"
                  >
                    <form
                      :id="page.admin.binding_form.form_id"
                      class="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto]"
                      @submit.prevent="submitBinding"
                    >
                      <div>
                        <CadenceField
                          control-id="binding_data_source_id"
                          wrapper-class="fieldset mb-3"
                          label="Data source"
                          label-class="hud-label block mb-1.5"
                        >
                          <select
                            id="binding_data_source_id"
                            v-model="binding.data_source_id"
                            name="binding[data_source_id]"
                            required
                            class="w-full select"
                          >
                            <option
                              v-for="option in page.admin.binding_form.source_options"
                              :key="option.value"
                              :value="option.value"
                            >
                              {{ option.label }}
                            </option>
                          </select>
                        </CadenceField>
                        <p
                          v-if="page.admin.binding_form.error"
                          :id="`change-binding-error-${row.binding_id}`"
                          class="mt-2 text-xs text-error"
                        >
                          {{ page.admin.binding_form.error }}
                        </p>
                      </div>
                      <div class="flex items-end gap-2">
                        <button
                          :id="`submit-change-binding-${row.binding_id}`"
                          type="submit"
                          class="btn btn-primary btn-sm"
                        >
                          Apply
                        </button>
                        <button
                          :id="`cancel-change-binding-${row.binding_id}`"
                          type="button"
                          class="btn btn-ghost btn-sm"
                          @click="emit('cancel-change-binding', {})"
                        >
                          Cancel
                        </button>
                      </div>
                    </form>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <aside class="space-y-4">
            <CadencePanel
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >
              <template #header>
                <div>
                  <h2 class="text-base font-semibold text-base-content">
                    {{ page.sources.heading }}
                  </h2>
                  <p class="mt-1 text-xs text-base-content/70">{{ page.sources.subtitle }}</p>
                </div>
              </template>
              <div class="card-body p-0">
                <div
                  v-if="page.sources.rows.length === 0"
                  class="px-4 py-5 text-sm text-base-content/70"
                >
                  {{ page.sources.empty }}
                </div>
                <div class="divide-y divide-base-300/70">
                  <div
                    v-for="source in page.sources.rows"
                    :id="`data-source-${source.data_source_id}`"
                    :key="source.data_source_id"
                    :class="[
                      'px-4 py-3',
                      source.focused && 'ring-1 ring-inset ring-primary/40 bg-primary/5',
                    ]"
                    :data-source-focus="String(source.focused)"
                    :data-data-source-row="source.data_source_id"
                    :data-source-status="source.status_text"
                    :data-source-health="source.health_status"
                    :data-source-readiness="source.source_readiness_status"
                    :data-source-readiness-reasons="source.source_readiness_reason_text"
                    :data-source-readiness-policy="source.source_readiness_policy_id"
                    :data-source-probe-kind="source.probe_kind_text"
                    :data-source-probe-policy="source.probe_policy_text"
                    :data-source-probe-stale-after-ms="source.probe_stale_after_ms_text"
                    :data-source-probe-message="source.probe_message_text"
                    :data-source-probe-metadata="source.probe_metadata_text"
                    :data-source-probe-diagnostic-kind="source.probe_diagnostic_kind_text"
                    :data-source-probe-diagnostic-stage="source.probe_diagnostic_stage_text"
                    :data-source-probe-remediation="source.probe_remediation_text"
                    :data-source-connection-test-result="source.connection_test_result_text"
                    :data-source-connection-test-kind="source.connection_test_kind_text"
                    :data-source-connection-test-message="source.connection_test_message_text"
                    :data-source-credential-state="source.credential_state_text"
                    :data-source-credential-provider="source.credential_provider_text"
                    :data-source-credential-version="source.credential_version_text"
                    :data-source-credential-material-state="source.credential_material_state_text"
                    :data-source-credential-endpoint="source.credential_endpoint_text"
                    :data-source-credential-secret-fields="source.credential_secret_fields_text"
                    :data-source-deployment-status="source.deployment_status_text"
                    :data-source-deployment-mode="source.deployment_mode_text"
                    :data-source-deployment-backend="source.deployment_backend_text"
                    :data-source-deployment-boundary="source.deployment_boundary_text"
                    :data-source-deployment-job-id="source.deployment_job_id_text"
                    :data-source-deployment-run-id="source.deployment_run_id_text"
                    :data-source-deployment-remediation="source.deployment_remediation_text"
                    :data-source-deployment-lifecycle-operation="
                      source.deployment_lifecycle_operation_text
                    "
                    :data-source-deployment-lifecycle-status="
                      source.deployment_lifecycle_status_text
                    "
                    :data-source-deployment-lifecycle-observed-at="
                      source.deployment_lifecycle_observed_at_text
                    "
                    :data-source-supported-sampling="source.supported_sampling_text"
                    :data-source-supported-products="source.supported_products_text"
                    :data-source-supported-metric-history-products="
                      source.supported_metric_history_products_text
                    "
                    :data-source-supported-product-families="source.supported_product_families_text"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div class="min-w-0">
                        <a
                          :href="source.detail_link.href"
                          data-phx-link="redirect"
                          data-phx-link-state="push"
                          class="truncate font-mono text-xs font-semibold text-primary hover:underline"
                          >{{ source.detail_link.label }}</a
                        >
                        <p class="mt-1 text-xs text-base-content/60">
                          {{ source.kind_text }} · {{ source.owner_text }} ·
                          {{ source.isolation_text }}
                        </p>
                      </div>
                      <div class="flex shrink-0 flex-col items-end gap-2">
                        <div class="flex flex-wrap justify-end gap-1">
                          <span
                            :class="[
                              'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
                              statusClass(source.status_text),
                            ]"
                            :data-status-pill="source.status_text"
                            >{{ source.status_text }}</span
                          >
                          <span
                            :class="[
                              'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
                              statusClass(source.health_status),
                            ]"
                            :data-status-pill="source.health_status"
                            >{{ source.health_status }}</span
                          >
                        </div>
                        <a
                          v-if="source.settings_link"
                          :id="source.settings_link.id"
                          :href="source.settings_link.href"
                          data-phx-link="redirect"
                          data-phx-link-state="push"
                          class="btn btn-ghost btn-xs"
                        >
                          <span :class="[source.settings_link.icon, 'h-3.5 w-3.5']"></span>
                          {{ source.settings_link.label }}
                        </a>
                        <button
                          v-for="action in source.actions ?? []"
                          :id="action.id"
                          :key="action.id"
                          type="button"
                          :class="actionClass(action.variant)"
                          :data-confirm="action.confirm"
                          @click="emitSourceAction(action)"
                        >
                          <span :class="[action.icon, 'h-3.5 w-3.5']"></span>
                          {{ action.label }}
                        </button>
                      </div>
                    </div>
                    <dl class="mt-3 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <template v-for="field in sourceFields" :key="field.key">
                        <dt class="text-base-content/50">{{ field.label }}</dt>
                        <dd class="break-all font-mono text-base-content">
                          {{ displayValue(source, field.key) }}
                        </dd>
                      </template>
                    </dl>
                  </div>
                </div>
              </div>
            </CadencePanel>

            <CadencePanel
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >
              <template #header>
                <div>
                  <h2 class="text-base font-semibold text-base-content">
                    {{ page.deployment_runs.heading }}
                  </h2>
                  <p class="mt-1 text-xs text-base-content/70">
                    {{ page.deployment_runs.subtitle }}
                  </p>
                </div>
              </template>
              <div class="card-body p-0">
                <div
                  v-if="page.deployment_runs.rows.length === 0"
                  class="px-4 py-5 text-sm text-base-content/70"
                >
                  {{ page.deployment_runs.empty }}
                </div>
                <div class="divide-y divide-base-300/70">
                  <div
                    v-for="run in page.deployment_runs.rows"
                    :id="`deployment-run-${run.run_id}`"
                    :key="run.run_id"
                    class="px-4 py-3"
                    :data-deployment-run-row="run.run_id"
                    :data-deployment-run-job-id="run.job_id"
                    :data-deployment-run-data-source-id="run.data_source_id"
                    :data-deployment-run-status="run.status_text"
                    :data-deployment-run-mode="run.mode_text"
                    :data-deployment-run-backend="run.backend_text"
                    :data-deployment-run-boundary="run.physical_boundary_text"
                    :data-deployment-run-attempt-count="run.attempt_count_text"
                    :data-deployment-run-failure-summary="run.failure_summary"
                    :data-deployment-run-remediation="run.remediation"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div class="min-w-0">
                        <p class="truncate font-mono text-xs font-semibold text-base-content">
                          {{ run.data_source_id }}
                        </p>
                        <p class="mt-1 truncate font-mono text-xs text-base-content/60">
                          {{ run.run_id }}
                        </p>
                      </div>
                      <div class="flex shrink-0 flex-col items-end gap-2">
                        <span
                          :class="[
                            'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
                            statusClass(run.status_text),
                          ]"
                          :data-status-pill="run.status_text"
                          >{{ run.status_text }}</span
                        >
                        <button
                          v-if="run.action"
                          :id="run.action.id"
                          type="button"
                          class="btn btn-secondary btn-xs"
                          @click="emitDeploymentAction(run)"
                        >
                          <span :class="[run.action.icon, 'h-3.5 w-3.5']"></span>
                          {{ run.action.label }}
                        </button>
                      </div>
                    </div>
                    <dl class="mt-3 grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
                      <template v-for="field in deploymentFields" :key="field.key">
                        <dt class="text-base-content/50">{{ field.label }}</dt>
                        <dd class="break-all font-mono text-base-content">
                          {{ displayValue(run, field.key) }}
                        </dd>
                      </template>
                    </dl>
                  </div>
                </div>
              </div>
            </CadencePanel>

            <CadencePanel
              v-for="list in [
                page.activity.binding_events,
                page.activity.source_events,
                page.activity.health_events,
              ]"
              :key="list.id"
              class="card bg-base-200 border border-base-300"
              header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
            >
              <template #header>
                <div>
                  <h2 class="text-base font-semibold text-base-content">{{ list.heading }}</h2>
                  <p class="mt-1 text-xs text-base-content/70">{{ list.subtitle }}</p>
                </div>
              </template>
              <div class="card-body p-0">
                <div :id="list.id" class="divide-y divide-base-300/70">
                  <div v-if="list.rows.length === 0" class="px-4 py-5 text-sm text-base-content/70">
                    {{ list.empty }}
                  </div>
                  <div
                    v-for="row in list.rows"
                    :id="row.id"
                    :key="row.id"
                    class="px-4 py-3"
                    :data-event-type="row.event_type"
                    :data-event-probe-kind="row.probe_kind ?? ''"
                    :data-event-probe-message="row.probe_message ?? ''"
                    :data-event-probe-metadata="row.probe_metadata ?? ''"
                    :data-event-probe-diagnostic-kind="row.probe_diagnostic_kind ?? ''"
                    :data-event-probe-diagnostic-stage="row.probe_diagnostic_stage ?? ''"
                    :data-event-probe-remediation="row.probe_remediation ?? ''"
                    :data-event-connection-test-result="row.connection_test_result ?? ''"
                    :data-event-connection-test-kind="row.connection_test_kind ?? ''"
                    :data-event-connection-test-message="row.connection_test_message ?? ''"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div class="min-w-0">
                        <p class="text-xs font-semibold text-base-content">{{ row.title }}</p>
                        <p class="mt-1 truncate font-mono text-xs text-base-content/60">
                          {{ row.subtitle }}
                        </p>
                      </div>
                      <span class="shrink-0 font-mono text-[0.65rem] text-base-content/50">
                        {{ row.occurred_at }}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </CadencePanel>
          </aside>
        </div>
      </div>
    </div>
  </div>
</template>
