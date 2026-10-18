import { fixtureFeaturePort } from "../../../test-support/feature-port";
import { required } from "../../../test-support/required";
import type { PacketPort } from "@cadence/telemetry-decom/packet-bindings";
import "./env.d.ts";

import { flushPromises, mount } from "@vue/test-utils";
import {
  assertReleaseMatchesModule,
  type CatalogApplication,
  type HostBridge,
  type HostQueryRequest,
  type HostActionRequest,
  type HostActionReceipt,
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
    surface: required(manifest.surfaces.find((surface) => surface.surfaceId === surfaceId)),
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
      const query = vi.fn<(request: HostQueryRequest) => Promise<unknown>>().mockResolvedValue({});
      const wrapper = mount(TelemetryDecomApplication, {
        props: {
          application: applicationFor(surface.surfaceId),
          surface,
          context,
          bridge: bridgeFor(query),
        },
        global: {
          stubs: {
            TelemetryDecomManage: { template: "<span />" },
            PacketBindingsSurface: { template: "<span />" },
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

  it("passes the public packet feature a scoped read, navigation and idempotent action port", async () => {
    const surface = required(
      manifest.surfaces.find((item) => item.surfaceId === "packet_bindings"),
    );
    const receipt = { receiptId: "receipt-1", completedAt: "2026-09-04T00:00:00Z", result: {} };
    const execute = vi
      .fn<(request: HostActionRequest<unknown>) => Promise<HostActionReceipt<unknown>>>()
      .mockResolvedValue(receipt);
    const query = vi
      .fn<(request: HostQueryRequest) => Promise<unknown>>()
      .mockResolvedValue({ trusted_surface: { contract_version: 1 } });
    const navigate = vi.fn();
    const wrapper = mount(TelemetryDecomApplication, {
      props: {
        application: applicationFor("packet_bindings"),
        surface,
        context,
        bridge: { ...bridgeFor(query, execute), navigate },
      },
      global: {
        stubs: {
          PacketBindingsSurface: {
            name: "PacketBindingsSurface",
            props: ["document", "port", "hostContext"],
            template: "<span />",
          },
        },
      },
    });
    await flushPromises();
    const feature = wrapper.findComponent({ name: "PacketBindingsSurface" });
    expect(feature.props("document")).toEqual({ contract_version: 1 });
    expect(feature.props("hostContext")).toEqual(context);
    const port = fixtureFeaturePort(feature.props("port"));
    const input: Parameters<PacketPort["save"]>[0] = {
      expected_review: "review-1",
      expected_configuration_version: 1,
      input_id: "telemetry-fields",
      input_version: 1,
      catalog_revision_id: "catalog-1",
      source_endpoint_ref: "endpoint-1",
      selected_packet_ids: ["packet-1"],
    };
    await expect(port.save(input, "stable-retry-key")).resolves.toEqual(receipt);
    expect(execute).toHaveBeenCalledWith({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      surfaceId: "packet_bindings",
      surfaceVersion: 1,
      actionId: "save_packet_bindings",
      input,
      idempotencyKey: "stable-retry-key",
      context,
    });
    await expect(port.read()).resolves.toEqual({ contract_version: 1 });
    expect(query).toHaveBeenLastCalledWith({
      queryId: "cadence.packet_bindings.manage",
      version: 1,
      context,
    });
    expect(query).toHaveBeenCalledTimes(2);
    port.navigate("/scoped-packet-page");
    expect(navigate).toHaveBeenCalledWith("/scoped-packet-page");
    wrapper.unmount();
  });

  it("shows rejected actions without replacing the current surface", async () => {
    const surface = required(manifest.surfaces.find((item) => item.surfaceId === "manage"));
    const query = vi.fn<(request: HostQueryRequest) => Promise<unknown>>().mockResolvedValue({});
    const execute = vi
      .fn<(request: HostActionRequest<unknown>) => Promise<HostActionReceipt<unknown>>>()
      .mockRejectedValue(new Error("action denied"));
    const wrapper = mount(TelemetryDecomApplication, {
      props: {
        application: applicationFor("manage"),
        surface,
        context,
        bridge: bridgeFor(query, execute),
      },
      global: {
        stubs: {
          TelemetryDecomManage: {
            template: `<button id="save" @click="$emit('save_catalog_revision', { catalog_revision_id: 'revision-1' })" />`,
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
    const surface = required(manifest.surfaces.find((item) => item.surfaceId === "manage"));
    const query = vi.fn<(request: HostQueryRequest) => Promise<unknown>>().mockResolvedValue({});
    const first = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const second = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const execute = vi
      .fn<(request: HostActionRequest<unknown>) => Promise<HostActionReceipt<unknown>>>()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);
    const wrapper = mount(TelemetryDecomApplication, {
      props: {
        application: applicationFor("manage"),
        surface,
        context,
        bridge: bridgeFor(query, execute),
      },
      global: {
        stubs: {
          TelemetryDecomManage: {
            template: `<button id="save" @click="$emit('save_catalog_revision', { catalog_revision_id: 'revision-1' })" />`,
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
  let resolve: ((value: TResult | PromiseLike<TResult>) => void) | undefined;
  const promise = new Promise<TResult>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve: required(resolve) };
}

// SDK interop: these mocks return unknown documents, which the feature adapter must admit.
function bridgeFor(
  query: (request: HostQueryRequest) => Promise<unknown>,
  execute: (
    request: HostActionRequest<unknown>,
  ) => Promise<HostActionReceipt<unknown>> = async () => {
    throw Error("Unexpected action");
  },
): HostBridge {
  return {
    query: async <TResult>(request: HostQueryRequest) => (await query(request)) as TResult,
    execute: async <TInput, TResult>(request: HostActionRequest<TInput>) =>
      (await execute(request)) as HostActionReceipt<TResult>,
    subscribe: vi.fn(),
  };
}

it.each(["unknown", "toString", "constructor", "__proto__"])(
  "rejects unsupported renderer %s before querying",
  async (surfaceId) => {
    const valid = required(manifest.surfaces[0]);
    const query = vi.fn<() => Promise<never>>().mockRejectedValue(new Error("unexpected query"));
    const wrapper = mount(TelemetryDecomApplication, {
      props: {
        application: applicationFor(valid.surfaceId),
        surface: { ...valid, surfaceId },
        context,
        bridge: bridgeFor(query),
      },
    });
    await flushPromises();
    expect(query).not.toHaveBeenCalled();
    expect(wrapper.find("#telemetry-decom-error").exists()).toBe(true);
    wrapper.unmount();
  },
);
