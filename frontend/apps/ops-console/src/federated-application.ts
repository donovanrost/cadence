import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  type FederatedSurfaceDefinition,
} from "@cadence/plugin-sdk";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

const renderer = { kind: "federated-vue", exposedModule: "./Application" } as const;

const routeSurfaces = [
  ["commands", "operations", "Commands", "cadence.ops.commands", []],
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
] as const;

export const routeQueryContracts = {
  data_source_registration: { subjectParam: null, queryParams: [] },
  data_source_settings: { subjectParam: "data_source_id", queryParams: ["data_source_id"] },
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
