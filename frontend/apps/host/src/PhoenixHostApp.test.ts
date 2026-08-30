import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import { describe, expect, it, vi } from "vite-plus/test";
import PhoenixHostApp from "./PhoenixHostApp.vue";
import type { FrontendApplicationCatalog } from "@cadence/plugin-sdk";

const catalog = {
  schema: "cadence.first-party-frontend-catalog.v1",
  hostContract: "cadence.application-host.v1",
  generatedAt: "2026-08-29T20:00:00.000Z",
  session: {
    sessionId: "session-1",
    csrfToken: "csrf-1",
    bridgeBaseUrl: "/api/cadence/application-host/v1",
    context: {
      scope: "mission",
      organizationId: "org-1",
      missionId: "mission-1",
      missionName: "Firebird",
      spacecraftId: null,
      spacecraftName: null,
      actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
    },
  },
  applications: [
    {
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
    },
  ],
} satisfies FrontendApplicationCatalog;

const BoundaryStub = defineComponent({ template: "<div id='remote-boundary-stub'></div>" });

describe("Phoenix host application", () => {
  it("loads and mounts only the mission comms application without demo auth", async () => {
    const fetcher = vi.fn(async () => Response.json(catalog));
    const wrapper = mount(PhoenixHostApp, {
      props: {
        missionId: "mission-1",
        catalogUrl: "/api/cadence/application-host/v1/catalog",
        fetcher: fetcher as typeof fetch,
      },
      global: { stubs: { RemoteApplicationBoundary: BoundaryStub } },
    });

    await flushPromises();

    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#remote-boundary-stub").exists()).toBe(true);
    expect(wrapper.find("#phoenix-host-home").attributes("href")).toBe("/missions/mission-1/comms");
    expect(wrapper.text()).toContain("Firebird");
    wrapper.unmount();
  });

  it("contains a catalog without comms_overview at the Phoenix boundary", async () => {
    const fetcher = vi.fn(async () =>
      Response.json({
        ...catalog,
        applications: [{ ...catalog.applications[0], applicationKey: "other_application" }],
      }),
    );
    const wrapper = mount(PhoenixHostApp, {
      props: {
        missionId: "mission-1",
        catalogUrl: "/catalog",
        fetcher: fetcher as typeof fetch,
      },
    });

    await flushPromises();

    expect(wrapper.find("#phoenix-host-error").text()).toContain("does not provide comms_overview");
    wrapper.unmount();
  });
});
