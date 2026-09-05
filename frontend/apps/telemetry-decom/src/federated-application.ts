import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import TelemetryDecomApplication from "./TelemetryDecomApplication.vue";

export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.telemetry-applications",
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
    applicationKey: "telemetry_decom",
    version: 1,
    displayName: "Telemetry Decom",
    description: "Choose the packet inputs decoded for an installed spacecraft.",
    installableScopes: ["spacecraft"],
  },
  surfaces: [
    {
      surfaceId: "manage",
      version: 1,
      purpose: "configuration",
      scope: "spacecraft",
      placement: "application_workspace",
      navigation: { label: "Manage", order: 10 },
      dataContract: { id: "cadence.telemetry_decom.manage", version: 1 },
      actions: ["save_configuration", "request_activation", "disable"],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
    {
      surfaceId: "packet_bindings",
      version: 1,
      purpose: "configuration",
      scope: "spacecraft",
      placement: "application_workspace",
      navigation: { label: "Packet bindings", order: 20 },
      dataContract: { id: "cadence.packet_bindings.manage", version: 1 },
      actions: ["save_packet_bindings"],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
});

export default TelemetryDecomApplication;
