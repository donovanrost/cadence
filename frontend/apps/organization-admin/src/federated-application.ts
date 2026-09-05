import {
  APPLICATION_HOST_CONTRACT,
  FEDERATED_APPLICATION_MANIFEST_SCHEMA,
  type FirstPartyApplicationManifest,
} from "@cadence/plugin-sdk";
import OrganizationAdminApplication from "./OrganizationAdminApplication.vue";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";
import { exposedComponents } from "./surface-components";

/*
 * The organization/admin/user scope literals are owned by the parallel host
 * foundation lane. Keep this publication forward-compatible with that ABI;
 * the current checkout's older SDK validator cannot admit those literals yet.
 */
export const manifest = {
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
    installableScopes: ["organization", "user", "admin"],
  },
  surfaces: SURFACE_CONTRACTS.map((surface, index) => ({
    surfaceId: surface.surfaceId,
    version: 1,
    purpose: surface.purpose,
    scope: surface.scope,
    placement: "application_workspace" as const,
    navigation: { label: surface.surfaceId.replaceAll("_", " "), order: (index + 1) * 10 },
    dataContract: surface.query,
    actions: surface.actions,
    renderer: { kind: "federated-vue" as const, exposedModule: "./Application" },
  })),
} as unknown as FirstPartyApplicationManifest;

export { exposedComponents };

export default OrganizationAdminApplication;
