import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  type FederatedSurfaceDefinition,
} from "@cadence/plugin-sdk";
import CommsApplication from "./CommsApplication.vue";

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
    description: "Review the saved communications setup for a mission.",
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
      renderer: { kind: "federated-vue", exposedModule: "./LegacyApplication" },
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
    canonicalSurface("transports", "Transports", "collection", "cadence.comms.transports", 30),
    canonicalSurface("transport", "Transport", "subject_detail", "cadence.comms.transport", 40),
    canonicalSurface("routing", "Routing", "collection", "cadence.comms.routing", 50),
    canonicalSurface(
      "routing_detail",
      "Routing Rule",
      "subject_detail",
      "cadence.comms.routing_detail",
      60,
    ),
    canonicalSurface(
      "ground_stations",
      "Ground Stations",
      "collection",
      "cadence.comms.ground_stations",
      70,
    ),
    canonicalSurface(
      "ground_station",
      "Ground Station",
      "subject_detail",
      "cadence.comms.ground_station",
      80,
    ),
    canonicalSurface("provider_list", "Providers", "collection", "cadence.comms.provider_list", 90),
    canonicalSurface(
      "provider_new",
      "New Provider",
      "configuration",
      "cadence.comms.provider_new",
      100,
      ["create_provider"],
    ),
    canonicalSurface(
      "provider_show",
      "Provider",
      "subject_detail",
      "cadence.comms.provider_show",
      110,
      ["validate_provider", "sync_provider", "archive_provider"],
    ),
    canonicalSurface(
      "transport_new",
      "New Transport",
      "configuration",
      "cadence.comms.transport_new",
      120,
      ["validate", "save"],
    ),
    canonicalSurface(
      "routing_new",
      "New Routing Rule",
      "configuration",
      "cadence.comms.routing_new",
      130,
      ["validate", "save"],
    ),
    canonicalSurface(
      "ground_station_new",
      "New Ground Station",
      "configuration",
      "cadence.comms.ground_station_new",
      140,
      ["validate", "save"],
    ),
    canonicalSurface(
      "ground_station_edit",
      "Edit Ground Station",
      "configuration",
      "cadence.comms.ground_station_edit",
      150,
      ["validate", "save"],
    ),
  ],
});

export const manifest = canonicalManifest;
export default CommsApplication;

function canonicalSurface(
  surfaceId: string,
  label: string,
  purpose: FederatedSurfaceDefinition["purpose"],
  queryId: string,
  order: number,
  actions: string[] = [],
): FederatedSurfaceDefinition {
  return {
    surfaceId,
    version: 1,
    purpose,
    scope: "mission",
    placement: "application_workspace",
    navigation: { label, order },
    dataContract: { id: queryId, version: 1 },
    actions,
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  };
}
