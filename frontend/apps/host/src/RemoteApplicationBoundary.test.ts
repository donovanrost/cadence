import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type {
  CatalogApplication,
  FirstPartyApplicationManifest,
  HostBridge,
  SpacecraftHostContext,
} from "@cadence/plugin-sdk";
import type { Component } from "vue";
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
  it("contains an approved remote load failure and exposes retry", async () => {
    vi.mocked(loadFederatedApplication).mockRejectedValueOnce(
      new Error("Approved release could not be loaded."),
    );

    const wrapper = mount(RemoteApplicationBoundary, {
      props: {
        application,
        context,
        bridge: {} as HostBridge,
      },
    });

    await flushPromises();

    expect(wrapper.find("#remote-error").exists()).toBe(true);
    expect(wrapper.find("#remote-error-message").text()).toBe(
      "The approved application release could not be loaded.",
    );
    expect(wrapper.find("#remote-error").text()).not.toContain("internal");
    expect(wrapper.find("#remote-error-reference").text()).toMatch(
      /^Reference ID: [0-9a-f-]{36}$/,
    );
    expect(wrapper.find("#retry-remote").exists()).toBe(true);
    expect(wrapper.find("#remote-loading").exists()).toBe(false);
    await wrapper.find("#retry-remote").trigger("click");
    expect(wrapper.emitted("retry")).toHaveLength(1);
    wrapper.unmount();
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
