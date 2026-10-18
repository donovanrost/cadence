import { readPublication } from "../../tools/publication-metadata.ts";
import { createModuleFederationConfig } from "@module-federation/vite";

const publication = readPublication(import.meta.dirname);

export default createModuleFederationConfig({
  name: publication.remoteName,
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
