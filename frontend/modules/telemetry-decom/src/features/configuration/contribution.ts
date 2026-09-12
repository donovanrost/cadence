import ConfigurationSurface from "./ConfigurationSurface.vue";

// Registered by compiled delivery code under the existing application surface contract.
export const configurationContribution = {
  id: "telemetry-decom.configuration",
  version: 1,
  applicationKey: "telemetry_decom",
  surfaceId: "manage",
  query: { id: "cadence.telemetry_decom.manage", version: 1 },
  component: ConfigurationSurface,
  actions: {
    save_catalog_revision: "save_configuration",
    enable: "request_activation",
    disable: "disable",
  },
} as const;
