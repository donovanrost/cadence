import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import SpacecraftApplication from "./SpacecraftApplication.vue";

export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.spacecraft",
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
    applicationKey: "spacecraft",
    version: 1,
    displayName: "Spacecraft",
    description: "Manage spacecraft identities, profiles, readiness, and operations.",
    installableScopes: ["mission", "spacecraft"],
  },
  surfaces: [
    surface("list", "overview", "mission", "Spacecraft", "cadence.spacecraft.list", []),
    surface("new", "configuration", "mission", "New spacecraft", "cadence.spacecraft.new", [
      "validate",
      "save",
    ]),
    surface("profile_list", "overview", "mission", "Profiles", "cadence.spacecraft.profiles", []),
    surface(
      "profile_new",
      "configuration",
      "mission",
      "New profile",
      "cadence.spacecraft.profile.new",
      ["validate", "save"],
    ),
    surface(
      "profile_show",
      "overview",
      "mission",
      "Profile",
      "cadence.spacecraft.profile.show",
      [],
    ),
    surface("show", "overview", "spacecraft", "Overview", "cadence.spacecraft.show", []),
    surface("edit", "configuration", "spacecraft", "Identity", "cadence.spacecraft.edit", [
      "validate",
      "save",
    ]),
    surface("readiness", "overview", "spacecraft", "Readiness", "cadence.spacecraft.readiness", []),
    surface("routing", "configuration", "spacecraft", "Routing", "cadence.spacecraft.routing", []),
    surface(
      "commanding",
      "operations",
      "spacecraft",
      "Commanding",
      "cadence.spacecraft.commanding",
      [],
    ),
    surface(
      "applications",
      "configuration",
      "spacecraft",
      "Applications",
      "cadence.spacecraft.applications",
      ["install", "disable", "uninstall"],
    ),
    surface(
      "telemetry_decom",
      "configuration",
      "spacecraft",
      "Telemetry Decom",
      "cadence.telemetry_decom.manage",
      ["change_revision", "save_catalog_revision", "enable", "disable"],
    ),
  ],
});

function surface(
  surfaceId: string,
  purpose: "overview" | "configuration" | "operations",
  scope: "mission" | "spacecraft",
  label: string,
  queryId: string,
  actions: string[],
) {
  return {
    surfaceId,
    version: 1,
    purpose,
    scope,
    placement: "application_workspace" as const,
    navigation: { label, order: surfaceId === "list" ? 10 : 20 },
    dataContract: { id: queryId, version: 1 },
    actions,
    renderer: { kind: "federated-vue" as const, exposedModule: "./Application" },
  };
}

export default SpacecraftApplication;
