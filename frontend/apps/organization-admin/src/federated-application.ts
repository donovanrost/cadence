import {
  APPLICATION_HOST_CONTRACT,
  defineApplicationManifest,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
} from "@cadence/plugin-sdk";
import OrganizationAdminApplication from "./OrganizationAdminApplication.vue";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";
import { exposedComponents } from "./surface-components";

export const manifest = defineApplicationManifest({
  schema: FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  hostContract: APPLICATION_HOST_CONTRACT,
  package: {
    packageId: "cadence.organization-admin",
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
    applicationKey: "organization_admin",
    version: 1,
    displayName: "Organization Administration",
    description:
      "Manage organization identity, provider access, notifications, and platform administration.",
    installableScopes: ["organization", "user", "admin"] as const,
  },
  surfaces: SURFACE_CONTRACTS.map((surface) => ({
    surfaceId: surface.surfaceId,
    version: 1,
    purpose: surface.purpose,
    scope: surface.scope,
    placement: surface.placement,
    navigation: surface.navigation,
    dataContract: surface.query,
    actions: surface.actions,
    renderer: { kind: "federated-vue" as const, exposedModule: surface.exposedModule },
  })),
});

export { exposedComponents };

export default OrganizationAdminApplication;
