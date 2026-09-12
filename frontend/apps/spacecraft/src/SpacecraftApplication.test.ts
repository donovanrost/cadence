import "./env.d.ts";

import { flushPromises, mount } from "@vue/test-utils";
import type {
  CatalogApplication,
  HostActionReceipt,
  HostActionRequest,
  HostBridge,
  HostContext,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
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
  // New and edit are public aliases of the same host-owned vertical feature.
  "SpacecraftIdentityForm",
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

function queryBridgeMock() {
  const mock = vi.fn((_request: HostQueryRequest) => Promise.resolve<unknown>({}));
  const bridge: HostBridge["query"] = async <TResult>(request: HostQueryRequest) =>
    (await mock(request)) as TResult;
  return { bridge, mock };
}

function actionBridgeMock() {
  const mock = vi.fn((_request: HostActionRequest<unknown>) =>
    Promise.resolve<HostActionReceipt<unknown>>({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: {},
    }),
  );
  const bridge: HostBridge["execute"] = async <_TInput, TResult>(
    request: HostActionRequest<_TInput>,
  ) => (await mock(request)) as HostActionReceipt<TResult>;
  return { bridge, mock };
}

function bridgeFor(query: HostBridge["query"], execute: HostBridge["execute"]) {
  return {
    query,
    execute,
    subscribe: vi.fn(),
  };
}

describe("Spacecraft federated application adapter", () => {
  it("publishes one app-level renderer for every surface and queries its declared contract", async () => {
    for (const surfaceId of surfaceIds) {
      const surface = manifest.surfaces.find((item) => item.surfaceId === surfaceId)!;
      const { bridge: query, mock: queryMock } = queryBridgeMock();
      const wrapper = mount(SpacecraftApplication, {
        props: {
          application: applicationFor(surfaceId),
          surface,
          context,
          bridge: bridgeFor(query, actionBridgeMock().bridge),
        },
        global: {
          stubs: Object.fromEntries(componentNames.map((name) => [name, { template: "<span />" }])),
        },
      });

      await flushPromises();

      expect(queryMock).toHaveBeenCalledWith({
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
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockResolvedValue({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: {},
    });
    const bridge = bridgeFor(query, execute);
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

    expect(executeMock).toHaveBeenCalledWith({
      applicationKey: "spacecraft",
      applicationVersion: 1,
      surfaceId: "applications",
      surfaceVersion: 1,
      actionId: "install",
      input: { key: "telemetry_decom" },
      context,
    });
    expect(queryMock).toHaveBeenCalledTimes(2);
    expect(wrapper.find("#spacecraft-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-1",
    );
    wrapper.unmount();
  });

  it("shows rejected actions without replacing the current surface", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "applications")!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockRejectedValue(new Error("action denied"));
    const wrapper = mount(SpacecraftApplication, {
      props: {
        application: applicationFor("applications"),
        surface,
        context,
        bridge: bridgeFor(query, execute),
      },
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

    expect(wrapper.find("#spacecraft-action-error").text()).toContain("action denied");
    expect(queryMock).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it("keeps the newest overlapping action receipt and refresh authoritative state", async () => {
    const surface = manifest.surfaces.find((item) => item.surfaceId === "applications")!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const first = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const second = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    const bridge = bridgeFor(query, execute);
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
    await wrapper.get("#install").trigger("click");
    second.resolve({ receiptId: "receipt-2", completedAt: "2026-09-04T00:00:02Z", result: {} });
    await flushPromises();
    first.resolve({ receiptId: "receipt-1", completedAt: "2026-09-04T00:00:01Z", result: {} });
    await flushPromises();

    expect(wrapper.find("#spacecraft-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-2",
    );
    expect(queryMock).toHaveBeenCalledTimes(2);
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

it.each(["unknown", "toString", "constructor", "__proto__"])(
  "rejects unsupported renderer %s before querying",
  async (surfaceId) => {
    const valid = manifest.surfaces[0]!;
    const query = vi.fn<() => Promise<never>>().mockRejectedValue(new Error("unexpected query"));
    const wrapper = mount(SpacecraftApplication, {
      props: {
        application: applicationFor(valid.surfaceId),
        surface: { ...valid, surfaceId },
        context,
        bridge: { query, execute: vi.fn(), subscribe: vi.fn() },
      },
    });
    await flushPromises();
    expect(query).not.toHaveBeenCalled();
    expect(wrapper.find("#spacecraft-error").exists()).toBe(true);
    wrapper.unmount();
  },
);
