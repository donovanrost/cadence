import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  HostBridge,
  SpacecraftHostContext,
} from "@cadence/plugin-sdk";
import { h, type Component } from "vue";
import RemoteApplicationBoundary from "./RemoteApplicationBoundary.vue";
import { loadFederatedApplication } from "./remote-loader";

vi.mock("./remote-loader", () => ({ loadFederatedApplication: vi.fn() }));

const application: CatalogApplication = {
  applicationKey: "comms_overview",
  applicationVersion: 1,
  displayName: "Communications Overview",
  description: "Mission communications overview.",
  package: { packageId: "cadence.comms_overview", version: 1 },
  surface: {
    surfaceId: "overview",
    version: 1,
    purpose: "overview",
    scope: "mission",
    placement: "application_workspace",
    navigation: { label: "Overview", order: 10 },
    dataContract: { id: "cadence.comms.overview", version: 1 },
    actions: [],
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  },
  release: {
    federation: "module_federation",
    releaseId: "2026.08.29.1",
    remoteName: "cadence_comms_overview",
    manifestUrl: "/assets/application-host/comms-overview/mf-manifest.json",
    exposedModule: "./Application",
  },
};

const context: SpacecraftHostContext = {
  scope: "spacecraft",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: "spacecraft-1",
  spacecraftName: "FB-1",
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
};

describe("RemoteApplicationBoundary", () => {
  it("exposes mounted identity only after admitting and rendering the remote", async () => {
    vi.mocked(loadFederatedApplication).mockResolvedValueOnce({
      manifest: {
        schema: "cadence.first-party-federated-application.v1",
        hostContract: "cadence.application-host.v1",
        package: { ...application.package, trust: "first_party" },
        compatibility: {
          cadenceApplicationContract: 1,
          cadenceSurfaceContract: 1,
          cadenceFederatedRendererContract: 1,
          cadenceThemeContract: 1,
        },
        application: {
          applicationKey: application.applicationKey,
          version: application.applicationVersion,
          displayName: application.displayName,
          description: application.description,
          installableScopes: [application.surface.scope],
        },
        surfaces: [application.surface],
      },
      default: { render: () => h("main", { id: "admitted-remote" }) },
    });
    const wrapper = mount(RemoteApplicationBoundary, {
      props: {
        application,
        context: { ...context, scope: "mission", spacecraftId: null, spacecraftName: null },
        bridge: {} as HostBridge,
        fallbackHref: "/",
      },
    });
    expect(wrapper.find("[data-mounted-release]").exists()).toBe(false);
    await flushPromises();
    const boundary = wrapper.get('[data-remote-state="ready"]');
    expect(boundary.attributes("data-mounted-release")).toBe(application.release.releaseId);
    expect(boundary.attributes("data-mounted-application")).toBe(application.applicationKey);
    expect(boundary.attributes("data-mounted-surface")).toBe(application.surface.surfaceId);
    expect(boundary.find("#admitted-remote").exists()).toBe(true);
    wrapper.unmount();
  });
  it("contains an approved remote load failure and exposes retry", async () => {
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.mocked(loadFederatedApplication).mockRejectedValueOnce(
      new Error("Approved release could not be loaded."),
    );

    const wrapper = mount(RemoteApplicationBoundary, {
      props: {
        application,
        context,
        bridge: {} as HostBridge,
        fallbackHref: "/missions/mission-1/comms",
      },
    });

    await flushPromises();

    expect(wrapper.find("#remote-error").exists()).toBe(true);
    expect(wrapper.find("[data-mounted-release]").exists()).toBe(false);
    expect(wrapper.find("#remote-error-message").text()).toBe(
      "The approved application release could not be loaded.",
    );
    expect(wrapper.find("#remote-error").text()).not.toContain("internal");
    expect(wrapper.find("#remote-error-reference").text()).toMatch(/^Reference ID: [0-9a-f-]{36}$/);
    expect(wrapper.find("#retry-remote").exists()).toBe(true);
    expect(wrapper.find("#remote-fallback").attributes("href")).toBe("/missions/mission-1/comms");
    expect(consoleError).toHaveBeenCalledWith(
      expect.stringMatching(/^Cadence federation failure [0-9a-f-]{36}$/),
      expect.objectContaining({
        applicationKey: "comms_overview",
        releaseId: "2026.08.29.1",
        surfaceId: "overview",
        reason: expect.any(Error),
      }),
    );
    expect(wrapper.find("#remote-loading").exists()).toBe(false);
    await wrapper.find("#retry-remote").trigger("click");
    expect(wrapper.emitted("retry")).toHaveLength(1);
    wrapper.unmount();
    consoleError.mockRestore();
  });

  it("does not mount a late remote after the boundary is superseded", async () => {
    type LoadedRemote = Awaited<ReturnType<typeof loadFederatedApplication>>;
    let resolveLoad: ((value: LoadedRemote) => void) | undefined;
    vi.mocked(loadFederatedApplication).mockImplementationOnce(
      () =>
        new Promise<LoadedRemote>((resolve) => {
          resolveLoad = resolve;
        }),
    );

    const wrapper = mount(RemoteApplicationBoundary, {
      props: {
        application,
        context,
        bridge: {} as HostBridge,
        fallbackHref: "/missions/mission-1/comms",
      },
    });

    wrapper.unmount();
    resolveLoad?.({
      manifest: {} as FirstPartyApplicationManifest,
      default: {} as Component,
    });
    await flushPromises();

    expect(wrapper.emitted("ready")).toBeUndefined();
  });
});
