import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import type { FullPageSurfaceProps, HostBridge, HostContext } from "@cadence/plugin-sdk";
import OrganizationAdminApplication from "./OrganizationAdminApplication.vue";
import { manifest } from "./federated-application";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";

const context = {
  scope: "organization",
  organizationId: "org-1",
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
} as unknown as HostContext;

function propsFor(
  surface: FullPageSurfaceProps["surface"],
  query: HostBridge["query"],
): FullPageSurfaceProps {
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

afterEach(() => vi.restoreAllMocks());

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

  it("sends the exact surface action envelope and displays its receipt after a refresh", async () => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "provider_account_new",
    )!;
    const query = vi
      .fn<HostBridge["query"]>()
      .mockResolvedValue({ queryVersion: 1, presentation: {} });
    const execute = vi.fn<HostBridge["execute"]>().mockResolvedValue({
      receiptId: "receipt-organization-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: {},
    });
    const props = propsFor(surface, query);
    props.bridge.execute = execute;
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          ProviderAccountNew: {
            template: `<button id="save" @click="$emit('save', { provider_account: { display_name: 'Relay' } })" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#save").trigger("click");
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "organization_admin",
      applicationVersion: 1,
      surfaceId: "provider_account_new",
      surfaceVersion: 1,
      actionId: "register_provider_account",
      input: { provider_account: { display_name: "Relay" } },
      context,
    });
    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#organization-admin-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-organization-1",
    );
    expect(wrapper.find("#organization-admin-action-notice").attributes("data-completed-at")).toBe(
      "2026-09-04T00:00:00Z",
    );
    wrapper.unmount();
  });

  it("honors same-origin navigation receipts without issuing a redundant query", async () => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "admin_organization_show",
    )!;
    const query = vi
      .fn<HostBridge["query"]>()
      .mockResolvedValue({ queryVersion: 1, presentation: {} });
    const execute = vi.fn<HostBridge["execute"]>().mockResolvedValue({
      receiptId: "receipt-navigation-1",
      completedAt: "2026-09-04T00:00:01Z",
      result: { navigation: { href: "/session/organization" } },
    });
    const props = propsFor(surface, query);
    props.bridge.execute = execute;
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          AdminOrganizationShow: {
            template: `<button id="issue" @click="$emit('issue-service-identity', { service_identity: { display_name: 'Relay', service_identity_id: 'svc-1' } })" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#issue").trigger("click");
    await flushPromises();
    wrapper.unmount();
    expect(assign).toHaveBeenCalledWith("/session/organization");
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("shows rejection and keeps the newest overlapping action state", async () => {
    const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === "admin_runtime")!;
    const query = vi
      .fn<HostBridge["query"]>()
      .mockResolvedValue({ queryVersion: 1, presentation: {} });
    const first = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const second = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const execute = vi
      .fn<HostBridge["execute"]>()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);
    const props = propsFor(surface, query);
    props.bridge.execute = execute;
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          AdminRuntime: {
            template: `<button id="refresh" @click="$emit('refresh')" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#refresh").trigger("click");
    await wrapper.get("#refresh").trigger("click");
    second.resolve({
      receiptId: "receipt-organization-2",
      completedAt: "2026-09-04T00:00:02Z",
      result: {},
    });
    await flushPromises();
    first.resolve({
      receiptId: "receipt-organization-1",
      completedAt: "2026-09-04T00:00:01Z",
      result: {},
    });
    await flushPromises();

    expect(wrapper.find("#organization-admin-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-organization-2",
    );
    expect(query).toHaveBeenCalledTimes(2);
    wrapper.unmount();

    const rejectedExecute = vi
      .fn<HostBridge["execute"]>()
      .mockRejectedValue(new Error("forbidden"));
    const rejectedProps = propsFor(surface, query);
    rejectedProps.bridge.execute = rejectedExecute;
    const rejected = mount(OrganizationAdminApplication, {
      props: rejectedProps,
      global: {
        stubs: { AdminRuntime: { template: `<button id="refresh" @click="$emit('refresh')" />` } },
      },
    });
    await flushPromises();
    await rejected.get("#refresh").trigger("click");
    await flushPromises();
    expect(rejected.find("#organization-admin-action-error").text()).toContain("forbidden");
    rejected.unmount();
  });
});

function deferred<TResult>() {
  let resolve!: (value: TResult | PromiseLike<TResult>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<TResult>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}
