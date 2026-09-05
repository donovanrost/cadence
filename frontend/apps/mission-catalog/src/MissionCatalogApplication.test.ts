// @vitest-environment happy-dom
import "./env.d.ts";

import { flushPromises, mount } from "@vue/test-utils";
import type { CatalogApplication, HostBridge, HostContext } from "@cadence/plugin-sdk";
import { describe, expect, it, vi } from "vite-plus/test";
import MissionCatalogApplication from "./MissionCatalogApplication.vue";
import { manifest, pageSurfaces } from "./federated-application";

const context: HostContext = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["operate_mission"] },
};

function applicationFor(surfaceId: string): CatalogApplication {
  return {
    applicationKey: manifest.application.applicationKey,
    applicationVersion: manifest.application.version,
    displayName: manifest.application.displayName,
    description: manifest.application.description,
    package: { packageId: manifest.package.packageId, version: manifest.package.version },
    surface: manifest.surfaces.find((surface) => surface.surfaceId === surfaceId)!,
    release: {
      federation: "module_federation",
      releaseId: "mission-catalog-v1",
      remoteName: "cadence_mission_catalog",
      manifestUrl: "/assets/application-host/mission-catalog/mf-manifest.json",
      exposedModule: "./Application",
    },
  };
}

function bridgeFor(query: HostBridge["query"], execute: HostBridge["execute"] = vi.fn()) {
  return { query, execute, subscribe: vi.fn() };
}

describe("Mission and catalog federated application adapter", () => {
  it("mounts every published surface and uses its declared Phoenix query", async () => {
    const componentNames = [
      "MissionList",
      "MissionNew",
      "MissionOverview",
      "MissionApplicationsPage",
      "CatalogIndex",
      "CatalogDatabaseNew",
      "CatalogDatabaseShow",
      "CatalogRevisionShow",
      "CatalogArtifactShowPage",
      "CatalogImportRunShow",
    ];

    for (const surface of pageSurfaces) {
      const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
      const wrapper = mount(MissionCatalogApplication, {
        props: {
          application: applicationFor(surface.surfaceId),
          surface,
          context,
          bridge: bridgeFor(query as HostBridge["query"]),
        },
        global: {
          stubs: Object.fromEntries(
            componentNames.map((name) => [name, { template: "<span />" }]),
          ),
        },
      });

      await flushPromises();

      expect(query).toHaveBeenCalledWith({
        queryId: surface.dataContract.id,
        version: surface.dataContract.version,
        context,
      });
      expect(wrapper.find(`[data-surface-id="${surface.surfaceId}"]`).exists()).toBe(true);
      wrapper.unmount();
    }
  });

  it("forwards a mounted application mutation using the declared bridge action", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "mission_applications")!;
    const execute = vi.fn<HostBridge["execute"]>().mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: {},
    });
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const wrapper = mount(MissionCatalogApplication, {
      props: {
        application: applicationFor("mission_applications"),
        surface,
        context,
        bridge: bridgeFor(query as HostBridge["query"], execute as HostBridge["execute"]),
      },
      global: {
        stubs: {
          MissionApplicationsPage: {
            template: `<button id="install" @click="$emit('install', { key: 'telemetry_decom' })" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#install").trigger("click");
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "mission_catalog",
      applicationVersion: 1,
      actionId: "install",
      input: { key: "telemetry_decom" },
      context,
    });
    expect(query).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });
});
