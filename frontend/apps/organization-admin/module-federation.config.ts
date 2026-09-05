import { createModuleFederationConfig } from "@module-federation/vite";

export default createModuleFederationConfig({
  name: "cadence_organization_admin",
  filename: "remoteEntry.js",
  manifest: true,
  exposes: {
    "./Application": "./src/federated-application.ts",
    "./OrganizationHome": "./src/OrganizationHome.vue",
    "./ProviderAccountListPage": "./src/ProviderAccountListPage.vue",
    "./ProviderAccountNew": "./src/ProviderAccountNew.vue",
    "./ProviderAccountShow": "./src/ProviderAccountShow.vue",
    "./NotificationsPage": "./src/NotificationsPage.vue",
    "./NotificationsBell": "./src/NotificationsBell.vue",
    "./AdminHome": "./src/AdminHome.vue",
    "./AdminRuntime": "./src/AdminRuntime.vue",
    "./AdminOrganizationListPage": "./src/AdminOrganizationListPage.vue",
    "./AdminOrganizationNew": "./src/AdminOrganizationNew.vue",
    "./AdminOrganizationShow": "./src/AdminOrganizationShow.vue",
    "./AdminOrganizationInvite": "./src/AdminOrganizationInvite.vue",
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
