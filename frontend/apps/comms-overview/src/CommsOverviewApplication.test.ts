import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostBridge,
  MissionHostContext,
} from "@cadence/plugin-sdk";
import CommsOverviewApplication from "./CommsOverviewApplication.vue";
import { canonicalManifest, legacyManifest, manifest } from "./federated-application";
import { unwrapCommsOverviewResponse, type CommsOverviewResponse } from "./comms-overview";

const context: MissionHostContext = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
};

const presentationResponse: CommsOverviewResponse = {
  queryVersion: 1,
  presentation: {
    root: { attrs: { class: "space-y-6", id: "comms-overview-page" } },
    header: {
      attrs: { class: "border-b border-primary/20 pb-4" },
      body: { attrs: {} },
      content: { attrs: {} },
      eyebrow: { attrs: { class: "hud-label" }, text: "Communications" },
      title: { attrs: { class: "mission-title" }, text: "Firebird" },
      title_suffix: { attrs: { class: "mission-title-suffix" }, text: "· Mission Comms" },
    },
    overview: {
      transport: {
        id: "comms-transports",
        eyebrow: "Transport",
        count: 0,
        count_label: "transports configured",
        description: "Mission transport readiness.",
        status: { tone: "attention", label: "Needs Work" },
        empty: true,
        empty_state: {
          title: "No transports configured",
          description: "Add a transport.",
          action_label: "Add a transport",
          action_href: "/missions/mission-1/comms/transports/new",
        },
        rows: [],
        manage_label: "Manage transports →",
        manage_href: "/missions/mission-1/comms/transports",
        add_label: "+ Add a transport",
        add_href: "/missions/mission-1/comms/transports/new",
      },
      validation: {
        id: "comms-validation-page",
        eyebrow: "Setup Checks",
        title: "What's missing or broken",
        description: "Checks on saved configuration.",
        status: { tone: "ready", label: "No Findings" },
        empty: true,
        empty_state: { title: "All clear", description: "The saved configuration is consistent." },
        findings_id: "comms-validation-findings",
        finding_groups: [],
      },
    },
  },
};

const application = {
  applicationKey: "comms_overview",
  applicationVersion: 1,
  displayName: "Communications Overview",
  description: "Mission communications overview.",
  package: { packageId: "cadence.comms_overview", version: 1 },
  surface: legacyManifest.surfaces[0],
  release: {
    federation: "module_federation" as const,
    releaseId: "comms-overview-v1",
    remoteName: "cadence_comms_overview",
    manifestUrl: "/assets/application-host/comms-overview/mf-manifest.json",
    exposedModule: "./Application",
  },
};

function propsFor(query: unknown): FullPageSurfaceProps {
  return {
    application,
    surface: application.surface,
    context,
    bridge: {
      query: query as HostBridge["query"],
      execute: vi.fn(),
      subscribe: vi.fn(),
    },
  };
}

describe("Comms Overview federated adapter", () => {
  it("queries the mission context and renders the real Phoenix presentation page", async () => {
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue(presentationResponse);
    const wrapper = mount(CommsOverviewApplication, { props: propsFor(query) });

    expect(wrapper.find("#comms-overview-loading").exists()).toBe(true);
    await flushPromises();

    expect(query).toHaveBeenCalledWith({
      queryId: "cadence.comms.overview",
      version: 1,
      context,
    });
    expect(wrapper.find("#comms-overview-page").exists()).toBe(true);
    expect(wrapper.find("#comms-overview-content").exists()).toBe(true);
    expect(wrapper.find("#comms-transports").exists()).toBe(true);
    expect(wrapper.text()).toContain("Firebird");
    wrapper.unmount();
  });

  it("contains malformed DTOs and retries the same approved query", async () => {
    const query = vi
      .fn<HostBridge["query"]>()
      .mockResolvedValueOnce({ queryVersion: 1, presentation: {} })
      .mockResolvedValueOnce(presentationResponse);
    const wrapper = mount(CommsOverviewApplication, { props: propsFor(query) });

    await flushPromises();
    expect(wrapper.find("#comms-overview-error").exists()).toBe(true);
    expect(wrapper.find("#retry-comms-overview").exists()).toBe(true);

    await wrapper.get("#retry-comms-overview").trigger("click");
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#comms-overview-page").exists()).toBe(true);
    wrapper.unmount();
  });

  it("surfaces bridge failures as a retryable application state", async () => {
    const query = vi.fn<HostBridge["query"]>().mockRejectedValue(new Error("query unavailable"));
    const wrapper = mount(CommsOverviewApplication, { props: propsFor(query) });

    await flushPromises();

    expect(wrapper.find("#comms-overview-error").text()).toContain("query unavailable");
    expect(wrapper.find("#comms-overview-page").exists()).toBe(false);
    wrapper.unmount();
  });

  it("rejects a validation payload that hides nonempty finding groups", () => {
    const malformed = {
      ...presentationResponse,
      presentation: {
        ...presentationResponse.presentation,
        overview: {
          ...presentationResponse.presentation.overview,
          validation: {
            ...presentationResponse.presentation.overview.validation,
            empty: true,
            finding_groups: [
              { id: "setup", title: "Setup", description: "Review setup.", findings: [] },
            ],
          },
        },
      },
    };

    expect(() => unwrapCommsOverviewResponse(malformed)).toThrow(
      "communications overview response is invalid",
    );
  });

  it("accepts validation findings without optional navigation actions", () => {
    const compatible = {
      ...presentationResponse,
      presentation: {
        ...presentationResponse.presentation,
        overview: {
          ...presentationResponse.presentation.overview,
          validation: {
            ...presentationResponse.presentation.overview.validation,
            empty: false,
            finding_groups: [
              {
                id: "setup",
                title: "Setup",
                description: "Review setup.",
                findings: [
                  {
                    id: null,
                    title: "Review setup",
                    body: "No navigation action is available.",
                    status: { tone: "attention", label: "Warning" },
                  },
                ],
              },
            ],
          },
        },
      },
    };

    expect(() => unwrapCommsOverviewResponse(compatible)).not.toThrow();
  });

  it("publishes all mission Comms surfaces from the canonical remote manifest", () => {
    expect(canonicalManifest.package).toMatchObject({ packageId: "cadence.comms", version: 1 });
    expect(canonicalManifest.application).toMatchObject({ applicationKey: "comms", version: 1 });
    expect(canonicalManifest.surfaces.map(({ surfaceId }) => surfaceId)).toEqual([
      "overview",
      "validation",
      "transports",
      "transport",
      "routing",
      "routing_detail",
      "ground_stations",
      "ground_station",
    ]);
    expect(canonicalManifest.surfaces.every(({ dataContract }) => dataContract.version === 1)).toBe(
      true,
    );
  });

  it("publishes the exact mission-scoped first-party identity", () => {
    expect(legacyManifest.package).toMatchObject({
      packageId: "cadence.comms_overview",
      version: 1,
    });
    expect(legacyManifest.application).toMatchObject({
      applicationKey: "comms_overview",
      version: 1,
    });
    expect(legacyManifest.application.installableScopes).toEqual(["mission"]);
    expect(manifest).toBe(legacyManifest);
    expect(legacyManifest.surfaces).toEqual([
      expect.objectContaining({
        surfaceId: "overview",
        purpose: "overview",
        scope: "mission",
        dataContract: { id: "cadence.comms.overview", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      }),
    ]);
  });
});
