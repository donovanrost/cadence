import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type { CatalogApplication, HostBridge, SpacecraftHostContext } from "@cadence/plugin-sdk";
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
    expect(wrapper.find("#retry-remote").exists()).toBe(true);
    expect(wrapper.find("#remote-loading").exists()).toBe(false);
    wrapper.unmount();
  });
});
