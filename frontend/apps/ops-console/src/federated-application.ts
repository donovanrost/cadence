import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import OpsConsoleApplication from "./OpsConsoleApplication.vue";

export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.ops_console",
    version: 1,
    trust: "first_party",
  },
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
  surfaces: [
    {
      surfaceId: "ops",
      version: 1,
      purpose: "operations",
      scope: "mission",
      placement: "ops_workspace",
      navigation: { label: "Ops Console", order: 10 },
      dataContract: { id: "cadence.ops.console", version: 1 },
      actions: [
        "validate",
        "save",
        "filter",
        "refresh",
        "select",
        "open_data_link",
        "open_evidence",
        "set_chart_time_range",
      ],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
});

export default OpsConsoleApplication;
