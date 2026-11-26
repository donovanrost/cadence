import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  type FederatedSurfaceDefinition,
} from "@cadence/plugin-sdk";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

const renderer = { kind: "federated-vue", exposedModule: "./Application" } as const;

const routeSurfaces = [
  [
    "contact_schedule",
    "operations",
    "Contact Schedule",
    "cadence.ops.contact_schedule",
    ["validate", "search", "reserve", "cancel"],
  ],
  [
    "contact_plan_show",
    "subject_detail",
    "Contact Plan",
    "cadence.ops.contact_plan_show",
    ["submit-plan", "approve-plan", "reject-plan", "execute-plan"],
  ],
  [
    "contact_detail",
    "subject_detail",
    "Contact Detail",
    "cadence.ops.contact_detail",
    ["approve-provider-change", "reject-provider-change", "acknowledge-provider-change"],
  ],
  ["contact_record", "subject_detail", "Contact Record", "cadence.ops.contact_record", []],
  [
    "fleet_planning",
    "operations",
    "Fleet Planning",
    "cadence.ops.fleet_planning",
    ["refresh-planning"],
  ],
  [
    "fleet_planning_new",
    "configuration",
    "New Fleet Run",
    "cadence.ops.fleet_planning_new",
    ["validate-fleet-run", "create-fleet-run"],
  ],
  [
    "fleet_planning_run",
    "subject_detail",
    "Fleet Planning Run",
    "cadence.ops.fleet_planning_run",
    ["refresh-fleet-run", "repair-fleet-run"],
  ],
  ["commands", "operations", "Commands", "cadence.ops.commands", []],
  [
    "telemetry_explore",
    "operations",
    "Telemetry Explore",
    "cadence.ops.telemetry_explore",
    ["apply_filters", "apply_question"],
  ],
  ["data_operations", "operations", "Data Operations", "cadence.ops.data_operations", []],
  [
    "data_operations_manage",
    "operations",
    "Manage Data Operations",
    "cadence.ops.data_operations_manage",
    [],
  ],
  [
    "data_sources",
    "configuration",
    "Data Sources",
    "cadence.ops.data_sources",
    [
      "register-source",
      "change-binding",
      "disable-source",
      "enable-source",
      "reconcile-tsdb-backend",
      "deprovision-tsdb-backend",
      "provision-tsdb-backend",
      "probe-source",
      "rotate-source-credential",
      "retry-deployment-run",
      "requeue-deployment-run",
    ],
  ],
  [
    "data_source_registration",
    "configuration",
    "Register Data Source",
    "cadence.ops.data_source_registration",
    ["register-source"],
  ],
  [
    "data_source_settings",
    "configuration",
    "Data Source Settings",
    "cadence.ops.data_source_settings",
    [
      "change-binding",
      "disable-source",
      "enable-source",
      "reconcile-tsdb-backend",
      "deprovision-tsdb-backend",
      "provision-tsdb-backend",
      "probe-source",
      "rotate-source-credential",
      "retry-deployment-run",
      "requeue-deployment-run",
    ],
  ],
  ["alarms", "operations", "Alarms", "cadence.ops.alarms", ["filter", "reset_filters"]],
  [
    "timeline",
    "activity",
    "Timeline",
    "cadence.ops.timeline",
    ["apply_timeline_filters", "clear_timeline_selection"],
  ],
] as const;

export const routeQueryContracts = {
  data_source_registration: { subjectParam: null, queryParams: [] },
  data_source_settings: { subjectParam: "data_source_id", queryParams: ["data_source_id"] },
  data_operations_manage: { subjectParam: null, queryParams: ["group"] },
} as const;

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
  ...routeSurfaces.map(([surfaceId, purpose, label, queryId, actions]) =>
    makeSurface(surfaceId, purpose, label, queryId, actions),
  ),
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
