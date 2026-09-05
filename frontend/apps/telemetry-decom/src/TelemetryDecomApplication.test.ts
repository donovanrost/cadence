import "./env.d.ts";

import { flushPromises, mount } from "@vue/test-utils";
import {
  assertReleaseMatchesModule,
  type CatalogApplication,
  type HostBridge,
  type HostContext,
} from "@cadence/plugin-sdk";
import { describe, expect, it, vi } from "vite-plus/test";
import TelemetryDecomApplication from "./TelemetryDecomApplication.vue";
import { manifest } from "./federated-application";

const phoenixSurfaceContracts = {
  manage: {
    surfaceId: "manage",
    version: 1,
    purpose: "configuration",
    scope: "spacecraft",
    placement: "application_workspace",
    navigation: { label: "Manage", order: 30 },
    dataContract: { id: "cadence.telemetry_decom.manage", version: 1 },
    actions: ["save_configuration", "request_activation", "disable"],
    renderer: { kind: "federated-vue", exposedModule: "./Application" },
  },
  packet_bindings: {
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
} as const;

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

function phoenixApplicationFor(
  surfaceId: keyof typeof phoenixSurfaceContracts,
): CatalogApplication {
  return {
    applicationKey: "telemetry_decom",
    applicationVersion: 1,
    displayName: "Telemetry Decom",
    description: "Bind packet fields and decode selected inputs into named telemetry points.",
    package: { packageId: "cadence.telemetry-applications", version: 1 },
    surface: phoenixSurfaceContracts[surfaceId],
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
  it("matches every Phoenix-approved exported surface before mount", () => {
    for (const surfaceId of ["manage", "packet_bindings"] as const) {
      expect(() =>
        assertReleaseMatchesModule(phoenixApplicationFor(surfaceId), {
          manifest,
          default: TelemetryDecomApplication,
        }),
      ).not.toThrow();
    }
  });

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
      surfaceId: "packet_bindings",
      surfaceVersion: 1,
      actionId: "save_packet_bindings",
      input: { selected_packet_ids: ["packet-1"] },
      context,
    });
    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#telemetry-decom-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-1",
    );
    wrapper.unmount();
  });

  it("shows rejected actions without replacing the current surface", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "packet_bindings")!;
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const execute = vi.fn<HostBridge["execute"]>().mockRejectedValue(new Error("action denied"));
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

    expect(wrapper.find("#telemetry-decom-action-error").text()).toContain("action denied");
    expect(query).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it("keeps the newest overlapping action receipt and refresh authoritative state", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "packet_bindings")!;
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const first = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const second = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const execute = vi
      .fn<HostBridge["execute"]>()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);
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
    await wrapper.get("#save").trigger("click");
    second.resolve({ receiptId: "receipt-2", completedAt: "2026-09-04T00:00:02Z", result: {} });
    await flushPromises();
    first.resolve({ receiptId: "receipt-1", completedAt: "2026-09-04T00:00:01Z", result: {} });
    await flushPromises();

    expect(wrapper.find("#telemetry-decom-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-2",
    );
    expect(query).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });
});

function deferred<TResult>() {
  let resolve!: (value: TResult | PromiseLike<TResult>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<TResult>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}
