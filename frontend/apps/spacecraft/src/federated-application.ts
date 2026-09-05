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
    description: "Mission spacecraft configuration and operations surfaces.",
    installableScopes: ["mission", "spacecraft"],
  },
  surfaces: [
    surface("list", "overview", "mission", "Spacecraft", "cadence.spacecraft.list", []),
    surface("new", "configuration", "mission", "New spacecraft", "cadence.spacecraft.new", [
      "validate",
      "save",
    ]),
    surface(
      "profile_list",
      "overview",
      "mission",
      "Spacecraft profiles",
      "cadence.spacecraft.profiles",
      [],
    ),
    surface(
      "profile_new",
      "configuration",
      "mission",
      "New spacecraft profile",
      "cadence.spacecraft.profile.new",
      ["validate", "save"],
    ),
    surface(
      "profile_show",
      "subject_detail",
      "mission",
      "Spacecraft profile",
      "cadence.spacecraft.profile.show",
      [],
    ),
    surface("show", "overview", "spacecraft", "Spacecraft overview", "cadence.spacecraft.show", []),
    surface("edit", "configuration", "spacecraft", "Edit spacecraft", "cadence.spacecraft.edit", [
      "validate",
      "save",
    ]),
    surface(
      "readiness",
      "overview",
      "spacecraft",
      "Spacecraft readiness",
      "cadence.spacecraft.readiness",
      [],
    ),
    surface(
      "routing",
      "configuration",
      "spacecraft",
      "Spacecraft routing",
      "cadence.spacecraft.routing",
      [],
    ),
    surface(
      "commanding",
      "operations",
      "spacecraft",
      "Spacecraft commanding",
      "cadence.spacecraft.commanding",
      [],
    ),
    surface(
      "applications",
      "configuration",
      "spacecraft",
      "Spacecraft applications",
      "cadence.spacecraft.applications",
      ["install", "disable", "uninstall"],
    ),
    surface(
      "telemetry_decom",
      "configuration",
      "spacecraft",
      "Telemetry decomposition",
      "cadence.telemetry_decom.manage",
      ["save_configuration", "request_activation", "disable"],
    ),
  ],
});

function surface(
  surfaceId: string,
  purpose: "overview" | "configuration" | "operations" | "subject_detail",
  scope: "mission" | "spacecraft",
  label: string,
  queryId: string,
  actions: string[],
) {
  const orderBySurfaceId: Record<string, number> =
    scope === "mission"
      ? { list: 10, new: 20, profile_list: 30, profile_new: 40, profile_show: 50 }
      : {
          show: 10,
          edit: 20,
          readiness: 30,
          routing: 40,
          commanding: 50,
          applications: 60,
          telemetry_decom: 70,
        };

  return {
    surfaceId,
    version: 1,
    purpose,
    scope,
    placement: "application_workspace" as const,
    navigation: { label, order: orderBySurfaceId[surfaceId] },
    dataContract: { id: queryId, version: 1 },
    actions,
    renderer: { kind: "federated-vue" as const, exposedModule: "./Application" },
  };
}

export default SpacecraftApplication;
