import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  type FederatedSurfaceDefinition,
} from "@cadence/plugin-sdk";
import CommsOverviewApplication from "./CommsOverviewApplication.vue";

export const legacyManifest = defineApplicationManifest({
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

export const canonicalManifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.comms",
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
    applicationKey: "comms",
    version: 1,
    displayName: "Communications",
    description: "Inspect mission-scoped communications setup and validation.",
    installableScopes: ["mission"],
  },
  surfaces: [
    canonicalSurface("overview", "Overview", "overview", "cadence.comms.overview", 10),
    canonicalSurface("validation", "Validation", "activity", "cadence.comms.validation", 20),
    canonicalSurface("transports", "Transports", "configuration", "cadence.comms.transports", 30),
    canonicalSurface("transport", "Transport", "configuration", "cadence.comms.transport", 40),
    canonicalSurface("routing", "Routing", "configuration", "cadence.comms.routing", 50),
    canonicalSurface(
      "routing_detail",
      "Routing Rule",
      "configuration",
      "cadence.comms.routing_detail",
      60,
    ),
    canonicalSurface(
      "ground_stations",
      "Ground Stations",
      "configuration",
      "cadence.comms.ground_stations",
      70,
    ),
    canonicalSurface(
      "ground_station",
      "Ground Station",
      "configuration",
      "cadence.comms.ground_station",
      80,
    ),
  ],
});

export const manifest = legacyManifest;
export { CommsOverviewApplication as legacyApplication };
export default CommsOverviewApplication;

function canonicalSurface(
  surfaceId: string,
  label: string,
  purpose: FederatedSurfaceDefinition["purpose"],
  queryId: string,
  order: number,
): FederatedSurfaceDefinition {
  return {
    surfaceId,
    version: 1,
    purpose,
    scope: "mission",
    placement: "application_workspace",
    navigation: { label, order },
    dataContract: { id: queryId, version: 1 },
    actions: [],
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  };
}
