import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import LimitsApplication from "./LimitsApplication.vue";
export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: { packageId: "cadence.mission-assurance", version: 1, trust: "first_party" },
  compatibility: {
    cadenceApplicationContract: 1,
    cadenceSurfaceContract: 1,
    cadenceFederatedRendererContract: 1,
    cadenceThemeContract: 1,
  },
  application: {
    applicationKey: "limits",
    version: 1,
    displayName: "Limits & Alarming",
    description: "Govern telemetry thresholds and inspect the mission's current limit posture.",
    installableScopes: ["mission"],
  },
  surfaces: [
    {
      surfaceId: "manage",
      version: 1,
      purpose: "configuration",
      scope: "mission",
      placement: "application_workspace",
      navigation: { label: "Definitions", order: 10 },
      dataContract: { id: "cadence.limits.manage", version: 1 },
      actions: ["save_limit_definition"],
      renderer: { kind: "federated-vue", exposedModule: "./Limits" },
    },
    {
      surfaceId: "activity",
      version: 1,
      purpose: "activity",
      scope: "mission",
      placement: "application_workspace",
      navigation: { label: "Current posture", order: 20 },
      dataContract: { id: "cadence.limits.activity", version: 1 },
      actions: [],
      renderer: { kind: "federated-vue", exposedModule: "./Limits" },
    },
  ],
});
export default LimitsApplication;
