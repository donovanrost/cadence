import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import ContractProbeApplication from "./ContractProbeApplication.vue";

export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.frontend-fixtures",
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
    applicationKey: "contract_probe",
    version: 1,
    displayName: "Contract Probe",
    description: "A development fixture proving generic runtime application discovery.",
    installableScopes: ["spacecraft"],
  },
  surfaces: [
    {
      surfaceId: "runtime_contracts",
      version: 1,
      purpose: "overview",
      scope: "spacecraft",
      placement: "application_workspace",
      navigation: { label: "Runtime contracts", order: 90 },
      dataContract: { id: "cadence.contract_probe.snapshot", version: 1 },
      actions: [],
      renderer: { kind: "federated-vue", exposedModule: "./Application" },
    },
  ],
});

export default ContractProbeApplication;
