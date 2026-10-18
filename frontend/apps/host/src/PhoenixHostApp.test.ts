import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import { describe, expect, it, vi } from "vite-plus/test";
import type { FrontendApplicationCatalog } from "@cadence/plugin-sdk";
import PhoenixHostApp from "./PhoenixHostApp.vue";

const missionCatalog = {
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
        renderer: { kind: "federated-vue", exposedModule: "./LegacyApplication" },
      },
      release: {
        federation: "module_federation",
        releaseId: "comms-overview-v1",
        remoteName: "cadence_comms",
        manifestUrl: "/assets/application-host/comms/mf-manifest.json",
        exposedModule: "./LegacyApplication",
      },
    },
  ],
} satisfies FrontendApplicationCatalog;

const spacecraftCatalog = {
  ...missionCatalog,
  session: {
    ...missionCatalog.session,
    context: {
      scope: "spacecraft",
      organizationId: "org-1",
      missionId: "mission-1",
      missionName: "Firebird",
      spacecraftId: "spacecraft-1",
      spacecraftName: "FB-1",
      actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
    },
  },
  applications: [
    {
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      displayName: "Telemetry Decom",
      description: "Choose the packet inputs decoded for an installed spacecraft.",
      package: { packageId: "cadence.telemetry-applications", version: 1 },
      surface: {
        surfaceId: "packet_bindings",
        version: 1,
        purpose: "configuration",
        scope: "spacecraft",
        placement: "application_workspace",
        navigation: { label: "Packet bindings", order: 20 },
        dataContract: { id: "cadence.packet_bindings.manage", version: 1 },
        actions: ["save_packet_bindings"],
        renderer: { kind: "federated-vue", exposedModule: "./Application" },
      },
      release: {
        federation: "module_federation",
        releaseId: "telemetry-decom-v1",
        remoteName: "cadence_telemetry_decom",
        manifestUrl: "/assets/application-host/telemetry-decom/mf-manifest.json",
        exposedModule: "./Application",
      },
    },
  ],
} satisfies FrontendApplicationCatalog;

const BoundaryStub = defineComponent({
  props: { fallbackHref: { type: String, required: true } },
  template: "<div id='remote-boundary-stub'></div>",
});

describe("Phoenix host application", () => {
  it("mounts the route-selected mission Comms surface with fallback navigation", async () => {
    const fetcher = vi.fn(async () => Response.json(missionCatalog));
    const wrapper = mount(PhoenixHostApp, {
      props: {
        applicationKey: "comms_overview",
        surfaceId: "overview",
        missionId: "mission-1",
        catalogUrl: "/api/cadence/application-host/v1/catalog",
        fallbackHref: "/missions/mission-1/comms",
        fetcher: fetcher as typeof fetch,
      },
      global: { stubs: { RemoteApplicationBoundary: BoundaryStub } },
    });

    await flushPromises();

    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#remote-boundary-stub").exists()).toBe(true);
    expect(wrapper.findComponent(BoundaryStub).props("fallbackHref")).toBe(
      "/missions/mission-1/comms",
    );
    wrapper.unmount();
  });

  it("mounts the route-selected spacecraft telemetry surface", async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      expect(input).toBe(
        "/api/cadence/application-host/v1/catalog?mission_id=mission-1&spacecraft_id=spacecraft-1",
      );
      return Response.json(spacecraftCatalog);
    });
    const wrapper = mount(PhoenixHostApp, {
      props: {
        applicationKey: "telemetry_decom",
        surfaceId: "packet_bindings",
        spacecraftId: "spacecraft-1",
        missionId: "mission-1",
        catalogUrl: "/api/cadence/application-host/v1/catalog",
        fallbackHref: "/missions/mission-1/spacecraft/spacecraft-1/applications",
        fetcher: fetcher as typeof fetch,
      },
      global: { stubs: { RemoteApplicationBoundary: BoundaryStub } },
    });

    await flushPromises();

    expect(wrapper.find("#remote-boundary-stub").exists()).toBe(true);
    expect(wrapper.findComponent(BoundaryStub).props("fallbackHref")).toBe(
      "/missions/mission-1/spacecraft/spacecraft-1/applications",
    );
    wrapper.unmount();
  });

  it("contains a catalog without the requested application at the Phoenix boundary", async () => {
    const fetcher = vi.fn(async () =>
      Response.json({
        ...missionCatalog,
        applications: [{ ...missionCatalog.applications[0], applicationKey: "other_application" }],
      }),
    );
    const wrapper = mount(PhoenixHostApp, {
      props: {
        applicationKey: "missing_application",
        surfaceId: "overview",
        missionId: "mission-1",
        catalogUrl: "/catalog",
        fallbackHref: "/missions/mission-1",
        fetcher: fetcher as typeof fetch,
      },
    });

    await flushPromises();

    expect(wrapper.find("#phoenix-host-error").text()).toContain(
      'does not provide requested application "missing_application"',
    );
    wrapper.unmount();
  });

  it("performs one bounded authenticated recovery and sanitizes a repeated 401", async () => {
    const fetcher = vi.fn(async () =>
      Response.json({ message: "SECRET-RAW-CATALOG-DETAIL" }, { status: 401 }),
    );
    const wrapper = mount(PhoenixHostApp, {
      props: {
        applicationKey: "comms_overview",
        surfaceId: "overview",
        missionId: "mission-1",
        catalogUrl: "/catalog",
        fallbackHref: "/missions/mission-1",
        fetcher: fetcher as typeof fetch,
      },
    });

    await flushPromises();

    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#remote-boundary-stub").exists()).toBe(false);
    expect(wrapper.find("#phoenix-host-error").text()).toContain(
      "The authenticated application catalog could not be loaded.",
    );
    expect(wrapper.find("#phoenix-host-error").text()).not.toContain("SECRET-RAW-CATALOG-DETAIL");
    expect(wrapper.find("#phoenix-host-error-reference").text()).toMatch(
      /^Reference ID: [0-9a-f-]{36}$/,
    );
    wrapper.unmount();
  });

  it("contains a 503 catalog failure without mounting a remote", async () => {
    const fetcher = vi.fn(async () =>
      Response.json({ message: "SECRET-RAW-503-DETAIL" }, { status: 503 }),
    );
    const wrapper = mount(PhoenixHostApp, {
      props: {
        applicationKey: "comms_overview",
        surfaceId: "overview",
        missionId: "mission-1",
        catalogUrl: "/catalog",
        fallbackHref: "/missions/mission-1",
        fetcher: fetcher as typeof fetch,
      },
    });

    await flushPromises();

    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#remote-boundary-stub").exists()).toBe(false);
    expect(wrapper.find("#phoenix-host-error").text()).toContain(
      "The authenticated application catalog could not be loaded.",
    );
    expect(wrapper.find("#phoenix-host-error").text()).not.toContain("SECRET-RAW-503-DETAIL");
    wrapper.unmount();
  });
});
