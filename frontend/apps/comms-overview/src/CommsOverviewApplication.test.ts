import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import type { FullPageSurfaceProps, HostBridge, MissionHostContext } from "@cadence/plugin-sdk";
import CommsOverviewApplication from "./CommsOverviewApplication.vue";
import CanonicalApplication, {
  canonicalManifest,
  legacyManifest,
  manifest,
} from "./federated-application";
import LegacyApplication, { manifest as legacyModuleManifest } from "./legacy-application";
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
    remoteName: "cadence_comms",
    manifestUrl: "/assets/application-host/comms/mf-manifest.json",
    exposedModule: "./LegacyApplication",
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
    expect(canonicalManifest.surfaces).toEqual([
      {
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
      {
        surfaceId: "validation",
        version: 1,
        purpose: "activity",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Validation", order: 20 },
        dataContract: { id: "cadence.comms.validation", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "transports",
        version: 1,
        purpose: "collection",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Transports", order: 30 },
        dataContract: { id: "cadence.comms.transports", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "transport",
        version: 1,
        purpose: "subject_detail",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Transport", order: 40 },
        dataContract: { id: "cadence.comms.transport", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "routing",
        version: 1,
        purpose: "collection",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Routing", order: 50 },
        dataContract: { id: "cadence.comms.routing", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "routing_detail",
        version: 1,
        purpose: "subject_detail",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Routing Rule", order: 60 },
        dataContract: { id: "cadence.comms.routing_detail", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "ground_stations",
        version: 1,
        purpose: "collection",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Ground Stations", order: 70 },
        dataContract: { id: "cadence.comms.ground_stations", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "ground_station",
        version: 1,
        purpose: "subject_detail",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Ground Station", order: 80 },
        dataContract: { id: "cadence.comms.ground_station", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "provider_list",
        version: 1,
        purpose: "collection",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Providers", order: 90 },
        dataContract: { id: "cadence.comms.provider_list", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "provider_new",
        version: 1,
        purpose: "configuration",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "New Provider", order: 100 },
        dataContract: { id: "cadence.comms.provider_new", version: 1 },
        actions: ["create_provider"],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "provider_show",
        version: 1,
        purpose: "subject_detail",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Provider", order: 110 },
        dataContract: { id: "cadence.comms.provider_show", version: 1 },
        actions: ["validate_provider", "sync_provider", "archive_provider"],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "transport_new",
        version: 1,
        purpose: "configuration",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "New Transport", order: 120 },
        dataContract: { id: "cadence.comms.transport_new", version: 1 },
        actions: ["validate", "save"],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "routing_new",
        version: 1,
        purpose: "configuration",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "New Routing Rule", order: 130 },
        dataContract: { id: "cadence.comms.routing_new", version: 1 },
        actions: ["validate", "save"],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "ground_station_new",
        version: 1,
        purpose: "configuration",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "New Ground Station", order: 140 },
        dataContract: { id: "cadence.comms.ground_station_new", version: 1 },
        actions: ["validate", "save"],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      {
        surfaceId: "ground_station_edit",
        version: 1,
        purpose: "configuration",
        scope: "mission",
        placement: "application_workspace",
        navigation: { label: "Edit Ground Station", order: 150 },
        dataContract: { id: "cadence.comms.ground_station_edit", version: 1 },
        actions: ["validate", "save"],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
    ]);
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
    expect(manifest).toBe(canonicalManifest);
    expect(CanonicalApplication).not.toBe(CommsOverviewApplication);
    expect(legacyModuleManifest).toBe(legacyManifest);
    expect(LegacyApplication).toBe(CommsOverviewApplication);
    expect(legacyManifest.surfaces).toEqual([
      expect.objectContaining({
        surfaceId: "overview",
        purpose: "overview",
        scope: "mission",
        dataContract: { id: "cadence.comms.overview", version: 1 },
        actions: [],
        renderer: { kind: "federated-vue", exposedModule: "./LegacyApplication" },
      }),
    ]);
  });
});
