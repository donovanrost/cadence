import "./env.d.ts";

import { flushPromises, mount } from "@vue/test-utils";
import type { CatalogApplication, HostBridge, HostContext } from "@cadence/plugin-sdk";
import { describe, expect, it, vi } from "vite-plus/test";
import SpacecraftApplication from "./SpacecraftApplication.vue";
import { manifest } from "./federated-application";

const context: HostContext = {
  scope: "spacecraft",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: "spacecraft-1",
  spacecraftName: "FB-1",
  actor: { displayName: "Mara Vance", permissions: ["operate_mission"] },
};

const surfaceIds = [
  "list",
  "new",
  "profile_list",
  "profile_new",
  "profile_show",
  "show",
  "edit",
  "readiness",
  "routing",
  "commanding",
  "applications",
  "telemetry_decom",
] as const;

const componentNames = [
  "SpacecraftListPage",
  "SpacecraftNew",
  "SpacecraftTypeListPage",
  "SpacecraftTypeNew",
  "SpacecraftTypeShow",
  "SpacecraftShow",
  "SpacecraftEdit",
  "SpacecraftReadiness",
  "SpacecraftRouting",
  "SpacecraftCommanding",
  "SpacecraftApplicationsPage",
  "SpacecraftTelemetryDecom",
];

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
      releaseId: "spacecraft-v1",
      remoteName: "cadence_spacecraft",
      manifestUrl: "/assets/application-host/spacecraft/mf-manifest.json",
      exposedModule: "./Application",
    },
  };
}

function bridgeFor(query: HostBridge["query"]) {
  return {
    query,
    execute: vi.fn<HostBridge["execute"]>().mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: {},
    }),
    subscribe: vi.fn(),
  };
}

describe("Spacecraft federated application adapter", () => {
  it("publishes one app-level renderer for every surface and queries its declared contract", async () => {
    for (const surfaceId of surfaceIds) {
      const surface = manifest.surfaces.find((item) => item.surfaceId === surfaceId)!;
      const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
      const wrapper = mount(SpacecraftApplication, {
        props: { application: applicationFor(surfaceId), surface, context, bridge: bridgeFor(query) },
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
      expect(wrapper.find(`[data-surface-id="${surfaceId}"]`).exists()).toBe(true);
      wrapper.unmount();
    }
  });

  it("forwards a mounted mutation through the selected surface action contract", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "applications")!;
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const bridge = bridgeFor(query);
    const wrapper = mount(SpacecraftApplication, {
      props: { application: applicationFor("applications"), surface, context, bridge },
      global: {
        stubs: {
          SpacecraftApplicationsPage: {
          template: `<button id="install" @click="$emit('install', { key: 'telemetry_decom' })" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#install").trigger("click");
    await flushPromises();

    expect(bridge.execute).toHaveBeenCalledWith({
      applicationKey: "spacecraft",
      applicationVersion: 1,
      actionId: "install",
      input: { key: "telemetry_decom" },
      context,
    });
    expect(query).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });
});
