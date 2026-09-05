import { createModuleFederationConfig } from "@module-federation/vite";

export default createModuleFederationConfig({
  name: "cadence_comms",
  filename: "remoteEntry.js",
  manifest: true,
  exposes: {
    "./Application": "./src/federated-application.ts",
    "./LegacyApplication": "./src/legacy-application.ts",
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
