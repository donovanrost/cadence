import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  type FederatedSurfaceDefinition,
} from "@cadence/plugin-sdk";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

const renderer = { kind: "federated-vue", exposedModule: "./Application" } as const;

const routeSurfaces = [
  ["contact_requirement_list", "collection", "Contact Requirements", "cadence.ops.contact_requirement_list", []],
  ["contact_requirement_new", "configuration", "New Contact Requirement", "cadence.ops.contact_requirement_new", ["validate", "save"]],
  ["contact_requirement_show", "subject_detail", "Contact Requirement", "cadence.ops.contact_requirement_show", ["plan", "toggle-opportunity", "create-plan"]],
  ["contact_requirement_template", "configuration", "Requirement Templates", "cadence.ops.contact_requirement_template", ["validate-template", "create-template", "pause-template", "activate-template", "close-template"]],
  ["contact_schedule", "operations", "Contact Schedule", "cadence.ops.contact_schedule", ["validate", "search", "reserve", "cancel"]],
  ["contact_plan_show", "subject_detail", "Contact Plan", "cadence.ops.contact_plan_show", ["submit-plan", "approve-plan", "reject-plan", "execute-plan"]],
  ["contact_detail", "subject_detail", "Contact Detail", "cadence.ops.contact_detail", ["approve-provider-change", "reject-provider-change", "acknowledge-provider-change"]],
  ["contact_record", "subject_detail", "Contact Record", "cadence.ops.contact_record", []],
  ["dashboard_directory", "collection", "Dashboards", "cadence.ops.dashboard_directory", ["filter_dashboards", "toggle_dashboard_star", "restore_dashboard"]],
  ["dashboard_new", "configuration", "New Dashboard", "cadence.ops.dashboard_new", ["validate", "save"]],
  ["dashboard_library", "collection", "Dashboard Library", "cadence.ops.dashboard_library", ["stage-library-item", "create-library-item", "add-library-version"]],
  ["dashboard_playlists", "collection", "Dashboard Playlists", "cadence.ops.dashboard_playlists", ["create-playlist"]],
  ["dashboard_playlist_present", "operations", "Present Playlist", "cadence.ops.dashboard_playlist_present", ["next-dashboard"]],
  ["dashboard_settings", "configuration", "Dashboard Settings", "cadence.ops.dashboard_settings", ["validate-settings", "save-settings", "create-share", "revoke-share", "create-snapshot", "archive-dashboard"]],
  ["dashboard_share", "subject_detail", "Dashboard Share", "cadence.ops.dashboard_share", []],
  ["dashboard_snapshot", "subject_detail", "Dashboard Snapshot", "cadence.ops.dashboard_snapshot", []],
  ["dashboard_diagnostics", "activity", "Dashboard Diagnostics", "cadence.ops.dashboard_diagnostics", []],
  ["fleet_planning", "operations", "Fleet Planning", "cadence.ops.fleet_planning", ["refresh-planning"]],
  ["fleet_planning_new", "configuration", "New Fleet Run", "cadence.ops.fleet_planning_new", ["validate-fleet-run", "create-fleet-run"]],
  ["fleet_planning_policy", "configuration", "Fleet Planning Policy", "cadence.ops.fleet_planning_policy", ["validate-policy", "save-policy", "approve-policy", "validate-grant", "issue-grant", "revoke-grant"]],
  ["fleet_planning_run", "subject_detail", "Fleet Planning Run", "cadence.ops.fleet_planning_run", ["refresh-fleet-run", "repair-fleet-run"]],
  ["activation_requests", "operations", "Activation Requests", "cadence.ops.activation_requests", ["review", "decide"]],
  ["commands", "operations", "Commands", "cadence.ops.commands", ["filter", "reset_filters", "follow_command", "clear_command_focus"]],
  ["telemetry_explore", "operations", "Telemetry Explore", "cadence.ops.telemetry_explore", ["apply_filters", "apply_question", "add_to_dashboard", "clear_selected_sample"]],
  ["data_operations", "operations", "Data Operations", "cadence.ops.data_operations", ["validate-request", "record-historical-workflow-request", "transition-group", "retry-group", "request-correction"]],
  ["data_sources", "configuration", "Data Sources", "cadence.ops.data_sources", ["open-register-source", "cancel-register-source", "register-source", "open-change-binding", "cancel-change-binding", "change-binding", "disable-source", "enable-source", "reconcile-tsdb-backend", "deprovision-tsdb-backend", "provision-tsdb-backend", "probe-source", "rotate-source-credential", "retry-deployment-run", "requeue-deployment-run"]],
  ["alarms", "operations", "Alarms", "cadence.ops.alarms", ["filter", "reset_filters"]],
  ["timeline", "activity", "Timeline", "cadence.ops.timeline", ["apply_timeline_filters", "clear_timeline_selection"]],
] as const;

const makeSurface = (
  surfaceId: string,
  purpose: FederatedSurfaceDefinition["purpose"],
  label: string,
  queryId: string,
  actions: readonly string[],
): FederatedSurfaceDefinition => ({
  surfaceId,
  version: 1,
  purpose,
  scope: "mission",
  placement: "ops_workspace",
  navigation: { label, order: 10 },
  dataContract: { id: queryId, version: 1 },
  actions,
  renderer,
});

export const surfaceContracts = [
  {
    surfaceId: "workspace",
    version: 1,
    purpose: "overview",
    scope: "mission",
    placement: "application_workspace",
    navigation: { label: "Ops Console", order: 10 },
    dataContract: { id: "cadence.ops.workspace", version: 1 },
    actions: [],
    renderer,
  },
  {
    surfaceId: "ops",
    version: 1,
    purpose: "operations",
    scope: "mission",
    placement: "ops_workspace",
    navigation: { label: "Operations", order: 10 },
    dataContract: { id: "cadence.ops.console", version: 1 },
    actions: ["validate", "save", "filter", "refresh", "select", "open_data_link", "open_evidence", "set_chart_time_range"],
    renderer,
  },
  ...routeSurfaces.map(([surfaceId, purpose, label, queryId, actions]) => makeSurface(surfaceId, purpose, label, queryId, actions)),
] as const;

export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: { packageId: "cadence.ops_console", version: 1, trust: "first_party" },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "ops_console",
    version: 1,
    displayName: "Ops Console",
    description: "Mission operations, dashboard runtime, evidence, and control surfaces.",
    installableScopes: ["mission"],
  },
  surfaces: surfaceContracts,
});

export default OpsConsoleApplication;
