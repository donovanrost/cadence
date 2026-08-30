import { describe, expect, it, vi } from "vite-plus/test";
import type { FrontendApplicationCatalog } from "@cadence/plugin-sdk";
import {
  loadPhoenixMissionCatalog,
  phoenixCatalogUrl,
  selectCommsOverviewApplication,
} from "./phoenix-catalog-client";

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

describe("Phoenix mission catalog bootstrap", () => {
  it("adds the active mission to a same-origin catalog URL and preserves credentials", async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(input).toBe("/api/cadence/application-host/v1/catalog?mission_id=mission-1");
      expect(init).toEqual({ credentials: "same-origin", cache: "no-store" });
      return Response.json(catalog);
    });

    await expect(
      loadPhoenixMissionCatalog(
        { missionId: "mission-1", catalogUrl: "/api/cadence/application-host/v1/catalog" },
        { fetch: fetcher as typeof fetch },
      ),
    ).resolves.toEqual(catalog);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("accepts an absolute same-origin catalog URL and rejects a different mission", async () => {
    expect(
      phoenixCatalogUrl(
        "https://cadence.test/catalog?mode=mission",
        "mission-1",
        "https://cadence.test/missions/mission-1/comms",
      ),
    ).toBe("https://cadence.test/catalog?mode=mission&mission_id=mission-1");

    const wrongMission = {
      ...catalog,
      session: {
        ...catalog.session,
        context: { ...catalog.session.context, missionId: "mission-2" },
      },
    };
    const fetcher = vi.fn(async () => Response.json(wrongMission));

    await expect(
      loadPhoenixMissionCatalog(
        { missionId: "mission-1", catalogUrl: "/catalog" },
        { fetch: fetcher as typeof fetch },
      ),
    ).rejects.toThrow("not scoped to the active mission");
  });

  it("fails closed when the selected comms identity is not exact", () => {
    expect(selectCommsOverviewApplication(catalog)).toBe(catalog.applications[0]);
    expect(() =>
      selectCommsOverviewApplication({
        ...catalog,
        applications: [
          {
            ...catalog.applications[0],
            surface: { ...catalog.applications[0].surface, actions: ["unexpected_action"] },
          },
        ],
      }),
    ).toThrow("contract is invalid");
  });

  it("rejects cross-origin catalogs before sending credentials", () => {
    expect(() => phoenixCatalogUrl("https://other.test/catalog", "mission-1")).toThrow(
      "same origin",
    );
  });
});
