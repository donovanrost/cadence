import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import CommsOverviewApplication from "./CommsOverviewApplication.vue";

export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.comms_overview",
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
    applicationKey: "comms_overview",
    version: 1,
    displayName: "Communications Overview",
    description: "Review mission communications transport readiness and setup findings.",
    installableScopes: ["mission"],
  },
  surfaces: [
    {
      surfaceId: "overview",
      version: 1,
      purpose: "overview",
      scope: "mission",
      placement: "application_workspace",
      navigation: { label: "Overview", order: 10 },
      dataContract: { id: "cadence.comms.overview", version: 1 },
      actions: [],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
});

export default CommsOverviewApplication;
