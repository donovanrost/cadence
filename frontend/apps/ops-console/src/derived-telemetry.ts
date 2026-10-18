import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import DerivedTelemetryApplication from "./DerivedTelemetryApplication.vue";
export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: { packageId: "cadence.telemetry-applications", version: 1, trust: "first_party" },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "derived_telemetry",
    version: 1,
    displayName: "Derived Telemetry",
    description: "Define and observe calculated telemetry points from canonical mission data.",
    installableScopes: ["mission"],
  },
  surfaces: [
    {
      surfaceId: "manage",
      version: 1,
      purpose: "configuration",
      scope: "mission",
      placement: "application_workspace",
      navigation: { label: "Manage", order: 10 },
      dataContract: { id: "cadence.derived_telemetry.manage", version: 1 },
      actions: ["save_definition"],
      renderer: { kind: "federated-vue", exposedModule: "./DerivedTelemetry" },
    },
  ],
});
export default DerivedTelemetryApplication;
