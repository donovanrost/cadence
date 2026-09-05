import { describe, expect, it, vi } from "vite-plus/test";
import type { CatalogApplication, FrontendApplicationCatalog } from "@cadence/plugin-sdk";
import {
  loadPhoenixApplicationCatalog,
  phoenixCatalogUrl,
  selectPhoenixApplication,
  type PhoenixHostConfig,
} from "./phoenix-catalog-client";

const missionCommsApplication = {
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
} satisfies CatalogApplication;

const spacecraftTelemetryApplication = {
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
} satisfies CatalogApplication;

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
  applications: [missionCommsApplication],
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
  applications: [spacecraftTelemetryApplication],
} satisfies FrontendApplicationCatalog;

const missionConfig: PhoenixHostConfig = {
  applicationKey: "comms_overview",
  surfaceId: "overview",
  missionId: "mission-1",
  catalogUrl: "/api/cadence/application-host/v1/catalog",
  fallbackHref: "/missions/mission-1/comms",
};

const spacecraftConfig: PhoenixHostConfig = {
  applicationKey: "telemetry_decom",
  surfaceId: "packet_bindings",
  spacecraftId: "spacecraft-1",
  missionId: "mission-1",
  catalogUrl: "/api/cadence/application-host/v1/catalog",
  fallbackHref: "/missions/mission-1/spacecraft/spacecraft-1/applications",
};

