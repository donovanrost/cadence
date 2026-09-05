import "./env.d.ts";

import { flushPromises, mount } from "@vue/test-utils";
import type { CatalogApplication, HostBridge, HostContext } from "@cadence/plugin-sdk";
import { describe, expect, it, vi } from "vite-plus/test";
import TelemetryDecomApplication from "./TelemetryDecomApplication.vue";
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
      releaseId: "telemetry-decom-v1",
      remoteName: "cadence_telemetry_decom",
      manifestUrl: "/assets/application-host/telemetry-decom/mf-manifest.json",
      exposedModule: "./Application",
    },
  };
}

describe("Telemetry Decom federated application adapter", () => {
  it("mounts both published surfaces and uses each declared query", async () => {
    for (const surface of manifest.surfaces) {
      const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
      const wrapper = mount(TelemetryDecomApplication, {
        props: {
          application: applicationFor(surface.surfaceId),
          surface,
          context,
          bridge: { query, execute: vi.fn(), subscribe: vi.fn() },
        },
        global: {
          stubs: {
            TelemetryDecomManage: { template: "<span />" },
            ApplicationHost: { template: "<span />" },
          },
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

  it("maps the packet bindings action event to the declared bridge action", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "packet_bindings")!;
    const execute = vi.fn<HostBridge["execute"]>().mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: {},
    });
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const wrapper = mount(TelemetryDecomApplication, {
      props: {
        application: applicationFor("packet_bindings"),
        surface,
        context,
        bridge: { query, execute, subscribe: vi.fn() },
      },
      global: {
        stubs: {
          ApplicationHost: {
            template: `<button id="save" @click="$emit('application_action', { application_action: { selected_packet_ids: ['packet-1'] } })" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#save").trigger("click");
    await flushPromises();

    expect(execute).toHaveBeenCalledWith({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: "save_packet_bindings",
      input: { selected_packet_ids: ["packet-1"] },
      context,
    });
    expect(query).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });
});
