import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type { FullPageSurfaceProps, HostBridge, HostContext } from "@cadence/plugin-sdk";
import OrganizationAdminApplication from "./OrganizationAdminApplication.vue";
import { manifest } from "./federated-application";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";

const context = {
  scope: "organization",
  organizationId: "org-1",
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
} as unknown as HostContext;

function propsFor(surface: FullPageSurfaceProps["surface"], query: HostBridge["query"]): FullPageSurfaceProps {
  const application = {
    applicationKey: "organization_admin",
    applicationVersion: 1,
    displayName: "Organization Administration",
    description: "Organization administration.",
    package: { packageId: "cadence.organization-admin", version: 1 },
    surface,
    release: {
      federation: "module_federation" as const,
      releaseId: "organization-admin-v1",
      remoteName: "cadence_organization_admin",
      manifestUrl: "/assets/application-host/organization-admin/mf-manifest.json",
      exposedModule: "./Application",
    },
  };

  return {
    application,
    surface,
    context,
    bridge: {
      query,
      execute: vi.fn(),
      subscribe: vi.fn(),
    },
  };
}

const rendererStubs = Object.fromEntries(
  SURFACE_CONTRACTS.map(({ component }) => [
    component,
    { template: `<div data-test-legacy-renderer="${component}" />` },
  ]),
);

describe("Organization Admin federated adapter", () => {
  it.each(SURFACE_CONTRACTS)(
    "selects $surfaceId, queries its declared DTO, and mounts its legacy component",
    async (contract) => {
      const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === contract.surfaceId)!;
      const query = vi.fn<HostBridge["query"]>().mockResolvedValue({
        queryVersion: 1,
        presentation: {},
      });
      const wrapper = mount(OrganizationAdminApplication, {
        props: propsFor(surface, query),
        global: { stubs: rendererStubs },
      });

      await flushPromises();

      expect(query).toHaveBeenCalledWith({
        queryId: contract.query.id,
        version: contract.query.version,
        context,
      });
      expect(wrapper.find("#organization-admin-application").attributes()).toMatchObject({
        "data-organization-admin-surface": contract.surfaceId,
        "data-organization-admin-renderer": contract.component,
      });
      expect(wrapper.find(`[data-test-legacy-renderer="${contract.component}"]`).exists()).toBe(
        true,
      );
      wrapper.unmount();
    },
  );
});