describe("Phoenix application catalog bootstrap", () => {
  it("encodes every tagged host scope without a fake mission id", () => {
    expect(phoenixCatalogUrl("/catalog", { scope: "organization", organizationId: "org-1" })).toBe(
      "/catalog?scope=organization&organization_id=org-1",
    );
    expect(phoenixCatalogUrl("/catalog", { scope: "user", userId: "user-1" })).toBe(
      "/catalog?scope=user&user_id=user-1",
    );
    expect(phoenixCatalogUrl("/catalog", { scope: "admin" })).toBe("/catalog?scope=admin");
  });

  it("rejects a tagged context carrying an identity from another scope", () => {
    expect(() =>
      phoenixCatalogUrl("/catalog", {
        scope: "organization",
        organizationId: "org-1",
        missionId: "mission-1",
      } as never),
    ).toThrow("organization context is invalid");
  });

  it("selects the requested mission Comms application and preserves same-origin credentials", async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(input).toBe("/api/cadence/application-host/v1/catalog?mission_id=mission-1");
      expect(init).toEqual({ credentials: "same-origin", cache: "no-store" });
      return Response.json(missionCatalog);
    });

    const catalog = await loadPhoenixApplicationCatalog(missionConfig, {
      fetch: fetcher as typeof fetch,
    });

    expect(selectPhoenixApplication(catalog, missionConfig)).toEqual(
      missionCatalog.applications[0],
    );
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("loads an unknown but valid Phoenix-admitted application without host identity knowledge", async () => {
    const unknownApplication: CatalogApplication = {
      ...missionCommsApplication,
      applicationKey: "unlisted_application",
      displayName: "Unlisted application",
      package: { packageId: "example.unlisted-application", version: 3 },
      surface: {
        ...missionCommsApplication.surface,
        surfaceId: "unlisted_surface",
        dataContract: { id: "example.unlisted-application.surface", version: 1 },
      },
      release: {
        ...missionCommsApplication.release,
        releaseId: "unlisted-release-v1",
        remoteName: "example_unlisted_application",
        manifestUrl: "/assets/application-host/unlisted-application/mf-manifest.json",
      },
    };
    const unknownCatalog = { ...missionCatalog, applications: [unknownApplication] };
    const config: PhoenixHostConfig = {
      ...missionConfig,
      applicationKey: unknownApplication.applicationKey,
      surfaceId: unknownApplication.surface.surfaceId,
    };
    const fetcher = vi.fn(async () => Response.json(unknownCatalog));

    const catalog = await loadPhoenixApplicationCatalog(config, {
      fetch: fetcher as typeof fetch,
    });

    expect(selectPhoenixApplication(catalog, config)).toEqual(unknownApplication);
  });

  it("selects the requested spacecraft telemetry surface and requests exact context", async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL) => {
      expect(input).toBe(
        "/api/cadence/application-host/v1/catalog?mission_id=mission-1&spacecraft_id=spacecraft-1",
      );
      return Response.json(spacecraftCatalog);
    });

    const catalog = await loadPhoenixApplicationCatalog(spacecraftConfig, {
      fetch: fetcher as typeof fetch,
    });

    expect(selectPhoenixApplication(catalog, spacecraftConfig)).toEqual(
      spacecraftCatalog.applications[0],
    );
  });

  it("rejects a catalog returned for a different scope or identity", async () => {
    const wrongContext = {
      ...spacecraftCatalog,
      session: {
        ...spacecraftCatalog.session,
        context: { ...spacecraftCatalog.session.context, spacecraftId: "spacecraft-2" },
      },
    };
    const fetcher = vi.fn(async () => Response.json(wrongContext));

    await expect(
      loadPhoenixApplicationCatalog(spacecraftConfig, {
        fetch: fetcher as typeof fetch,
      }),
    ).rejects.toThrow("not scoped to the requested context");

    expect(() =>
      selectPhoenixApplication(missionCatalog, {
        applicationKey: "comms_overview",
        surfaceId: "overview",
        missionId: "mission-1",
        spacecraftId: "spacecraft-1",
      }),
    ).toThrow("not approved for spacecraft context");
  });

  it("fails closed for a missing application or surface", () => {
    expect(() =>
      selectPhoenixApplication(missionCatalog, {
        applicationKey: "missing_application",
        surfaceId: "overview",
        missionId: "mission-1",
      }),
    ).toThrow('does not provide requested application "missing_application"');

    expect(() =>
      selectPhoenixApplication(missionCatalog, {
        applicationKey: "comms_overview",
        surfaceId: "missing_surface",
        missionId: "mission-1",
      }),
    ).toThrow('does not provide requested surface "missing_surface"');
  });

  it("rejects a selected release whose module differs from the catalog surface", () => {
    const mismatchedCatalog = {
      ...missionCatalog,
      applications: [
        {
          ...missionCommsApplication,
          release: { ...missionCommsApplication.release, exposedModule: "./Other" },
        },
      ],
    } as FrontendApplicationCatalog;

    expect(() => selectPhoenixApplication(mismatchedCatalog, missionConfig)).toThrow(
      "does not match its surface renderer module",
    );
  });

  it("uses the current plugin-sdk catalog schema and rejects stale documents", async () => {
    const staleCatalog = { ...missionCatalog, schema: "cadence.frontend-catalog.v0" };
    const fetcher = vi.fn(async () => Response.json(staleCatalog));

    await expect(
      loadPhoenixApplicationCatalog(missionConfig, { fetch: fetcher as typeof fetch }),
    ).rejects.toThrow("frontend application catalog is invalid");
  });

  it("rejects a cross-origin catalog before sending credentials", async () => {
    const fetcher = vi.fn();

    await expect(
      loadPhoenixApplicationCatalog(
        { ...missionConfig, catalogUrl: "https://other.test/catalog" },
        {
          fetch: fetcher as typeof fetch,
          baseUrl: "https://cadence.test/missions/mission-1/comms",
        },
      ),
    ).rejects.toThrow("same origin");
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("adds exact context query parameters and removes stale spacecraft context", () => {
    expect(
      phoenixCatalogUrl(
        "https://cadence.test/catalog?mode=mission&spacecraft_id=old#ignored",
        { missionId: "mission-1" },
        "https://cadence.test/missions/mission-1/comms",
      ),
    ).toBe("https://cadence.test/catalog?mode=mission&mission_id=mission-1");

    expect(
      phoenixCatalogUrl(
        "/catalog",
        { missionId: "mission-1", spacecraftId: "spacecraft-1" },
        "https://cadence.test/missions/mission-1/spacecraft/spacecraft-1/applications",
      ),
    ).toBe("/catalog?mission_id=mission-1&spacecraft_id=spacecraft-1");
  });
});
