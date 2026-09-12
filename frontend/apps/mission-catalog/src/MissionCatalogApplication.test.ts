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
          stubs: Object.fromEntries(componentNames.map((name) => [name, { template: "<span />" }])),
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
      surfaceId: "mission_applications",
      surfaceVersion: 1,
      actionId: "install",
      input: { key: "telemetry_decom" },
      context,
    });
    expect(query).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#mission-catalog-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-1",
    );
    expect(wrapper.find("#mission-catalog-action-notice").attributes("data-completed-at")).toBe(
      "2026-09-04T00:00:00Z",
    );
    wrapper.unmount();
  });

  it("shows rejected actions without replacing the current surface", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "mission_applications")!;
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const execute = vi.fn<HostBridge["execute"]>().mockRejectedValue(new Error("action denied"));
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

    expect(wrapper.find("#mission-catalog-action-error").text()).toContain("action denied");
    expect(wrapper.find(`[data-surface-id="mission_applications"]`).exists()).toBe(true);
    expect(query).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it("keeps the newest overlapping action receipt and refresh authoritative state", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "mission_applications")!;
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const first = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const second = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const execute = vi
      .fn<HostBridge["execute"]>()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);
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
    await wrapper.get("#install").trigger("click");
    second.resolve({ receiptId: "receipt-2", completedAt: "2026-09-04T00:00:02Z", result: {} });
    await flushPromises();
    first.resolve({ receiptId: "receipt-1", completedAt: "2026-09-04T00:00:01Z", result: {} });
    await flushPromises();

    expect(wrapper.find("#mission-catalog-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-2",
    );
    expect(query).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it("ignores a late action receipt after the remote unmounts", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "mission_applications")!;
    const query = vi.fn<HostBridge["query"]>().mockResolvedValue({});
    const action = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const execute = vi.fn<HostBridge["execute"]>().mockReturnValue(action.promise);
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
    wrapper.unmount();
    action.resolve({ receiptId: "late-receipt", completedAt: "2026-09-04T00:00:03Z", result: {} });
    await flushPromises();

    expect(query).toHaveBeenCalledTimes(1);
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

it.each(["unknown", "toString", "constructor", "__proto__"])(
  "rejects unsupported renderer %s before querying",
  async (surfaceId) => {
    const valid = manifest.surfaces[0]!;
    const query = vi.fn<() => Promise<never>>().mockRejectedValue(new Error("unexpected query"));
    const wrapper = mount(MissionCatalogApplication, {
      props: {
        application: applicationFor(valid.surfaceId),
        surface: { ...valid, surfaceId },
        context,
        bridge: { query, execute: vi.fn(), subscribe: vi.fn() },
      },
    });
    await flushPromises();
    expect(query).not.toHaveBeenCalled();
    expect(wrapper.find("#mission-catalog-error").exists()).toBe(true);
    wrapper.unmount();
  },
);
