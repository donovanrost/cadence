import { createModuleFederationConfig } from "@module-federation/vite";

export default createModuleFederationConfig({
  name: "cadence_mission_catalog",
  filename: "remoteEntry.js",
  manifest: true,
  exposes: {
    "./Application": "./src/federated-application.ts",
    "./MissionList": "./src/MissionList.vue",
    "./MissionNew": "./src/MissionNew.vue",
    "./MissionOverview": "./src/MissionOverview.vue",
    "./MissionApplicationsPage": "./src/MissionApplicationsPage.vue",
    "./CatalogIndex": "./src/CatalogIndex.vue",
    "./CatalogDatabaseNew": "./src/CatalogDatabaseNew.vue",
    "./CatalogDatabaseShow": "./src/CatalogDatabaseShow.vue",
    "./CatalogRevisionShow": "./src/CatalogRevisionShow.vue",
    "./CatalogArtifactShowPage": "./src/CatalogArtifactShowPage.vue",
    "./CatalogImportRunShow": "./src/CatalogImportRunShow.vue",
  },
  shared: {
    vue: {
      singleton: true,
      requiredVersion: "^3.5.40",
      allowNodeModulesSuffixMatch: true,
    },
  },
  dts: false,
});
