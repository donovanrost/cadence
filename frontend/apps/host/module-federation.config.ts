import { createModuleFederationConfig } from "@module-federation/vite";

export default createModuleFederationConfig({
  name: "cadence_host",
  remotes: {},
  shared: {
    vue: {
      singleton: true,
      requiredVersion: "^3.5.40",
      allowNodeModulesSuffixMatch: true,
    },
  },
  dts: false,
});
